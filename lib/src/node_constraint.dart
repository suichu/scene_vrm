import 'package:flutter/widgets.dart' show debugPrint;
import 'package:flutter_scene/scene.dart';
import 'package:gltfx/gltfx.dart';
import 'package:gltfx_ext_vrm/gltfx_ext_vrm.dart' as vrmext;
import 'package:vector_math/vector_math.dart';

class AimConstraint extends NodeConstraint {
  final vrmext.AimAxis axis;
  final Quaternion _destinationRestPose;
  final Vector3 _aimAxis;

  AimConstraint({
    required super.destination,
    required super.source,
    required super.weight,
    required this.axis,
  }) : _destinationRestPose = destination.rotation.clone(),
       _aimAxis = switch (axis) {
         vrmext.AimAxis.positiveX => Vector3(1, 0, 0),
         vrmext.AimAxis.positiveY => Vector3(0, 1, 0),
         vrmext.AimAxis.positiveZ => Vector3(0, 0, 1),
         vrmext.AimAxis.negativeX => Vector3(-1, 0, 0),
         vrmext.AimAxis.negativeY => Vector3(0, -1, 0),
         vrmext.AimAxis.negativeZ => Vector3(0, 0, -1),
       };

  @override
  void apply() {
    final aimAxis = _aimAxis;

    final dstRestQuat = _destinationRestPose;
    final dstParentWorldQuat = Quaternion.identity();

    destination.parent!.globalTransform.decompose(
      Vector3.zero(),
      dstParentWorldQuat,
      Vector3.zero(),
    );

    final worldMatrixInverted =
        destination.parent!.globalTransform.getRotation()
          ..multiply(dstParentWorldQuat.conjugated().asRotationMatrix())
          ..invert();

    final srcWorldPos = source.globalTransform.getTranslation();
    final dstWorldPos = destination.globalTransform.getTranslation();

    final fromVec = (dstParentWorldQuat * dstRestQuat).conjugated().rotated(
      aimAxis,
    );
    final toVec = worldMatrixInverted.transform(srcWorldPos - dstWorldPos);
    final fromToQuat = Quaternion.fromTwoVectors(fromVec, toVec);

    final targetQuat = dstRestQuat.slerp(
      (dstParentWorldQuat.conjugated() *
          fromToQuat *
          dstParentWorldQuat *
          dstRestQuat),
      weight,
    );

    destination.rotation = targetQuat;
  }
}

class RollConstraint extends NodeConstraint {
  final vrmext.RollAxis axis;
  final Quaternion _sourceRestPose;
  final Quaternion _destinationRestPose;
  final Vector3 _rollAxis;

  RollConstraint({
    required super.destination,
    required super.source,
    required super.weight,
    required this.axis,
  }) : _sourceRestPose = source.rotation.clone(),
       _destinationRestPose = destination.rotation.clone(),
       _rollAxis = switch (axis) {
         vrmext.RollAxis.x => Vector3(1, 0, 0),
         vrmext.RollAxis.y => Vector3(0, 1, 0),
         vrmext.RollAxis.z => Vector3(0, 0, 1),
       };

  @override
  void apply() {
    final srcRestQuat = _sourceRestPose;
    final dstRestQuat = _destinationRestPose;
    final srcRestQuatInverted = srcRestQuat.conjugated();
    final dstRestQuatInverted = dstRestQuat.conjugated();

    final deltaSrcQuat = srcRestQuatInverted * source.rotation;
    final deltaSrcQuatInParent =
        srcRestQuat * deltaSrcQuat * srcRestQuatInverted;
    final deltaSrcQuatInDest =
        dstRestQuatInverted * deltaSrcQuatInParent * dstRestQuat;

    final rollAxis = _rollAxis;
    final toVec = deltaSrcQuatInDest.conjugated().rotated(rollAxis);
    final fromTo = Quaternion.fromTwoVectors(rollAxis, toVec);
    final target = dstRestQuat.slerp(
      dstRestQuat * fromTo.conjugated() * deltaSrcQuatInDest,
      weight,
    );
    destination.rotation = target;
  }
}

class RotationConstraint extends NodeConstraint {
  final Quaternion _sourceRestPose;
  final Quaternion _destinationRestPose;

  RotationConstraint({
    required super.destination,
    required super.source,
    required super.weight,
  }) : _sourceRestPose = source.rotation.clone(),
       _destinationRestPose = destination.rotation.clone();

  @override
  void apply() {
    final srcRestQuatInverted = _sourceRestPose.conjugated();
    final destRestQuat = _destinationRestPose;

    final srcDeltaQuat = srcRestQuatInverted * source.rotation;
    final targetQuat = destRestQuat.slerp(destRestQuat * srcDeltaQuat, weight);

    destination.rotation = targetQuat;
  }
}

/// A single VRMC_node_constraint entry.
///
/// Constraints are evaluated by [NodeConstraintSolver] so that they run in
/// dependency order, not in scene traversal order.
sealed class NodeConstraint {
  final Node destination;
  final Node source;
  final double weight;

  NodeConstraint({
    required this.destination,
    required this.source,
    this.weight = 1.0,
  });

  static NodeConstraint import(
    vrmext.VrmcNodeConstraint data, {
    required Node destination,
    required GltfDocument document,
    required Node root,
  }) {
    final c = data.constraint;
    final sourceName = document.nodes[c.source].name;
    final source = sourceName == null ? null : root.getChildByName(sourceName);
    if (source == null) {
      throw StateError('source node not found (index: ${c.source})');
    }
    if (identical(source, destination)) {
      throw StateError('source and destination must be different nodes');
    }
    final weight = c.weight.clamp(0.0, 1.0).toDouble();
    return switch (c) {
      vrmext.AimNodeConstraint() => AimConstraint(
        destination: destination,
        source: source,
        weight: weight,
        axis: c.aimAxis,
      ),
      vrmext.RollNodeConstraint() => RollConstraint(
        destination: destination,
        source: source,
        weight: weight,
        axis: c.rollAxis,
      ),
      vrmext.RotationNodeConstraint() => RotationConstraint(
        destination: destination,
        source: source,
        weight: weight,
      ),
    };
  }

  /// Writes the constrained rotation to [destination].
  void apply();
}

class NodeConstraintSolver extends Component {
  final List<NodeConstraint> constraints;

  NodeConstraintSolver(this.constraints);

  @override
  void update(double deltaSeconds) {
    for (final c in constraints) {
      c.apply();
    }
  }
}

/// Orders [constraints] so that every constraint is evaluated after the
/// constraints it depends on. Constraints that take part in a circular
/// dependency are dropped.
List<NodeConstraint> _sortConstraints(List<NodeConstraint> constraints) {
  final byDestination = {for (final c in constraints) c.destination: c};

  // Nodes whose transform this constraint reads.
  Iterable<Node> dependencies(NodeConstraint c) sync* {
    yield c.source;
    if (c is AimConstraint) {
      // Aim reads world transforms, which depend on all ancestors.
      for (var n = c.source.parent; n != null; n = n.parent) {
        yield n;
      }
      for (var n = c.destination.parent; n != null; n = n.parent) {
        yield n;
      }
    }
  }

  final sorted = <NodeConstraint>[];
  final done = <NodeConstraint>{};
  final pending = <NodeConstraint>{};
  final invalid = <NodeConstraint>{};

  bool visit(NodeConstraint c) {
    if (done.contains(c)) return true;
    if (invalid.contains(c)) return false;
    if (pending.contains(c)) {
      debugPrint(
        'Circular node constraint dependency detected: '
        '${c.destination.name}',
      );
      return false;
    }
    pending.add(c);
    var ok = true;
    for (final dep in dependencies(c)) {
      if (byDestination[dep] case final d? when !identical(d, c)) {
        if (!visit(d)) ok = false;
      }
    }
    pending.remove(c);
    if (ok) {
      done.add(c);
      sorted.add(c);
    } else {
      invalid.add(c);
    }
    return ok;
  }

  for (final c in constraints) {
    visit(c);
  }
  return sorted;
}

void loadNodeConstraint({required GltfDocument document, required Node root}) {
  final constraints = <NodeConstraint>[];

  for (final nd in document.nodes.values) {
    final data = nd.extensions?.get(vrmext.vrmcNodeConstraint);
    if (data == null) continue;
    final name = nd.name;
    final destination = name == null ? null : root.getChildByName(name);
    if (destination == null) {
      debugPrint('Node constraint destination not found: $name');
      continue;
    }
    try {
      constraints.add(
        NodeConstraint.import(
          data,
          destination: destination,
          document: document,
          root: root,
        ),
      );
    } catch (err) {
      debugPrint('Failed to import node constraint for $name: $err');
    }
  }

  if (constraints.isEmpty) return;

  final solver = NodeConstraintSolver(_sortConstraints(constraints));
  root.addComponent(solver);
}
