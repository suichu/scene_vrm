import 'package:flutter/rendering.dart';
import 'package:flutter_scene/scene.dart';
import 'package:flutter/services.dart';
import 'package:gltfx/gltfx.dart';
import 'package:gltfx_ext_vrm/gltfx_ext_vrm.dart' as vrmext;

import 'spring_bone.dart';
import 'vrm.dart';
import 'mtoon.dart';
import 'node_constraint.dart';

/// Loads a VRM model from the asset bundle.
///
/// [name] is the asset key passed to [rootBundle]. See [loadVrmBytes] for
/// what is set up on the returned node.
Future<Node> loadVrmAsset(String name) async {
  final blob = await rootBundle.load(name);
  return loadVrmBytes(blob.buffer.asUint8List());
}

/// Loads a VRM model from GLB bytes.
///
/// Both VRM 0.x (`VRM` extension) and VRM 1.0 (`VRMC_vrm` extension) are
/// supported. The returned root node has a [Vrm] component attached, along
/// with spring bone simulation, node constraints (1.0 only) and MToon
/// materials when the model defines them.
Future<Node> loadVrmBytes(Uint8List blob) async {
  final root = await Node.fromGlbBytes(blob);
  debugPrint("${root.children.map((c) => c.name)}");

  final doc = Glb.parse(blob, extensions: [...vrmext.vrmc, vrmext.vrm]);

  final vrm0 = doc.extensions?.get(vrmext.vrm);

  if (vrm0 != null) {
    _loadVrm0x(doc, vrm0, root);
    return root;
  }

  final srcVrm = doc.extensions?.get(vrmext.vrmcVrm);
  if (srcVrm != null) {
    final humanoid = Vrm.import(srcVrm, document: doc, root: root);
    root.addComponent(humanoid);
  }

  loadNodeConstraint(document: doc, root: root);

  final springBone = doc.extensions?.get(vrmext.vrmcSpringBone);

  if (springBone != null) {
    final simulator = SpringBoneSimulator.fromDocument(doc, springBone, root);
    if (simulator != null) root.addComponent(simulator);
  }

  await loadMToon(doc, root);

  return root;
}

void _loadVrm0x(GltfDocument doc, vrmext.Vrm vrm, Node root) {
  final humanoid = Vrm.import0(vrm, document: doc, root: root);
  root.addComponent(humanoid);

  final secondary = vrm.secondaryAnimation;
  if (secondary != null) {
    final simulator = SpringBoneSimulator.fromVrm0(doc, secondary, root);
    if (simulator != null) root.addComponent(simulator);
  }
}
