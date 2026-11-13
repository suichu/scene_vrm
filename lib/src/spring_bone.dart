import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:gltfx/gltfx.dart';
import 'package:vector_math/vector_math.dart';
import 'package:gltfx_ext_vrm/gltfx_ext_vrm.dart' as vrmext;

import 'gltfhelper.dart';

/// SpringBone simulator for VRMC_springBone-1.0.
///
/// https://github.com/vrm-c/vrm-specification/blob/master/specification/VRMC_springBone-1.0/README.md
class SpringBoneSimulator extends Component {
  final List<SpringBoneChain> springs;

  SpringBoneSimulator(List<SpringBoneChain> springs)
    // Update joints starting from the ancestors
    : springs = [...springs]
        ..sort(
          (a, b) => _depth(a.joints.first.node) - _depth(b.joints.first.node),
        );

  static SpringBoneSimulator? fromDocument(
    GltfDocument doc,
    vrmext.VrmcSpringBone src,
    Node root,
  ) {
    Node? resolve(int idx) {
      if (idx < 0 || idx >= doc.nodes.items.length) return null;
      final name = doc.nodes[NodeIdx(idx)].name;
      return name != null ? root.getChildByName(name) : null;
    }

    final colliders = <SpringBoneCollider?>[
      for (final c in src.colliders) _buildCollider(c, resolve(c.node.value)),
    ];

    final colliderGroups = <List<SpringBoneCollider>>[
      for (final g in src.colliderGroups)
        [
          for (final i in g.colliders)
            if (i >= 0 && i < colliders.length && colliders[i] != null)
              colliders[i]!,
        ],
    ];

    final springs = <SpringBoneChain>[];
    for (final s in src.springs) {
      final nodes = s.joints.map((j) => resolve(j.node.value)).toList();
      if (nodes.contains(null)) continue;

      final joints = <SpringBoneJointState>[];
      // The last joint is used only as a tail; its parameters are not used
      for (var i = 0; i < s.joints.length - 1; i++) {
        final j = s.joints[i];
        final gravityDir = j.gravityDir;
        joints.add(
          SpringBoneJointState(
            node: nodes[i]!,
            child: nodes[i + 1]!,
            hitRadius: j.hitRadius,
            stiffness: j.stiffness,
            gravityPower: j.gravityPower,
            gravityDir: gravityDir != null && gravityDir.length >= 3
                ? Vector3(gravityDir[0], gravityDir[1], gravityDir[2])
                : Vector3(0, -1, 0),
            dragForce: j.dragForce,
          ),
        );
      }
      if (joints.isEmpty) continue;

      final center = s.center;
      springs.add(
        SpringBoneChain(
          joints: joints,
          colliders: [
            for (final g in s.colliderGroups)
              if (g >= 0 && g < colliderGroups.length) ...colliderGroups[g],
          ],
          center: center != null ? resolve(center.value) : null,
        ),
      );
    }

    if (springs.isEmpty) return null;
    return SpringBoneSimulator(springs);
  }

  /// Builds from VRM 0.x `secondaryAnimation`.
  ///
  /// A 0.x boneGroup treats each node listed in `bones` as a root and all its descendants as spring bones.
  /// Each node's tail is its first child; a leaf uses a virtual point extended 7cm in the direction from its parent.
  static SpringBoneSimulator? fromVrm0(
    GltfDocument doc,
    vrmext.VrmSecondaryAnimation src,
    Node root,
  ) {
    Node? resolve(int idx) {
      if (idx < 0 || idx >= doc.nodes.items.length) return null;
      final name = doc.nodes[NodeIdx(idx)].name;
      return name != null ? root.getChildByName(name) : null;
    }

    final colliderGroups = <List<SpringBoneCollider>>[
      for (final g in src.colliderGroups)
        if (resolve(g.node.value) case final node?)
          [
            for (final c in g.colliders)
              SpringBoneSphereCollider(
                node: node,
                // 0.x offsets are in Unity coordinates, so flip Z
                offset: Vector3(c.offset.x, c.offset.y, -c.offset.z),
                radius: c.radius,
              ),
          ]
        else
          const [],
    ];

    final springs = <SpringBoneChain>[];
    for (final group in src.boneGroups) {
      final g = group.gravityDir;
      final gravityDir = Vector3(g.x, g.y, g.z);
      final colliders = [
        for (final i in group.colliderGroups)
          if (i >= 0 && i < colliderGroups.length) ...colliderGroups[i],
      ];
      final center = group.center;

      for (final boneIdx in group.bones) {
        final rootBone = resolve(boneIdx);
        if (rootBone == null) continue;

        final joints = <SpringBoneJointState>[];
        // Order parents first (pre-order traversal)
        void visit(Node node) {
          final child = node.children.isNotEmpty ? node.children.first : null;
          joints.add(
            SpringBoneJointState(
              node: node,
              child: child,
              hitRadius: group.hitRadius,
              stiffness: group.stiffiness,
              gravityPower: group.gravityPower,
              gravityDir: gravityDir,
              dragForce: group.dragForce,
            ),
          );
          for (final c in node.children) {
            visit(c);
          }
        }

        visit(rootBone);
        springs.add(
          SpringBoneChain(
            joints: joints,
            colliders: colliders,
            center: center != null ? resolve(center.value) : null,
          ),
        );
      }
    }

    if (springs.isEmpty) return null;
    return SpringBoneSimulator(springs);
  }

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    reset();
  }

  void reset() {
    for (final spring in springs) {
      spring.reset();
    }
  }

  @override
  void fixedUpdate(double fixedDt) {
    for (final spring in springs) {
      spring.update(fixedDt);
    }
  }

  static int _depth(Node node) {
    var d = 0;
    for (var n = node.parent; n != null; n = n.parent) {
      d++;
    }
    return d;
  }
}

SpringBoneCollider? _buildCollider(
  vrmext.VrmcSpringBoneCollider src,
  Node? node,
) {
  if (node == null) return null;
  Vector3 vec(List<double>? v) =>
      v != null && v.length >= 3 ? Vector3(v[0], v[1], v[2]) : Vector3.zero();

  return switch (src.shape) {
    vrmext.VrmcSpringBoneColliderSphere sphere => SpringBoneSphereCollider(
      node: node,
      offset: vec(sphere.offset),
      radius: sphere.radius,
    ),
    vrmext.VrmcSpringBoneColliderCapsule capsule => SpringBoneCapsuleCollider(
      node: node,
      offset: vec(capsule.offset),
      radius: capsule.radius,
      tail: vec(capsule.tail),
    ),
  };
}

/// Result of a collision test. A negative [distance] means a collision.
typedef SpringBoneCollision = ({Vector3 direction, double distance});

sealed class SpringBoneCollider {
  final Node node;
  final Vector3 offset;
  final double radius;

  SpringBoneCollider({
    required this.node,
    required this.offset,
    required this.radius,
  });

  SpringBoneCollision collide(Vector3 position, double jointRadius);
}

class SpringBoneSphereCollider extends SpringBoneCollider {
  SpringBoneSphereCollider({
    required super.node,
    required super.offset,
    required super.radius,
  });

  @override
  SpringBoneCollision collide(Vector3 position, double jointRadius) {
    final transformedOffset = node.globalTransform.transformed3(offset);
    final delta = position - transformedOffset;
    return (
      direction: delta.normalized(),
      distance: delta.length - radius - jointRadius,
    );
  }
}

class SpringBoneCapsuleCollider extends SpringBoneCollider {
  final Vector3 tail;

  SpringBoneCapsuleCollider({
    required super.node,
    required super.offset,
    required super.radius,
    required this.tail,
  });

  @override
  SpringBoneCollision collide(Vector3 position, double jointRadius) {
    final world = node.globalTransform;
    final transformedOffset = world.transformed3(offset);
    final transformedTail = world.transformed3(tail);
    final offsetToTail = transformedTail - transformedOffset;
    final delta = position - transformedOffset;
    final dot = offsetToTail.dot(delta);
    final lengthSquared = offsetToTail.length2;

    if (dot <= 0.0) {
      // Head side: same as a sphere
    } else if (dot >= lengthSquared) {
      // Tail side
      delta.sub(offsetToTail);
    } else {
      // Between head and tail: perpendicular to the segment
      delta.sub(offsetToTail * (dot / lengthSquared));
    }

    return (
      direction: delta.normalized(),
      distance: delta.length - radius - jointRadius,
    );
  }
}

class SpringBoneChain {
  final List<SpringBoneJointState> joints;
  final List<SpringBoneCollider> colliders;

  /// Space in which inertia is evaluated. World space if null.
  final Node? center;

  SpringBoneChain({required this.joints, required this.colliders, this.center});

  void reset() {
    final worldToCenter = _worldToCenter();
    for (final joint in joints) {
      joint.reset(worldToCenter);
    }
  }

  void update(double deltaTime) {
    final centerToWorld = center?.globalTransform;
    final worldToCenter = _worldToCenter();
    for (final joint in joints) {
      joint.update(deltaTime, colliders, centerToWorld, worldToCenter);
    }
  }

  Matrix4? _worldToCenter() {
    final c = center;
    if (c == null) return null;
    return Matrix4.copy(c.globalTransform)..invert();
  }
}

class SpringBoneJointState {
  /// Length of the virtual tail for leaf joints without children (7cm, same as UniVRM 0.x).
  static const double virtualTailLength = 0.07;

  final Node node;

  /// Node used as the tail. A virtual tail is used if null.
  final Node? child;

  final double hitRadius;
  final double stiffness;
  final double gravityPower;
  final Vector3 gravityDir;
  final double dragForce;

  final Matrix4 initialLocalMatrix;
  final Vector3 _initialTranslation = Vector3.zero();
  final Quaternion initialLocalRotation = Quaternion.identity();
  final Vector3 _initialScale = Vector3.zero();

  /// Local position of the tail (initial pose).
  final Vector3 _childLocalPosition;
  final Vector3 boneAxis;

  /// Position of the tail in center space.
  Vector3 currentTail = Vector3.zero();
  Vector3 prevTail = Vector3.zero();

  SpringBoneJointState._({
    required this.node,
    required this.child,
    required this.hitRadius,
    required this.stiffness,
    required this.gravityPower,
    required this.gravityDir,
    required this.dragForce,
    required this.initialLocalMatrix,
    required Vector3 childLocalPosition,
  }) : _childLocalPosition = childLocalPosition,
       boneAxis = childLocalPosition.normalized() {
    initialLocalMatrix.decompose(
      _initialTranslation,
      initialLocalRotation,
      _initialScale,
    );
  }

  factory SpringBoneJointState({
    required Node node,
    required Node? child,
    required double hitRadius,
    required double stiffness,
    required double gravityPower,
    required Vector3 gravityDir,
    required double dragForce,
  }) {
    final Vector3 childLocalPosition;
    if (child != null) {
      // child is not necessarily a direct child, so compute the local position via world coordinates
      final worldToLocal = Matrix4.copy(node.globalTransform)..invert();
      childLocalPosition = worldToLocal.transformed3(
        child.globalTransform.getTranslation(),
      );
    } else {
      childLocalPosition = _virtualTailLocalPosition(node);
    }
    return SpringBoneJointState._(
      node: node,
      child: child,
      hitRadius: hitRadius,
      stiffness: stiffness,
      gravityPower: gravityPower,
      gravityDir: gravityDir.normalized(),
      dragForce: dragForce,
      initialLocalMatrix: node.localTransform.clone(),
      childLocalPosition: childLocalPosition,
    );
  }

  /// Local position of the virtual tail for a node without children.
  ///
  /// The point extended by [virtualTailLength] in world space, in the direction from the parent to this node.
  static Vector3 _virtualTailLocalPosition(Node node) {
    final world = node.globalTransform;
    final parentWorld = node.parent?.globalTransform ?? Matrix4.identity();
    final position = world.getTranslation();
    var dir = position - parentWorld.getTranslation();
    if (dir.length2 < 1e-12) dir = Vector3(0, 1, 0);
    final tail = position + dir.normalized() * virtualTailLength;
    final worldToLocal = Matrix4.copy(world)..invert();
    return worldToLocal.transformed3(tail);
  }

  void reset(Matrix4? worldToCenter) {
    node.localTransform = initialLocalMatrix.clone();
    final tail =
        child?.globalTransform.getTranslation() ??
        node.globalTransform.transformed3(_childLocalPosition.clone());
    currentTail = worldToCenter?.transformed3(tail) ?? tail;
    prevTail = currentTail.clone();
  }

  void update(
    double deltaTime,
    List<SpringBoneCollider> colliders,
    Matrix4? centerToWorld,
    Matrix4? worldToCenter,
  ) {
    final parentWorldMatrix =
        node.parent?.globalTransform ?? Matrix4.identity();
    final restWorldMatrix = parentWorldMatrix.multiplied(initialLocalMatrix);
    final worldPosition = restWorldMatrix.getTranslation();
    final boneLength =
        (restWorldMatrix.transformed3(_childLocalPosition) - worldPosition)
            .length;

    // Inertia is evaluated in center space
    final worldCurrentTail =
        centerToWorld?.transformed3(currentTail) ?? currentTail.clone();
    final worldPrevTail =
        centerToWorld?.transformed3(prevTail) ?? prevTail.clone();

    final parentWorldRotation = Quaternion.identity();
    parentWorldMatrix.decompose(
      Vector3.zero(),
      parentWorldRotation,
      Vector3.zero(),
    );

    final inertia = (worldCurrentTail - worldPrevTail)..scale(1.0 - dragForce);
    final stiffnessForce = rotateByQuaternion(
      parentWorldRotation * initialLocalRotation,
      boneAxis,
    )..scale(deltaTime * stiffness);
    final external = gravityDir * (deltaTime * gravityPower);

    var nextTail = worldCurrentTail + inertia + stiffnessForce + external;

    // Length constraint
    nextTail = _constrainLength(nextTail, worldPosition, boneLength);

    // Collision
    for (final collider in colliders) {
      final (:direction, :distance) = collider.collide(nextTail, hitRadius);
      if (distance < 0.0) {
        nextTail.sub(direction * distance);
        nextTail = _constrainLength(nextTail, worldPosition, boneLength);
      }
    }

    prevTail = currentTail;
    currentTail = worldToCenter?.transformed3(nextTail) ?? nextTail;

    // Apply rotation
    final to = (Matrix4.copy(
      restWorldMatrix,
    )..invert()).transformed3(nextTail).normalized();
    final rotation = initialLocalRotation * _fromTo(boneAxis, to);
    node.localTransform = Matrix4.compose(
      _initialTranslation,
      rotation..normalize(),
      _initialScale,
    );
  }

  static Vector3 _constrainLength(
    Vector3 tail,
    Vector3 position,
    double boneLength,
  ) {
    final dir = tail - position;
    if (dir.length2 == 0.0) return tail;
    return position + dir.normalized() * boneLength;
  }

  static Quaternion _fromTo(Vector3 from, Vector3 to) {
    final d = from.dot(to);
    if (d >= 1.0 - 1e-7) return Quaternion.identity();
    if (d <= -1.0 + 1e-7) {
      // If opposite, rotate 180 degrees around any axis orthogonal to from
      var axis = Vector3(1, 0, 0).cross(from);
      if (axis.length2 < 1e-12) axis = Vector3(0, 1, 0).cross(from);
      return Quaternion.axisAngle(axis.normalized(), math.pi);
    }
    return Quaternion.fromTwoVectors(from, to);
  }
}
