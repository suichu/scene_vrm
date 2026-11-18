import 'dart:math';

import 'package:flutter_scene/scene.dart';
import 'package:gltfx/gltfx.dart';
import 'package:vector_math/vector_math.dart';
import 'package:gltfx_ext_vrm/gltfx_ext_vrm.dart';

import 'expression.dart';
import 'humanoid.dart';

/// Eye gaze control (VRM 1.0 `lookAt` / VRM 0.x `firstPerson`).
///
/// Gaze is applied either by rotating eye bones ([LookAtBoneBind]) or by
/// driving lookUp / lookDown / lookLeft / lookRight expressions
/// ([LookAtExpressionBind]), depending on the model.
class LookAt {
  /// Head node.
  final Node node;

  /// Position of the look-at origin (between the eyes), relative to [node].
  final Vector3 offset;

  /// Left eye.
  final Eye leftEye;

  /// Right eye.
  final Eye rightEye;

  LookAt({
    required this.node,
    required this.leftEye,
    required this.rightEye,
    required this.offset,
  });

  /// Points both eyes in [direction].
  ///
  /// See [LookAtBind.apply] for how [direction] is interpreted.
  void direct(Vector2 direction) {
    rightEye.direction = direction;
    leftEye.direction = direction;
  }

  /// Points the eyes at [target].
  ///
  /// Not implemented yet; currently does nothing.
  void lookAt(Vector3 target) {}

  /// Loads from VRM 1.0 `lookAt`.
  ///
  /// Throws if the type is bone and the eye bones are missing.
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

/// Which eye an [Eye] represents.
enum EyePosition { left, right }

/// One eye whose gaze direction can be set.
class Eye {
  /// Whether this is the left or right eye.
  final EyePosition position;

  /// Bind that applies the gaze to the model.
  final LookAtBind bind;
  final Vector2 _direction = Vector2.zero();

  Eye({required this.bind, required this.position});

  /// Current gaze direction. Setting it applies the gaze through [bind].
  ///
  /// See [LookAtBind.apply] for how the value is interpreted.
  Vector2 get direction => _direction;

  set direction(Vector2 value) {
    _direction.setFrom(value);
    bind.apply(_direction);
  }
}

/// Applies a gaze direction to the model.
sealed class LookAtBind {
  /// Computes yaw / pitch (degrees) from [direction] and applies them.
  ///
  /// The components are the sines of the angles:
  /// yaw = asin(-x), pitch = asin(y). See [applyYawPitch] for the signs.
  void apply(Vector2 direction) {
    final yaw = asin(-direction.x.clamp(-1.0, 1.0)) * 180 / pi;
    final pitch = asin(direction.y.clamp(-1.0, 1.0)) * 180 / pi;
    applyYawPitch(yaw, pitch);
  }

  /// Positive [yaw] is left, positive [pitch] is down (degrees).
  void applyYawPitch(double yaw, double pitch);
}

/// Linear range map from an input angle to an output value.
///
/// Corresponds to VRM 1.0 `rangeMap` and VRM 0.x degree map.
class LookAtRange {
  /// Maximum input angle in degrees. Larger inputs are clamped.
  final double inputMaxValue;

  /// Output value at [inputMaxValue]: an angle in degrees for bone binds,
  /// or an expression weight for expression binds.
  final double outputScale;

  LookAtRange({required this.inputMaxValue, required this.outputScale});

  /// Maps the absolute value of the input angle (degrees) to the outputScale range.
  double map(double value) {
    final inputMax = max(inputMaxValue, 0.001);
    return min(value.abs(), inputMax) / inputMax * outputScale;
  }
}

/// Expresses gaze by rotating an eye bone.
class LookAtBoneBind extends LookAtBind {
  /// Eye bone to rotate.
  final HumanBone bone;

  /// Which eye [bone] is; decides which horizontal range is inner/outer.
  final EyePosition position;

  /// Range for turning toward the nose.
  final LookAtRange horizontalInnerRange;

  /// Range for turning away from the nose.
  final LookAtRange horizontalOuterRange;

  /// Range for looking up.
  final LookAtRange verticalUpRange;

  /// Range for looking down.
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
  /// Expression driven when looking up.
  final Expression? lookUp;

  /// Expression driven when looking down.
  final Expression? lookDown;

  /// Expression driven when looking left.
  final Expression? lookLeft;

  /// Expression driven when looking right.
  final Expression? lookRight;

  /// Maps the horizontal angle to the lookLeft / lookRight weight.
  final LookAtRange horizontalOuterRange;

  /// Maps the upward angle to the lookUp weight.
  final LookAtRange verticalUpRange;

  /// Maps the downward angle to the lookDown weight.
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
