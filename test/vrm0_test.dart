import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scene_vrm/scene_vrm.dart';
import 'package:scene_vrm/src/humanoid.dart';
import 'package:scene_vrm/src/mtoon.dart';
import 'package:scene_vrm/src/spring_bone.dart';
import 'package:gltfx_ext_vrm/gltfx_ext_vrm.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  group('humanBoneNameFromVrm0', () {
    test('maps thumb bones to VRM 1.0 names', () {
      expect(
        humanBoneNameFromVrm0(HumanoidBone0.leftThumbProximal),
        HumanBoneName.leftThumbMetacarpal,
      );
      expect(
        humanBoneNameFromVrm0(HumanoidBone0.leftThumbIntermediate),
        HumanBoneName.leftThumbProximal,
      );
      expect(
        humanBoneNameFromVrm0(HumanoidBone0.rightThumbProximal),
        HumanBoneName.rightThumbMetacarpal,
      );
      expect(
        humanBoneNameFromVrm0(HumanoidBone0.rightThumbIntermediate),
        HumanBoneName.rightThumbProximal,
      );
      expect(
        humanBoneNameFromVrm0(HumanoidBone0.leftThumbDistal),
        HumanBoneName.leftThumbDistal,
      );
    });

    test('maps every VRM 0.x bone', () {
      for (final b in HumanoidBone0.values) {
        expect(() => humanBoneNameFromVrm0(b), returnsNormally);
      }
    });
  });

  group('MToonSource.fromVrm0', () {
    test('ignores non-MToon shaders', () {
      expect(
        MToonSource.fromVrm0(const VrmMaterial(shader: 'VRM/UnlitTexture')),
        isNull,
      );
    });

    test('converts shading shift / toony', () {
      final r = convertVrm0Shading(shadeShift: 0.0, shadeToony: 0.9);
      expect(r.shadingToony, closeTo(0.95, 1e-6));
      expect(r.shadingShift, closeTo(-0.05, 1e-6));
    });

    test('converts properties to VRMC_materials_mtoon', () {
      final src = MToonSource.fromVrm0(
        VrmMaterial(
          shader: 'VRM/MToon',
          floatProperties: const {
            '_OutlineWidthMode': 1,
            '_OutlineWidth': 0.5,
            '_UvAnimScrollY': 0.3,
            '_IndirectLightIntensity': 0.2,
          },
          vectorProperties: {
            '_Color': Float32List.fromList([1, 0.5, 0, 0.25]),
            '_ShadeColor': Float32List.fromList([0.5, 0.5, 0.5, 1]),
          },
          textureProperties: const {'_MainTex': 3, '_SphereAdd': 4},
        ),
      )!;

      expect(src.baseColorTexture?.value, 3);
      expect(src.baseColorFactor![0], closeTo(1.0, 1e-6));
      expect(src.baseColorFactor![1], closeTo(0.214, 1e-3)); // sRGB→linear
      // alpha stays linear
      expect(src.baseColorFactor![3], closeTo(0.25, 1e-6));
      expect(src.mtoon.shadeColorFactor![0], closeTo(0.214, 1e-3));
      expect(src.mtoon.outlineWidthMode, OutlineWidthMode.worldCoordinates);
      expect(src.mtoon.outlineWidthFactor, closeTo(0.005, 1e-9));
      expect(src.mtoon.uvAnimationScrollYSpeedFactor, closeTo(-0.3, 1e-9));
      expect(src.mtoon.giEqualizationFactor, closeTo(0.8, 1e-9));
      expect(src.mtoon.matcapTexture?.index.value, 4);
    });
  });

  group('SpringBone (VRM 0.x)', () {
    test('leaf joint uses a 7cm virtual tail', () {
      final root = Node(name: 'root');
      final a = Node(
        name: 'a',
        localTransform: Matrix4.translation(Vector3(0, 1, 0)),
      );
      final b = Node(
        name: 'b',
        localTransform: Matrix4.translation(Vector3(0.5, 0, 0)),
      );
      root.add(a);
      a.add(b);

      final joint = SpringBoneJointState(
        node: b,
        child: null,
        hitRadius: 0,
        stiffness: 0,
        gravityPower: 1,
        gravityDir: Vector3(0, -1, 0),
        dragForce: 0.5,
      );
      final sim = SpringBoneSimulator([
        SpringBoneChain(joints: [joint], colliders: []),
      ]);
      sim.reset();
      for (var i = 0; i < 600; i++) {
        sim.fixedUpdate(1 / 60);
      }

      // The virtual tail is 7cm along +X and points straight down under gravity
      final tail = b.globalTransform.transformed3(
        Vector3(SpringBoneJointState.virtualTailLength, 0, 0),
      );
      final pb = b.globalTransform.getTranslation();
      expect((tail - pb).length, closeTo(0.07, 1e-4));
      expect(tail.x, closeTo(pb.x, 1e-2));
      expect(tail.y, lessThan(pb.y));
    });
  });

  group('LookAtBoneBind (VRM 0.x)', () {
    LookAtBoneBind bind({required bool facesNegativeZ}) {
      final node = Node(name: 'eye');
      final bone = HumanBone(
        HumanBoneName.leftEye,
        localRestTransform: Matrix4.identity(),
        worldRestTransform: Matrix4.identity(),
      );
      node.addComponent(bone);
      LookAtRange r() => LookAtRange(inputMaxValue: 90, outputScale: 90);
      return LookAtBoneBind(
        bone: bone,
        position: EyePosition.left,
        horizontalInnerRange: r(),
        horizontalOuterRange: r(),
        verticalUpRange: r(),
        verticalDownRange: r(),
        facesNegativeZ: facesNegativeZ,
      );
    }

    Vector3 forward(bool negZ) => Vector3(0, 0, negZ ? -1 : 1);

    for (final negZ in [false, true]) {
      test('facesNegativeZ=$negZ: +yaw looks to the model left', () {
        final q = bind(facesNegativeZ: negZ).localRotation(30, 0);
        final dir = q.asRotationMatrix().transformed(forward(negZ));
        // The model's left is +X when facing +Z, and -X when facing -Z
        expect(dir.x * (negZ ? -1 : 1), closeTo(math.sin(math.pi / 6), 1e-6));
      });

      test('facesNegativeZ=$negZ: +pitch looks down', () {
        final q = bind(facesNegativeZ: negZ).localRotation(0, 30);
        final dir = q.asRotationMatrix().transformed(forward(negZ));
        expect(dir.y, closeTo(-math.sin(math.pi / 6), 1e-6));
      });
    }

    test('applies rotation to the bone node', () {
      final b = bind(facesNegativeZ: true);
      b.applyYawPitch(30, 0);
      final m = b.bone.node.localTransform;
      expect(
        Quaternion.fromRotation(m.getRotation()).radians,
        greaterThan(0.1),
      );
    });
  });
}
