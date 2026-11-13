import 'package:flutter_scene/scene.dart';
import 'package:gltfx/gltfx.dart';
import 'package:gltfx_ext_vrm/gltfx_ext_vrm.dart' as vrmext;

class NodeConstraint extends Component {
  Node source;
  vrmext.NodeConstraint constraint;

  NodeConstraint({required this.source, required this.constraint});

  @override
  void update(double deltaSeconds) {}

  factory NodeConstraint.import(
    vrmext.VrmcNodeConstraint data, {
    required GltfDocument document,
    required Node root,
  }) {
    return NodeConstraint(
      source: root.getChildByName(
        document.nodes[data.constraint.source].name!,
      )!,
      constraint: data.constraint,
    );
  }
}
