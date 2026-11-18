import 'package:flutter/rendering.dart';
import 'package:flutter_scene/scene.dart';
import 'package:flutter/services.dart';
import 'package:gltfx/gltfx.dart';
import 'package:gltfx_ext_vrm/gltfx_ext_vrm.dart' as vrmext;

import 'spring_bone.dart';
import 'vrm.dart';
import 'mtoon.dart';
import 'node_constraint.dart';

Future<Node> loadVrmAsset(String name) async {
  final blob = await rootBundle.load(name);
  return loadVrmBytes(blob.buffer.asUint8List());
}

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
