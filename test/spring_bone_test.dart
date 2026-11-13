import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scene_vrm/src/spring_bone.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  // root -> a -> b -> c, a chain extending along +X
  (Node, Node, Node, Node) buildChain() {
    final root = Node(name: 'root');
    final a = Node(
      name: 'a',
      localTransform: Matrix4.translation(Vector3(0, 1, 0)),
    );
    final b = Node(
      name: 'b',
      localTransform: Matrix4.translation(Vector3(0.5, 0, 0)),
    );
    final c = Node(
      name: 'c',
      localTransform: Matrix4.translation(Vector3(0.5, 0, 0)),
    );
    root.add(a);
    a.add(b);
    b.add(c);
    return (root, a, b, c);
  }

  SpringBoneJointState joint(
    Node node,
    Node child, {
    double stiffness = 1.0,
    double gravityPower = 0.0,
    double dragForce = 0.5,
    double hitRadius = 0.0,
  }) => SpringBoneJointState(
    node: node,
    child: child,
    hitRadius: hitRadius,
    stiffness: stiffness,
    gravityPower: gravityPower,
    gravityDir: Vector3(0, -1, 0),
    dragForce: dragForce,
  );

  void run(SpringBoneSimulator sim, int steps) {
    // Called from onLoad at runtime
    sim.reset();
    for (var i = 0; i < steps; i++) {
      sim.fixedUpdate(1 / 60);
    }
  }

  test('rest pose is kept without external force', () {
    final (_, a, b, c) = buildChain();
    final sim = SpringBoneSimulator([
      SpringBoneChain(joints: [joint(a, b), joint(b, c)], colliders: []),
    ]);
    run(sim, 120);
    final tip = c.globalTransform.getTranslation();
    expect(tip.x, closeTo(1.0, 1e-4));
    expect(tip.y, closeTo(1.0, 1e-4));
  });

  test('gravity bends the chain down and keeps bone length', () {
    final (_, a, b, c) = buildChain();
    final sim = SpringBoneSimulator([
      SpringBoneChain(
        joints: [
          joint(a, b, stiffness: 0, gravityPower: 1),
          joint(b, c, stiffness: 0, gravityPower: 1),
        ],
        colliders: [],
      ),
    ]);
    run(sim, 600);
    final pa = a.globalTransform.getTranslation();
    final pb = b.globalTransform.getTranslation();
    final pc = c.globalTransform.getTranslation();
    expect((pb - pa).length, closeTo(0.5, 1e-4));
    expect((pc - pb).length, closeTo(0.5, 1e-4));
    expect(pc.y, closeTo(0.0, 1e-2));
    expect(pc.x, closeTo(0.0, 1e-2));
  });

  test('sphere collider pushes the tail out', () {
    final (root, a, b, c) = buildChain();
    final colliderNode = Node(
      name: 'collider',
      localTransform: Matrix4.translation(Vector3(0.3, 0.6, 0)),
    );
    root.add(colliderNode);
    final collider = SpringBoneSphereCollider(
      node: colliderNode,
      offset: Vector3.zero(),
      radius: 0.2,
    );
    final sim = SpringBoneSimulator([
      SpringBoneChain(
        joints: [joint(a, b, stiffness: 0, gravityPower: 1)],
        colliders: [collider],
      ),
    ]);
    run(sim, 600);
    final pb = b.globalTransform.getTranslation();
    expect(
      (pb - Vector3(0.3, 0.6, 0)).length,
      greaterThanOrEqualTo(0.2 - 1e-2),
    );
    expect(pb.x, greaterThan(0.3));
  });

  test('capsule collider pushes the tail out', () {
    final (root, a, b, _) = buildChain();
    final colliderNode = Node(name: 'collider');
    root.add(colliderNode);
    final collider = SpringBoneCapsuleCollider(
      node: colliderNode,
      offset: Vector3(0.2, 0.7, -1),
      tail: Vector3(0.2, 0.7, 1),
      radius: 0.1,
    );
    final sim = SpringBoneSimulator([
      SpringBoneChain(
        joints: [joint(a, b, stiffness: 0, gravityPower: 1)],
        colliders: [collider],
      ),
    ]);
    run(sim, 600);
    final pb = b.globalTransform.getTranslation();
    final d = Vector2(pb.x - 0.2, pb.y - 0.7).length;
    expect(d, greaterThanOrEqualTo(0.1 - 1e-2));
  });
}
