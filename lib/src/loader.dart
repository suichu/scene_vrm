import 'package:flutter_scene/scene.dart';
import 'package:flutter/services.dart';
import 'package:gltfx/gltfx.dart';
import 'package:gltfx_ext_vrm/gltfx_ext_vrm.dart' as vrmext;

import 'gltfhelper.dart';
import 'rest_transform.dart';
import 'spring_bone.dart';
import 'vrm.dart';
import 'mtoon.dart';

Future<Node> loadVrmAsset(String name) async {
  final blob = await rootBundle.load(name);
  return loadVrmBytes(blob.buffer.asUint8List());
}

Future<Node> loadVrmBytes(Uint8List blob) async {
  final root = await Node.fromGlbBytes(blob);
  final doc = Glb.parse(blob, extensions: [...vrmext.vrmc, vrmext.vrm]);

  for (final nd in doc.nodes.values) {
    if (nd.name case final name?) {
      if (root.getChildByName(name) case final n?) {
        n.addComponent(
          RestTransform(
            local: getNodeMatrix(nd),
            world: getNodeWorldMatrix(doc, nd),
          ),
        );
      }
    }
  }

  final srcVrm = doc.extensions?.get(vrmext.vrmcVrm);
  if (srcVrm != null) {
    _loadVrm(doc, srcVrm, root);
  } else {
    final srcVrm = doc.extensions?.get(vrmext.vrm);
    if (srcVrm != null) {
      _loadVrm0x(doc, srcVrm, root);
    }
  }

  await loadMToon(doc, root);
  return root;
}

void _loadVrm(GltfDocument doc, vrmext.VrmcVrm vrm, Node root) {
  final humanoid = Vrm.import(vrm, document: doc, root: root);
  root.addComponent(humanoid);

  final springBone = doc.extensions?.get(vrmext.vrmcSpringBone);
  if (springBone != null) {
    final simulator = SpringBoneSimulator.fromDocument(doc, springBone, root);
    if (simulator != null) root.addComponent(simulator);
  }
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
