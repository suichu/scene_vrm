import 'dart:math';

import 'package:flutter_scene/scene.dart';
import 'package:gltfx/gltfx.dart';
import 'package:vector_math/vector_math.dart';
import 'package:gltfx_ext_vrm/gltfx_ext_vrm.dart';

import 'expression.dart';
import 'humanoid.dart';

class LookAt {
  final Node node; // Head node
  final Vector3 offset;
  final Eye leftEye;
  final Eye rightEye;

  LookAt({
    required this.node,
    required this.leftEye,
    required this.rightEye,
    required this.offset,
  });

  void direct(Vector2 direction) {
    rightEye.direction = direction;
    leftEye.direction = direction;
  }

  void lookAt(Vector3 target) {}

  factory LookAt.import(
    VrmcVrmLookAt data, {
    required GltfDocument document,
    required Node root,
    required HumanSkeleton skeleton,
    Expressions expressions = const Expressions(),
  }) {
    final offset = Vector3(
      data.offsetFromHeadBone?[0] ?? 0.0,
      data.offsetFromHeadBone?[1] ?? 0.0,
      data.offsetFromHeadBone?[2] ?? 0.0,
    );

    LookAtRange range(VrmcVrmLookAtRangeMap? map, double defaultOutput) =>
        LookAtRange(
          inputMaxValue: map?.inputMaxValue ?? 360.0,
          outputScale: map?.outputScale ?? defaultOutput,
        );

    switch (data.type) {
      case LookAtType.bone || null:
        return _bone(
          skeleton: skeleton,
          offset: offset,
          horizontalInnerRange: range(data.rangeMapHorizontalInner, 360.0),
          horizontalOuterRange: range(data.rangeMapHorizontalOuter, 360.0),
          verticalUpRange: range(data.rangeMapVerticalUp, 360.0),
          verticalDownRange: range(data.rangeMapVerticalDown, 360.0),
          facesNegativeZ: false,
        );
      case LookAtType.expression:
        return _expression(
          skeleton: skeleton,
          expressions: expressions,
          offset: offset,
          horizontalOuterRange: range(data.rangeMapHorizontalOuter, 1.0),
          verticalUpRange: range(data.rangeMapVerticalUp, 1.0),
          verticalDownRange: range(data.rangeMapVerticalDown, 1.0),
        );
    }
  }

  /// Loads from VRM 0.x `firstPerson`.
  ///
  /// In a 0.x degree map, `xRange` is the maximum input angle and `yRange` is the maximum output
  /// (an angle for Bone, a weight for BlendShape). `curve` is ignored and mapped linearly.
  factory LookAt.import0(
    VrmFirstPerson data, {
    required HumanSkeleton skeleton,
    Expressions expressions = const Expressions(),
  }) {
    final o = data.firstPersonBoneOffset;
    // 0.x offsets are in Unity coordinates, so flip Z
    final offset = o != null ? Vector3(o.x, o.y, -o.z) : Vector3(0, 0.06, 0);

    final isBlendShape = data.lookAtTypeName == LookAtType0.blendShape;
    final defaultOutput = isBlendShape ? 1.0 : 10.0;
    LookAtRange range(VrmFirstPersonDegreeMap? map) => LookAtRange(
      inputMaxValue: map?.xRange ?? 90.0,
      outputScale: map?.yRange ?? defaultOutput,
    );

    if (isBlendShape) {
      return _expression(
        skeleton: skeleton,
        expressions: expressions,
        offset: offset,
        horizontalOuterRange: range(data.lookAtHorizontalOuter),
        verticalUpRange: range(data.lookAtVerticalUp),
        verticalDownRange: range(data.lookAtVerticalDown),
      );
    }
    return _bone(
      skeleton: skeleton,
      offset: offset,
      horizontalInnerRange: range(data.lookAtHorizontalInner),
      horizontalOuterRange: range(data.lookAtHorizontalOuter),
      verticalUpRange: range(data.lookAtVerticalUp),
      verticalDownRange: range(data.lookAtVerticalDown),
      facesNegativeZ: true,
    );
  }

  static LookAt _bone({
    required HumanSkeleton skeleton,
    required Vector3 offset,
    required LookAtRange horizontalInnerRange,
    required LookAtRange horizontalOuterRange,
    required LookAtRange verticalUpRange,
    required LookAtRange verticalDownRange,
    required bool facesNegativeZ,
  }) {
    final leftEye = skeleton.leftEye;
    final rightEye = skeleton.rightEye;
    if (leftEye == null || rightEye == null) {
      throw Exception('Left or right eye not found in human bones.');
    }

    Eye eye(EyePosition position, HumanBone bone) => Eye(
      bind: LookAtBoneBind(
        position: position,
        bone: bone,
        horizontalInnerRange: horizontalInnerRange,
        horizontalOuterRange: horizontalOuterRange,
        verticalUpRange: verticalUpRange,
        verticalDownRange: verticalDownRange,
        facesNegativeZ: facesNegativeZ,
      ),
      position: position,
    );

    return LookAt(
      node: skeleton.head.node,
      offset: offset,
      leftEye: eye(EyePosition.left, leftEye),
      rightEye: eye(EyePosition.right, rightEye),
    );
  }

  static LookAt _expression({
    required HumanSkeleton skeleton,
    required Expressions expressions,
    required Vector3 offset,
    required LookAtRange horizontalOuterRange,
    required LookAtRange verticalUpRange,
    required LookAtRange verticalDownRange,
  }) {
    // Expressions are common to both eyes, so both share the same bind (applying is idempotent)
    final bind = LookAtExpressionBind(
      lookUp: expressions.preset.lookUp,
      lookDown: expressions.preset.lookDown,
      lookLeft: expressions.preset.lookLeft,
      lookRight: expressions.preset.lookRight,
      horizontalOuterRange: horizontalOuterRange,
      verticalUpRange: verticalUpRange,
      verticalDownRange: verticalDownRange,
    );
    return LookAt(
      node: skeleton.head.node,
      offset: offset,
      leftEye: Eye(bind: bind, position: EyePosition.left),
      rightEye: Eye(bind: bind, position: EyePosition.right),
    );
  }
}

enum EyePosition { left, right }

class Eye {
  final EyePosition position;
  final LookAtBind bind;
  final Vector2 _direction = Vector2.zero();

  Eye({required this.bind, required this.position});

  Vector2 get direction => _direction;

  set direction(Vector2 value) {
    _direction.setFrom(value);
    bind.apply(_direction);
  }
}

sealed class LookAtBind {
  /// Computes yaw / pitch (degrees) from [direction] and applies them.
  void apply(Vector2 direction) {
    final yaw = asin(-direction.x.clamp(-1.0, 1.0)) * 180 / pi;
    final pitch = asin(direction.y.clamp(-1.0, 1.0)) * 180 / pi;
    applyYawPitch(yaw, pitch);
  }

  /// Positive [yaw] is left, positive [pitch] is down (degrees).
  void applyYawPitch(double yaw, double pitch);
}

class LookAtRange {
  final double inputMaxValue;
  final double outputScale;

  LookAtRange({required this.inputMaxValue, required this.outputScale});

  /// Maps the absolute value of the input angle (degrees) to the outputScale range.
  double map(double value) {
    final inputMax = max(inputMaxValue, 0.001);
    return min(value.abs(), inputMax) / inputMax * outputScale;
  }
}

class LookAtBoneBind extends LookAtBind {
  final HumanBone bone;
  final EyePosition position;
  final LookAtRange horizontalInnerRange;
  final LookAtRange horizontalOuterRange;
  final LookAtRange verticalUpRange;
  final LookAtRange verticalDownRange;

  /// True if the model faces -Z (VRM 0.x).
  ///
  /// The LookAt space is treated as rotated 180 degrees around the Y axis.
  final bool facesNegativeZ;

  LookAtBoneBind({
    required this.bone,
    required this.position,
    required this.horizontalInnerRange,
    required this.horizontalOuterRange,
    required this.verticalUpRange,
    required this.verticalDownRange,
    this.facesNegativeZ = false,
  });

  @override
  void applyYawPitch(double yaw, double pitch) {
    bone.transform = Matrix4.compose(
      Vector3.zero(),
      localRotation(yaw, pitch),
      Vector3.all(1.0),
    );
  }

  /// Computes the bone-local rotation from the rest pose.
  Quaternion localRotation(double yaw, double pitch) {
    final pitchDegrees = pitch > 0.0
        ? verticalDownRange.map(pitch)
        : -verticalUpRange.map(pitch);

    // Left eye: left (+yaw) is outward; right eye: left (+yaw) is inward
    final leftYaw = yaw > 0.0
        ? horizontalOuterRange.map(yaw)
        : -horizontalInnerRange.map(yaw);
    final rightYaw = yaw > 0.0
        ? horizontalInnerRange.map(yaw)
        : -horizontalOuterRange.map(yaw);

    final yawDegrees = position == EyePosition.left ? leftYaw : rightYaw;
    // For -Z-facing models, conjugating by a 180-degree Y rotation flips the X axis
    final pitchSign = facesNegativeZ ? -1.0 : 1.0;
    // Rotation in LookAt space (model space at rest): Euler angles in YXZ order
    final rotation =
        Quaternion.axisAngle(Vector3(0, 1, 0), yawDegrees * degrees2Radians) *
        Quaternion.axisAngle(
          Vector3(1, 0, 0),
          pitchSign * pitchDegrees * degrees2Radians,
        );

    // Convert the model-space rotation into the bone's local space
    final restWorld = Quaternion.fromRotation(
      bone.worldRestTransform.getRotation(),
    );
    return restWorld.inverted() * rotation * restWorld;
  }
}

/// Expresses gaze via expressions (lookUp / lookDown / lookLeft / lookRight).
class LookAtExpressionBind extends LookAtBind {
  final Expression? lookUp;
  final Expression? lookDown;
  final Expression? lookLeft;
  final Expression? lookRight;
  final LookAtRange horizontalOuterRange;
  final LookAtRange verticalUpRange;
  final LookAtRange verticalDownRange;

  LookAtExpressionBind({
    this.lookUp,
    this.lookDown,
    this.lookLeft,
    this.lookRight,
    required this.horizontalOuterRange,
    required this.verticalUpRange,
    required this.verticalDownRange,
  });

  @override
  void applyYawPitch(double yaw, double pitch) {
    lookLeft?.weight = yaw > 0.0 ? horizontalOuterRange.map(yaw) : 0.0;
    lookRight?.weight = yaw < 0.0 ? horizontalOuterRange.map(yaw) : 0.0;
    lookDown?.weight = pitch > 0.0 ? verticalDownRange.map(pitch) : 0.0;
    lookUp?.weight = pitch < 0.0 ? verticalUpRange.map(pitch) : 0.0;
  }
}
