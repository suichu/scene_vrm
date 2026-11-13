import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_scene/scene.dart';
import 'package:gltfx/gltfx.dart';
import 'package:vector_math/vector_math.dart';
import 'package:gltfx_ext_vrm/gltfx_ext_vrm.dart' as vrmext;

import 'gltfhelper.dart';
import 'vrm.dart';
import 'humanoid.dart';

class VrmAnimator {
  final List<_Track> _tracks;
  final Duration duration;

  VrmAnimator._(this._tracks, {required this.duration});

  factory VrmAnimator(VrmAnimation animation, Node bindTarget) {
    final document = animation._document;
    final an = document.animations.first;
    final van = document.extensions!.get(vrmext.vrmcVrmAnimation)!;

    final skeleton = _vrmaHumanoidSkeletonToMap(van.humanoid!);
    final boneByNode = Map.fromEntries(
      skeleton.entries
          .where((entry) => entry.value != null)
          .map((entry) => MapEntry(entry.value!.node, entry.key)),
    );

    final tracks = <_Track>[];

    // VRMA faces +Z. VRM 0.x models face -Z, so world-space deltas are
    // conjugated by a 180-degree Y rotation before being applied.
    final isVrm0 =
        bindTarget.getComponent<Vrm>()?.specVersion == VrmSpecVersion.v0;
    final facing = isVrm0
        ? Quaternion.axisAngle(Vector3(0, 1, 0), math.pi)
        : Quaternion.identity();

    for (final ch in an.channels) {
      final n = ch.target.node;
      if (n == null) continue;
      final nd = document.nodes[n];
      final boneName = boneByNode[n];
      if (boneName == null) continue;
      final bone = bindTarget.getComponent<Vrm>()?.getBoneByName(boneName);
      if (bone == null) continue;

      final sampler = an.samplers[ch.samplerIndex];
      final times = sampler.getTimes(document);
      final values = sampler.getValues(document);

      final srcLocal = getNodeMatrix(nd);
      final srcWorld = getNodeWorldMatrix(document, nd);
      final dstLocal = bone.localRestTransform;
      final dstWorld = bone.worldRestTransform;
      final al = Quaternion.fromRotation(srcLocal.getRotation());
      final aw = Quaternion.fromRotation(srcWorld.getRotation());
      final bl = Quaternion.fromRotation(dstLocal.getRotation());
      final bw = Quaternion.fromRotation(dstWorld.getRotation());

      switch (ch.target.path) {
        case Translation():
          final vs = List.generate(values.length ~/ 3, (i) {
            final t = Vector3(
              values[i * 3],
              values[i * 3 + 1],
              values[i * 3 + 2],
            );
            // Translation in world space
            final a = rotateByQuaternion(
              facing * aw * al.inverted(),
              t - srcLocal.getTranslation(),
            );
            // Convert back to local space using the target parent's world rotation
            return dstLocal.getTranslation() +
                rotateByQuaternion((bw * bl.inverted()).inverted(), a);
          });
          tracks.add(
            _Track(
              node: bone.node,
              property: ch.target.path,
              times: times,
              interpolation: sampler.interpolation,
              values: Float32List.fromList(
                vs.expand((v) => [v.x, v.y, v.z]).toList(),
              ),
            ),
          );
          break;
        case Rotation():
          final qs = List.generate(values.length ~/ 4, (i) {
            final q = Quaternion(
              values[i * 4],
              values[i * 4 + 1],
              values[i * 4 + 2],
              values[i * 4 + 3],
            );
            final a =
                facing *
                aw *
                al.inverted() *
                q *
                aw.inverted() *
                facing.inverted();
            return bl * bw.inverted() * a * bw;
          });
          tracks.add(
            _Track(
              node: bone.node,
              property: ch.target.path,
              times: times,
              interpolation: sampler.interpolation,
              values: Float32List.fromList(
                qs.expand((q) => [q.x, q.y, q.z, q.w]).toList(),
              ),
            ),
          );
        default:
          tracks.add(
            _Track(
              node: bone.node,
              property: ch.target.path,
              times: times,
              interpolation: sampler.interpolation,
              values: Float32List.fromList(values),
            ),
          );
      }
    }

    return VrmAnimator._(
      tracks,
      duration: Duration(microseconds: (animation.endTime * 1_000_000).toInt()),
    );
  }

  void apply(Duration time) {
    for (final track in _tracks) {
      track.apply(time);
    }
  }
}

class VrmAnimation {
  final GltfDocument _document;
  final double endTime;

  VrmAnimation._({required this._document, required this.endTime});

  factory VrmAnimation.fromBytes(Uint8List bytes) {
    final doc = Glb.parse(bytes, extensions: [vrmext.vrmcVrmAnimation]);

    final dur = doc.animations.first.getDuration(doc);
    return VrmAnimation._(document: doc, endTime: dur);
  }

  static Future<VrmAnimation> fromAsset(String name) async {
    final asset = await rootBundle.load(name);
    return VrmAnimation.fromBytes(asset.buffer.asUint8List());
  }
}

class VrmAnimationClip {
  final VrmAnimator _animator;
  double endTime;
  bool playing = false;
  double playbackTime = 0;
  bool loop = false;

  VrmAnimationClip(VrmAnimation animation, Node bindTarget)
    : _animator = VrmAnimator(animation, bindTarget),
      endTime = animation.endTime;

  void play() => playing = true;
  void stop() => playing = false;

  void update(double deltaSeconds) {
    if (playing) {
      var time = Duration(
        microseconds: ((playbackTime + deltaSeconds) * 1_000_000).toInt(),
      );
      if (loop && endTime > 0.0) {
        time = Duration(
          microseconds: time.inMicroseconds % (endTime * 1_000_000).toInt(),
        );
      }
      playbackTime = time.inMicroseconds / 1_000_000.0;
      _animator.apply(time);
    }
  }
}

class VrmAnimationPlayer {
  final _clips = <VrmAnimationClip>[];

  VrmAnimationClip createAnimationClip(
    VrmAnimation animation,
    Node bindTarget,
  ) {
    final clip = VrmAnimationClip(animation, bindTarget);
    _clips.add(clip);
    return clip;
  }

  void removeAnimationClip(VrmAnimationClip clip) {
    _clips.remove(clip);
  }

  void update(double deltaSeconds) {
    for (final clip in _clips) {
      clip.update(deltaSeconds);
    }
  }
}

class _Track {
  final Node node;
  final AnimationPath property; // 'rotation', 'translation', 'weights'
  final Float32List times;
  final Float32List values;
  final Interpolation interpolation;

  _Track({
    required this.node,
    required this.property,
    required this.times,
    required this.values,
    this.interpolation = const Linear(),
  });

  // Optimize: Cache last index to avoid searching from start every time
  int _lastIndex = 0;

  void apply(Duration time) {
    _apply(time, node.localTransform);
    node.localTransform = node.localTransform;
  }

  void _apply(Duration time, Matrix4? transform) {
    if (times.isEmpty) return;

    final t = time.inMicroseconds / 1_000_000.0;

    // Handle boundary conditions
    if (t <= times.first) {
      _applyValue(0, transform);
      return;
    }
    if (t >= times.last) {
      _applyValue(times.length - 1, transform);
      return;
    }

    // Find keyframe index
    // Reset cache if time went backwards
    if (t < times[_lastIndex]) {
      _lastIndex = 0;
    }

    // Search forward
    while (_lastIndex < times.length - 1 && t > times[_lastIndex + 1]) {
      _lastIndex++;
    }

    final i = _lastIndex;
    final t0 = times[i];
    final t1 = times[i + 1];
    final factor = (t - t0) / (t1 - t0);

    switch (interpolation) {
      case Step():
        _applyValue(i, transform);
        break;
      case Linear():
        _applyLerp(i, i + 1, factor, transform);
        break;
      case CubicSpline():
        _applyCubicSpline(i, i + 1, factor, transform);
        break;
    }
  }

  void _applyValue(int index, Matrix4? transform) {
    switch (property) {
      case Translation():
        final i = index * 3;
        final v = Vector3(values[i], values[i + 1], values[i + 2]);
        transform?.setTranslation(v);
        break;
      case Rotation():
        final i = index * 4;
        final q = Quaternion(
          values[i],
          values[i + 1],
          values[i + 2],
          values[i + 3],
        );
        transform?.setRotation(q.asRotationMatrix());
        break;
      default:
        break;
    }
    // TODO: weights
  }

  void _applyLerp(int i0, int i1, double factor, Matrix4? transform) {
    switch (property) {
      case Translation():
        final off0 = i0 * 3;
        final off1 = i1 * 3;
        final v0 = Vector3(values[off0], values[off0 + 1], values[off0 + 2]);
        final v1 = Vector3(values[off1], values[off1 + 1], values[off1 + 2]);
        final v = v0 * (1.0 - factor) + v1 * factor;
        transform?.setTranslation(v);
        break;
      case Rotation():
        final off0 = i0 * 4;
        final off1 = i1 * 4;
        final q0 = Quaternion(
          values[off0],
          values[off0 + 1],
          values[off0 + 2],
          values[off0 + 3],
        );
        final q1 = Quaternion(
          values[off1],
          values[off1 + 1],
          values[off1 + 2],
          values[off1 + 3],
        );
        final q = q0.slerp(q1, factor);
        transform?.setRotation(q.asRotationMatrix());
        break;
      default:
        break;
    }
  }

  void _applyCubicSpline(int i0, int i1, double factor, Matrix4? transform) {
    switch (property) {
      case Translation():
        final off0 = i0 * 9;
        final off1 = i1 * 9;
        final v0 = Vector3(
          values[off0 + 3],
          values[off0 + 4],
          values[off0 + 5],
        );
        final t0 = Vector3(
          values[off0 + 6],
          values[off0 + 7],
          values[off0 + 8],
        );
        final t1 = Vector3(values[off1], values[off1 + 1], values[off1 + 2]);
        final v1 = Vector3(
          values[off1 + 3],
          values[off1 + 4],
          values[off1 + 5],
        );
        final v = cubicSplineVector3(v0, t0, v1, t1, factor);
        transform?.setTranslation(v);
        break;
      case Rotation():
        final off0 = i0 * 12;
        final off1 = i1 * 12;

        final v0 = Quaternion(
          values[off0 + 4],
          values[off0 + 5],
          values[off0 + 6],
          values[off0 + 7],
        );

        final t0 = Quaternion(
          values[off0 + 8],
          values[off0 + 9],
          values[off0 + 10],
          values[off0 + 11],
        );

        final t1 = Quaternion(
          values[off1],
          values[off1 + 1],
          values[off1 + 2],
          values[off1 + 3],
        );

        final v1 = Quaternion(
          values[off1 + 4],
          values[off1 + 5],
          values[off1 + 6],
          values[off1 + 7],
        );

        final q = cubicSplineQuaternion(v0, t0, v1, t1, factor);
        transform?.setRotation(q.asRotationMatrix());
        break;
      default:
        break;
    }
  }

  static Quaternion cubicSplineQuaternion(
    Quaternion vert0,
    Quaternion tang0,
    Quaternion vert1,
    Quaternion tang1,
    double factor,
  ) {
    final t = factor;
    final t2 = t * t;
    final t3 = t2 * t;

    // Hermite basis functions
    final h00 = 2 * t3 - 3 * t2 + 1;
    final h10 = t3 - 2 * t2 + t;
    final h01 = -2 * t3 + 3 * t2;
    final h11 = t3 - t2;

    // Ensure quaternions are in the same hemisphere to avoid flipping
    final dot =
        vert0.x * vert1.x +
        vert0.y * vert1.y +
        vert0.z * vert1.z +
        vert0.w * vert1.w;
    final sign = dot < 0.0 ? -1.0 : 1.0;

    final x =
        h00 * vert0.x + h10 * tang0.x + sign * (h01 * vert1.x + h11 * tang1.x);
    final y =
        h00 * vert0.y + h10 * tang0.y + sign * (h01 * vert1.y + h11 * tang1.y);
    final z =
        h00 * vert0.z + h10 * tang0.z + sign * (h01 * vert1.z + h11 * tang1.z);
    final w =
        h00 * vert0.w + h10 * tang0.w + sign * (h01 * vert1.w + h11 * tang1.w);

    return Quaternion(x, y, z, w)..normalize();
  }

  static Vector3 cubicSplineVector3(
    Vector3 vert0,
    Vector3 tang0,
    Vector3 vert1,
    Vector3 tang1,
    double factor,
  ) {
    final t = factor;
    final t2 = t * t;
    final t3 = t2 * t;

    // Hermite basis functions
    final h00 = 2 * t3 - 3 * t2 + 1;
    final h10 = t3 - 2 * t2 + t;
    final h01 = -2 * t3 + 3 * t2;
    final h11 = t3 - t2;

    return vert0 * h00 + tang0 * h10 + vert1 * h01 + tang1 * h11;
  }
}

Map<HumanBoneName, vrmext.VrmcVrmaHumanBone?> _vrmaHumanoidSkeletonToMap(
  vrmext.VrmcVrmaHumanoid humanoid,
) {
  return {
    HumanBoneName.hips: humanoid.humanBones.hips,
    HumanBoneName.spine: humanoid.humanBones.spine,
    HumanBoneName.chest: humanoid.humanBones.chest,
    HumanBoneName.neck: humanoid.humanBones.neck,
    HumanBoneName.head: humanoid.humanBones.head,
    HumanBoneName.leftShoulder: humanoid.humanBones.leftShoulder,
    HumanBoneName.leftUpperArm: humanoid.humanBones.leftUpperArm,
    HumanBoneName.leftLowerArm: humanoid.humanBones.leftLowerArm,
    HumanBoneName.leftHand: humanoid.humanBones.leftHand,
    HumanBoneName.rightShoulder: humanoid.humanBones.rightShoulder,
    HumanBoneName.rightUpperArm: humanoid.humanBones.rightUpperArm,
    HumanBoneName.rightLowerArm: humanoid.humanBones.rightLowerArm,
    HumanBoneName.rightHand: humanoid.humanBones.rightHand,
    HumanBoneName.leftUpperLeg: humanoid.humanBones.leftUpperLeg,
    HumanBoneName.leftLowerLeg: humanoid.humanBones.leftLowerLeg,
    HumanBoneName.leftFoot: humanoid.humanBones.leftFoot,
    HumanBoneName.rightUpperLeg: humanoid.humanBones.rightUpperLeg,
    HumanBoneName.rightLowerLeg: humanoid.humanBones.rightLowerLeg,
    HumanBoneName.rightFoot: humanoid.humanBones.rightFoot,
    HumanBoneName.leftToes: humanoid.humanBones.leftToes,
    HumanBoneName.rightToes: humanoid.humanBones.rightToes,
    HumanBoneName.leftEye: humanoid.humanBones.leftEye,
    HumanBoneName.rightEye: humanoid.humanBones.rightEye,
    HumanBoneName.jaw: humanoid.humanBones.jaw,
    HumanBoneName.leftThumbProximal: humanoid.humanBones.leftThumbProximal,
    HumanBoneName.leftThumbMetacarpal: humanoid.humanBones.leftThumbMetacarpal,
    HumanBoneName.leftThumbDistal: humanoid.humanBones.leftThumbDistal,
    HumanBoneName.leftIndexProximal: humanoid.humanBones.leftIndexProximal,
    HumanBoneName.leftIndexIntermediate:
        humanoid.humanBones.leftIndexIntermediate,
    HumanBoneName.leftIndexDistal: humanoid.humanBones.leftIndexDistal,
    HumanBoneName.leftMiddleProximal: humanoid.humanBones.leftMiddleProximal,
    HumanBoneName.leftMiddleIntermediate:
        humanoid.humanBones.leftMiddleIntermediate,
    HumanBoneName.leftMiddleDistal: humanoid.humanBones.leftMiddleDistal,
    HumanBoneName.leftRingProximal: humanoid.humanBones.leftRingProximal,
    HumanBoneName.leftRingIntermediate:
        humanoid.humanBones.leftRingIntermediate,
    HumanBoneName.leftRingDistal: humanoid.humanBones.leftRingDistal,
    HumanBoneName.leftLittleProximal: humanoid.humanBones.leftLittleProximal,
    HumanBoneName.leftLittleIntermediate:
        humanoid.humanBones.leftLittleIntermediate,
    HumanBoneName.leftLittleDistal: humanoid.humanBones.leftLittleDistal,
    HumanBoneName.rightThumbProximal: humanoid.humanBones.rightThumbProximal,
    HumanBoneName.rightThumbMetacarpal:
        humanoid.humanBones.rightThumbMetacarpal,
    HumanBoneName.rightThumbDistal: humanoid.humanBones.rightThumbDistal,
    HumanBoneName.rightIndexProximal: humanoid.humanBones.rightIndexProximal,
    HumanBoneName.rightIndexIntermediate:
        humanoid.humanBones.rightIndexIntermediate,
    HumanBoneName.rightIndexDistal: humanoid.humanBones.rightIndexDistal,
    HumanBoneName.rightMiddleProximal: humanoid.humanBones.rightMiddleProximal,
    HumanBoneName.rightMiddleIntermediate:
        humanoid.humanBones.rightMiddleIntermediate,
    HumanBoneName.rightMiddleDistal: humanoid.humanBones.rightMiddleDistal,
    HumanBoneName.rightRingProximal: humanoid.humanBones.rightRingProximal,
    HumanBoneName.rightRingIntermediate:
        humanoid.humanBones.rightRingIntermediate,
    HumanBoneName.rightRingDistal: humanoid.humanBones.rightRingDistal,
    HumanBoneName.rightLittleProximal: humanoid.humanBones.rightLittleProximal,
    HumanBoneName.rightLittleIntermediate:
        humanoid.humanBones.rightLittleIntermediate,
    HumanBoneName.rightLittleDistal: humanoid.humanBones.rightLittleDistal,
  };
}
