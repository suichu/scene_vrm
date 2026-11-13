import 'package:flutter_scene/scene.dart';
import 'package:gltfx/gltfx.dart';
import 'package:gltfx_ext_vrm/gltfx_ext_vrm.dart' as vrmext;
import 'package:vector_math/vector_math.dart';

import 'gltfhelper.dart';

class HumanBone extends Component {
  final HumanBoneName name;
  final Matrix4 localRestTransform;
  final Matrix4 worldRestTransform;

  HumanBone(
    this.name, {
    required this.localRestTransform,
    required this.worldRestTransform,
  });

  Matrix4 get transform => localRestTransform.clone()
    ..invert()
    ..multiply(node.localTransform);

  set transform(Matrix4 value) {
    node.localTransform = localRestTransform.clone()..multiply(value);
  }
}

/// Converts a VRM 0.x bone name to a VRM 1.0 bone name.
///
/// Thumb names are shifted between 0.x and 1.0:
/// `thumbProximal` → `thumbMetacarpal`, `thumbIntermediate` → `thumbProximal`.
HumanBoneName humanBoneNameFromVrm0(
  vrmext.HumanoidBone0 bone,
) => switch (bone) {
  vrmext.HumanoidBone0.leftThumbProximal => HumanBoneName.leftThumbMetacarpal,
  vrmext.HumanoidBone0.leftThumbIntermediate => HumanBoneName.leftThumbProximal,
  vrmext.HumanoidBone0.rightThumbProximal => HumanBoneName.rightThumbMetacarpal,
  vrmext.HumanoidBone0.rightThumbIntermediate =>
    HumanBoneName.rightThumbProximal,
  _ => HumanBoneName.values.byName(bone.name),
};

class HumanSkeleton {
  // Torso (required)
  final HumanBone hips;
  final HumanBone spine;
  final HumanBone chest;
  final HumanBone? upperChest;
  final HumanBone neck;
  // Head (required)
  final HumanBone head;
  final HumanBone? leftEye;
  final HumanBone? rightEye;
  final HumanBone? jaw;
  // Legs (required)
  final HumanBone leftUpperLeg;
  final HumanBone leftLowerLeg;
  final HumanBone leftFoot;
  final HumanBone? leftToes;
  final HumanBone rightUpperLeg;
  final HumanBone rightLowerLeg;
  final HumanBone rightFoot;
  final HumanBone? rightToes;
  // Arms (required)
  final HumanBone? leftShoulder;
  final HumanBone leftUpperArm;
  final HumanBone leftLowerArm;
  final HumanBone leftHand;
  final HumanBone? rightShoulder;
  final HumanBone rightUpperArm;
  final HumanBone rightLowerArm;
  final HumanBone rightHand;
  // Left fingers (optional)
  final HumanBone? leftThumbMetacarpal;
  final HumanBone? leftThumbProximal;
  final HumanBone? leftThumbDistal;
  final HumanBone? leftIndexProximal;
  final HumanBone? leftIndexIntermediate;
  final HumanBone? leftIndexDistal;
  final HumanBone? leftMiddleProximal;
  final HumanBone? leftMiddleIntermediate;
  final HumanBone? leftMiddleDistal;
  final HumanBone? leftRingProximal;
  final HumanBone? leftRingIntermediate;
  final HumanBone? leftRingDistal;
  final HumanBone? leftLittleProximal;
  final HumanBone? leftLittleIntermediate;
  final HumanBone? leftLittleDistal;
  // Right fingers (optional)
  final HumanBone? rightThumbMetacarpal;
  final HumanBone? rightThumbProximal;
  final HumanBone? rightThumbDistal;
  final HumanBone? rightIndexProximal;
  final HumanBone? rightIndexIntermediate;
  final HumanBone? rightIndexDistal;
  final HumanBone? rightMiddleProximal;
  final HumanBone? rightMiddleIntermediate;
  final HumanBone? rightMiddleDistal;
  final HumanBone? rightRingProximal;
  final HumanBone? rightRingIntermediate;
  final HumanBone? rightRingDistal;
  final HumanBone? rightLittleProximal;
  final HumanBone? rightLittleIntermediate;
  final HumanBone? rightLittleDistal;

  List<HumanBone> get all => [
    hips,
    spine,
    chest,
    ?upperChest,
    neck,
    head,
    ?leftEye,
    ?rightEye,
    ?jaw,
    leftUpperLeg,
    leftLowerLeg,
    leftFoot,
    ?leftToes,
    rightUpperLeg,
    rightLowerLeg,
    rightFoot,
    ?rightToes,
    ?leftShoulder,
    leftUpperArm,
    leftLowerArm,
    leftHand,
    ?rightShoulder,
    rightUpperArm,
    rightLowerArm,
    rightHand,
    ?leftThumbMetacarpal,
    ?leftThumbProximal,
    ?leftThumbDistal,
    ?leftIndexProximal,
    ?leftIndexIntermediate,
    ?leftIndexDistal,
    ?leftMiddleProximal,
    ?leftMiddleIntermediate,
    ?leftMiddleDistal,
    ?leftRingProximal,
    ?leftRingIntermediate,
    ?leftRingDistal,
    ?leftLittleProximal,
    ?leftLittleIntermediate,
    ?leftLittleDistal,
    ?rightThumbMetacarpal,
    ?rightThumbProximal,
    ?rightThumbDistal,
    ?rightIndexProximal,
    ?rightIndexIntermediate,
    ?rightIndexDistal,
    ?rightMiddleProximal,
    ?rightMiddleIntermediate,
    ?rightMiddleDistal,
    ?rightRingProximal,
    ?rightRingIntermediate,
    ?rightRingDistal,
    ?rightLittleProximal,
    ?rightLittleIntermediate,
    ?rightLittleDistal,
  ];

  /// Builds the skeleton by attaching [HumanBone] components to glTF nodes.
  ///
  /// Throws [FormatException] if a required bone is missing.
  factory HumanSkeleton.attach(
    Map<HumanBoneName, NodeIdx> bones, {
    required GltfDocument document,
    required Node root,
  }) {
    final attached = <HumanBoneName, HumanBone>{};
    for (final MapEntry(key: bone, value: idx) in bones.entries) {
      if (idx.value < 0 || idx.value >= document.nodes.items.length) continue;
      final srcNode = document.nodes[idx];
      final name = srcNode.name;
      if (name == null) continue;
      final node = root.getChildByName(name);
      if (node == null) continue;
      final hb = HumanBone(
        bone,
        localRestTransform: getNodeMatrix(srcNode),
        worldRestTransform: getNodeWorldMatrix(document, srcNode),
      );
      node.addComponent(hb);
      attached[bone] = hb;
    }

    HumanBone req(HumanBoneName name) =>
        attached[name] ??
        (throw FormatException('Required human bone "${name.name}" not found'));
    HumanBone? opt(HumanBoneName name) => attached[name];

    return HumanSkeleton(
      hips: req(HumanBoneName.hips),
      spine: req(HumanBoneName.spine),
      chest: req(HumanBoneName.chest),
      upperChest: opt(HumanBoneName.upperChest),
      neck: req(HumanBoneName.neck),
      head: req(HumanBoneName.head),
      leftEye: opt(HumanBoneName.leftEye),
      rightEye: opt(HumanBoneName.rightEye),
      jaw: opt(HumanBoneName.jaw),
      leftUpperLeg: req(HumanBoneName.leftUpperLeg),
      leftLowerLeg: req(HumanBoneName.leftLowerLeg),
      leftFoot: req(HumanBoneName.leftFoot),
      leftToes: opt(HumanBoneName.leftToes),
      rightUpperLeg: req(HumanBoneName.rightUpperLeg),
      rightLowerLeg: req(HumanBoneName.rightLowerLeg),
      rightFoot: req(HumanBoneName.rightFoot),
      rightToes: opt(HumanBoneName.rightToes),
      leftShoulder: opt(HumanBoneName.leftShoulder),
      leftUpperArm: req(HumanBoneName.leftUpperArm),
      leftLowerArm: req(HumanBoneName.leftLowerArm),
      leftHand: req(HumanBoneName.leftHand),
      rightShoulder: opt(HumanBoneName.rightShoulder),
      rightUpperArm: req(HumanBoneName.rightUpperArm),
      rightLowerArm: req(HumanBoneName.rightLowerArm),
      rightHand: req(HumanBoneName.rightHand),
      leftThumbMetacarpal: opt(HumanBoneName.leftThumbMetacarpal),
      leftThumbProximal: opt(HumanBoneName.leftThumbProximal),
      leftThumbDistal: opt(HumanBoneName.leftThumbDistal),
      leftIndexProximal: opt(HumanBoneName.leftIndexProximal),
      leftIndexIntermediate: opt(HumanBoneName.leftIndexIntermediate),
      leftIndexDistal: opt(HumanBoneName.leftIndexDistal),
      leftMiddleProximal: opt(HumanBoneName.leftMiddleProximal),
      leftMiddleIntermediate: opt(HumanBoneName.leftMiddleIntermediate),
      leftMiddleDistal: opt(HumanBoneName.leftMiddleDistal),
      leftRingProximal: opt(HumanBoneName.leftRingProximal),
      leftRingIntermediate: opt(HumanBoneName.leftRingIntermediate),
      leftRingDistal: opt(HumanBoneName.leftRingDistal),
      leftLittleProximal: opt(HumanBoneName.leftLittleProximal),
      leftLittleIntermediate: opt(HumanBoneName.leftLittleIntermediate),
      leftLittleDistal: opt(HumanBoneName.leftLittleDistal),
      rightThumbMetacarpal: opt(HumanBoneName.rightThumbMetacarpal),
      rightThumbProximal: opt(HumanBoneName.rightThumbProximal),
      rightThumbDistal: opt(HumanBoneName.rightThumbDistal),
      rightIndexProximal: opt(HumanBoneName.rightIndexProximal),
      rightIndexIntermediate: opt(HumanBoneName.rightIndexIntermediate),
      rightIndexDistal: opt(HumanBoneName.rightIndexDistal),
      rightMiddleProximal: opt(HumanBoneName.rightMiddleProximal),
      rightMiddleIntermediate: opt(HumanBoneName.rightMiddleIntermediate),
      rightMiddleDistal: opt(HumanBoneName.rightMiddleDistal),
      rightRingProximal: opt(HumanBoneName.rightRingProximal),
      rightRingIntermediate: opt(HumanBoneName.rightRingIntermediate),
      rightRingDistal: opt(HumanBoneName.rightRingDistal),
      rightLittleProximal: opt(HumanBoneName.rightLittleProximal),
      rightLittleIntermediate: opt(HumanBoneName.rightLittleIntermediate),
      rightLittleDistal: opt(HumanBoneName.rightLittleDistal),
    );
  }

  const HumanSkeleton({
    required this.hips,
    required this.spine,
    required this.chest,
    this.upperChest,
    required this.neck,
    required this.head,
    this.leftEye,
    this.rightEye,
    this.jaw,
    required this.leftUpperLeg,
    required this.leftLowerLeg,
    required this.leftFoot,
    this.leftToes,
    required this.rightUpperLeg,
    required this.rightLowerLeg,
    required this.rightFoot,
    this.rightToes,
    this.leftShoulder,
    required this.leftUpperArm,
    required this.leftLowerArm,
    required this.leftHand,
    this.rightShoulder,
    required this.rightUpperArm,
    required this.rightLowerArm,
    required this.rightHand,
    this.leftThumbMetacarpal,
    this.leftThumbProximal,
    this.leftThumbDistal,
    this.leftIndexProximal,
    this.leftIndexIntermediate,
    this.leftIndexDistal,
    this.leftMiddleProximal,
    this.leftMiddleIntermediate,
    this.leftMiddleDistal,
    this.leftRingProximal,
    this.leftRingIntermediate,
    this.leftRingDistal,
    this.leftLittleProximal,
    this.leftLittleIntermediate,
    this.leftLittleDistal,
    this.rightThumbMetacarpal,
    this.rightThumbProximal,
    this.rightThumbDistal,
    this.rightIndexProximal,
    this.rightIndexIntermediate,
    this.rightIndexDistal,
    this.rightMiddleProximal,
    this.rightMiddleIntermediate,
    this.rightMiddleDistal,
    this.rightRingProximal,
    this.rightRingIntermediate,
    this.rightRingDistal,
    this.rightLittleProximal,
    this.rightLittleIntermediate,
    this.rightLittleDistal,
  });
}

enum HumanBoneName {
  hips("hips"),
  leftUpperLeg("leftUpperLeg"),
  rightUpperLeg("rightUpperLeg"),
  leftLowerLeg("leftLowerLeg"),
  rightLowerLeg("rightLowerLeg"),
  leftFoot("leftFoot"),
  rightFoot("rightFoot"),
  spine("spine"),
  chest("chest"),
  upperChest("upperChest"),
  neck("neck"),
  head("head"),
  leftShoulder("leftShoulder"),
  rightShoulder("rightShoulder"),
  leftUpperArm("leftUpperArm"),
  rightUpperArm("rightUpperArm"),
  leftLowerArm("leftLowerArm"),
  rightLowerArm("rightLowerArm"),
  leftHand("leftHand"),
  rightHand("rightHand"),
  leftToes("leftToes"),
  rightToes("rightToes"),
  leftEye("leftEye"),
  rightEye("rightEye"),
  jaw("jaw"),
  leftThumbMetacarpal("leftThumbMetacarpal"),
  leftThumbProximal("leftThumbProximal"),
  leftThumbDistal("leftThumbDistal"),
  leftIndexProximal("leftIndexProximal"),
  leftIndexIntermediate("leftIndexIntermediate"),
  leftIndexDistal("leftIndexDistal"),
  leftMiddleProximal("leftMiddleProximal"),
  leftMiddleIntermediate("leftMiddleIntermediate"),
  leftMiddleDistal("leftMiddleDistal"),
  leftRingProximal("leftRingProximal"),
  leftRingIntermediate("leftRingIntermediate"),
  leftRingDistal("leftRingDistal"),
  leftLittleProximal("leftLittleProximal"),
  leftLittleIntermediate("leftLittleIntermediate"),
  leftLittleDistal("leftLittleDistal"),
  rightThumbMetacarpal("rightThumbMetacarpal"),
  rightThumbProximal("rightThumbProximal"),
  rightThumbDistal("rightThumbDistal"),
  rightIndexProximal("rightIndexProximal"),
  rightIndexIntermediate("rightIndexIntermediate"),
  rightIndexDistal("rightIndexDistal"),
  rightMiddleProximal("rightMiddleProximal"),
  rightMiddleIntermediate("rightMiddleIntermediate"),
  rightMiddleDistal("rightMiddleDistal"),
  rightRingProximal("rightRingProximal"),
  rightRingIntermediate("rightRingIntermediate"),
  rightRingDistal("rightRingDistal"),
  rightLittleProximal("rightLittleProximal"),
  rightLittleIntermediate("rightLittleIntermediate"),
  rightLittleDistal("rightLittleDistal");

  final String name;

  const HumanBoneName(this.name);
}
