import 'package:flutter_scene/scene.dart';
import 'package:gltfx/gltfx.dart';
import 'package:gltfx_ext_vrm/gltfx_ext_vrm.dart' as vrmext;

import 'animation.dart';
import 'expression.dart';
import 'humanoid.dart';
import 'lookat.dart';

/// VRM specification version of the loaded model.
enum VrmSpecVersion {
  /// VRM 0.x (`VRM` extension). The model faces -Z.
  v0,

  /// VRM 1.0 (`VRMC_vrm` extension). The model faces +Z.
  v1,
}

class Vrm extends Component {
  final Expressions expressions;
  final HumanSkeleton skeleton;
  final LookAt? lookAt;
  final VrmSpecVersion specVersion;
  final vrmext.VrmcVrmMeta meta;
  final vrmext.VrmMeta? meta0;
  final player = VrmAnimationPlayer();
  final Map<HumanBoneName, HumanBone> _boneMap = {};

  Vrm._({
    this.expressions = const Expressions(),
    required this.skeleton,
    this.lookAt,
    this.specVersion = VrmSpecVersion.v1,
    required this.meta,
    this.meta0,
  }) {
    for (final bone in skeleton.all) {
      _boneMap[bone.name] = bone;
    }
  }

  factory Vrm.import(
    vrmext.VrmcVrm data, {
    required GltfDocument document,
    required Node root,
  }) {
    final skeleton = HumanSkeleton.attach(
      {
        for (final MapEntry(:key, :value) in _vrmcHumanBonesToMap(
          data.humanoid.humanBones,
        ).entries)
          if (value != null) key: value.node,
      },
      document: document,
      root: root,
    );

    LookAt? lookAt;
    final expressions = Expressions.import(
      document,
      data.expressions ?? vrmext.VrmcVrmExpressions(),
      node: root,
    );

    if (data.lookAt != null) {
      try {
        lookAt = LookAt.import(
          data.lookAt!,
          document: document,
          root: root,
          skeleton: skeleton,
          expressions: expressions,
        );
      } catch (e) {
        // Handle the exception if needed
      }
    }

    return Vrm._(
      skeleton: skeleton,
      expressions: expressions,
      lookAt: lookAt,
      specVersion: VrmSpecVersion.v1,
      meta: data.meta,
    );
  }

  /// Loads from the VRM 0.x `VRM` extension.
  ///
  /// https://github.com/vrm-c/vrm-specification/blob/master/specification/0.0/README.md
  factory Vrm.import0(
    vrmext.Vrm data, {
    required GltfDocument document,
    required Node root,
  }) {
    final bones = <HumanBoneName, NodeIdx>{};
    for (final b
        in data.humanoid?.humanBones ?? const <vrmext.VrmHumanoidBone>[]) {
      final name = b.bone != null ? humanBoneNameFromVrm0(b.bone!) : null;
      if (name == null || b.node.value < 0) continue;
      bones.putIfAbsent(name, () => b.node);
    }

    final skeleton = HumanSkeleton.attach(
      bones,
      document: document,
      root: root,
    );

    final expressions = Expressions.import0(
      document,
      data.blendShapeMaster ?? const vrmext.VrmBlendShape(),
      node: root,
    );

    LookAt? lookAt;
    final firstPerson = data.firstPerson;
    if (firstPerson != null) {
      try {
        lookAt = LookAt.import0(
          firstPerson,
          skeleton: skeleton,
          expressions: expressions,
        );
      } catch (e) {
        // LookAt is optional, so the model is still valid if it fails to load
      }
    }

    vrmext.AvatarPermission computeAvatarPermission(
      vrmext.AllowedUserName0 allowedUserName,
    ) => switch (allowedUserName) {
      vrmext.AllowedUserName0.onlyAuthor => vrmext.AvatarPermission.onlyAuthor,
      vrmext.AllowedUserName0.explicitlyLicensedPerson =>
        vrmext.AvatarPermission.onlySeparatelyLicensedPerson,
      vrmext.AllowedUserName0.everyone => vrmext.AvatarPermission.everyone,
    };

    String computeLicenseUrl(vrmext.LicenseName0 licenseName) =>
        switch (licenseName) {
          vrmext.LicenseName0.cc0 =>
            'https://creativecommons.org/publicdomain/zero/1.0/',
          vrmext.LicenseName0.ccBy =>
            'https://creativecommons.org/licenses/by/4.0/',
          vrmext.LicenseName0.ccBySa =>
            'https://creativecommons.org/licenses/by-sa/4.0/',
          vrmext.LicenseName0.ccByNd =>
            'https://creativecommons.org/licenses/by-nd/4.0/',
          vrmext.LicenseName0.ccByNc =>
            'https://creativecommons.org/licenses/by-nc/4.0/',
          vrmext.LicenseName0.ccByNcSa =>
            'https://creativecommons.org/licenses/by-nc-sa/4.0/',
          vrmext.LicenseName0.ccByNcNd =>
            'https://creativecommons.org/licenses/by-nc-nd/4.0/',
          _ => '',
        };

    final meta1 = vrmext.VrmcVrmMeta(
      name: data.meta?.title ?? 'noname',
      version: data.meta?.version ?? '0.0',
      authors: data.meta?.author != null ? [data.meta!.author!] : ['unknown'],
      contactInformation: data.meta?.contactInformation,
      thumbnailImage: data.meta?.texture,
      references: data.meta?.reference != null ? [data.meta!.reference!] : [],
      avatarPermission: data.meta?.allowedUserName != null
          ? computeAvatarPermission(data.meta!.allowedUserName!)
          : vrmext.AvatarPermission.onlyAuthor,
      allowExcessivelyViolentUsage:
          data.meta?.violentUsageName == vrmext.Permission0.allow,
      allowExcessivelySexualUsage:
          data.meta?.sexualUsageName == vrmext.Permission0.allow,
      commercialUsage:
          data.meta?.commercialUsageName == vrmext.Permission0.allow
          ? vrmext.CommercialUsage.corporation
          : vrmext.CommercialUsage.personalNonProfit,
      licenseUrl: data.meta?.licenseName != null
          ? computeLicenseUrl(data.meta!.licenseName!)
          : '',
      otherLicenseUrl: data.meta?.otherLicenseUrl,
    );

    return Vrm._(
      skeleton: skeleton,
      expressions: expressions,
      lookAt: lookAt,
      specVersion: VrmSpecVersion.v0,
      meta: meta1,
      meta0: data.meta,
    );
  }

  @override
  void update(double deltaSeconds) {
    player.update(deltaSeconds);
  }

  HumanBone? getBoneByName(HumanBoneName name) => _boneMap[name];

  VrmAnimationClip createAnimationClip(VrmAnimation animation) {
    return player.createAnimationClip(animation, node);
  }

  void removeAnimationClip(VrmAnimationClip clip) {
    player.removeAnimationClip(clip);
  }
}

Map<HumanBoneName, vrmext.VrmcVrmHumanBone?> _vrmcHumanBonesToMap(
  vrmext.VrmcVrmHumanBones b,
) => {
  HumanBoneName.hips: b.hips,
  HumanBoneName.spine: b.spine,
  HumanBoneName.chest: b.chest,
  HumanBoneName.upperChest: b.upperChest,
  HumanBoneName.neck: b.neck,
  HumanBoneName.head: b.head,
  HumanBoneName.leftEye: b.leftEye,
  HumanBoneName.rightEye: b.rightEye,
  HumanBoneName.jaw: b.jaw,
  HumanBoneName.leftUpperLeg: b.leftUpperLeg,
  HumanBoneName.leftLowerLeg: b.leftLowerLeg,
  HumanBoneName.leftFoot: b.leftFoot,
  HumanBoneName.leftToes: b.leftToes,
  HumanBoneName.rightUpperLeg: b.rightUpperLeg,
  HumanBoneName.rightLowerLeg: b.rightLowerLeg,
  HumanBoneName.rightFoot: b.rightFoot,
  HumanBoneName.rightToes: b.rightToes,
  HumanBoneName.leftShoulder: b.leftShoulder,
  HumanBoneName.leftUpperArm: b.leftUpperArm,
  HumanBoneName.leftLowerArm: b.leftLowerArm,
  HumanBoneName.leftHand: b.leftHand,
  HumanBoneName.rightShoulder: b.rightShoulder,
  HumanBoneName.rightUpperArm: b.rightUpperArm,
  HumanBoneName.rightLowerArm: b.rightLowerArm,
  HumanBoneName.rightHand: b.rightHand,
  HumanBoneName.leftThumbMetacarpal: b.leftThumbMetacarpal,
  HumanBoneName.leftThumbProximal: b.leftThumbProximal,
  HumanBoneName.leftThumbDistal: b.leftThumbDistal,
  HumanBoneName.leftIndexProximal: b.leftIndexProximal,
  HumanBoneName.leftIndexIntermediate: b.leftIndexIntermediate,
  HumanBoneName.leftIndexDistal: b.leftIndexDistal,
  HumanBoneName.leftMiddleProximal: b.leftMiddleProximal,
  HumanBoneName.leftMiddleIntermediate: b.leftMiddleIntermediate,
  HumanBoneName.leftMiddleDistal: b.leftMiddleDistal,
  HumanBoneName.leftRingProximal: b.leftRingProximal,
  HumanBoneName.leftRingIntermediate: b.leftRingIntermediate,
  HumanBoneName.leftRingDistal: b.leftRingDistal,
  HumanBoneName.leftLittleProximal: b.leftLittleProximal,
  HumanBoneName.leftLittleIntermediate: b.leftLittleIntermediate,
  HumanBoneName.leftLittleDistal: b.leftLittleDistal,
  HumanBoneName.rightThumbMetacarpal: b.rightThumbMetacarpal,
  HumanBoneName.rightThumbProximal: b.rightThumbProximal,
  HumanBoneName.rightThumbDistal: b.rightThumbDistal,
  HumanBoneName.rightIndexProximal: b.rightIndexProximal,
  HumanBoneName.rightIndexIntermediate: b.rightIndexIntermediate,
  HumanBoneName.rightIndexDistal: b.rightIndexDistal,
  HumanBoneName.rightMiddleProximal: b.rightMiddleProximal,
  HumanBoneName.rightMiddleIntermediate: b.rightMiddleIntermediate,
  HumanBoneName.rightMiddleDistal: b.rightMiddleDistal,
  HumanBoneName.rightRingProximal: b.rightRingProximal,
  HumanBoneName.rightRingIntermediate: b.rightRingIntermediate,
  HumanBoneName.rightRingDistal: b.rightRingDistal,
  HumanBoneName.rightLittleProximal: b.rightLittleProximal,
  HumanBoneName.rightLittleIntermediate: b.rightLittleIntermediate,
  HumanBoneName.rightLittleDistal: b.rightLittleDistal,
};
