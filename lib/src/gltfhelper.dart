import 'package:gltfx/gltfx.dart';
import 'package:vector_math/vector_math.dart';

Matrix4 getNodeWorldMatrix(GltfDocument document, GltfNode node) {
  final i =
      document.nodes.indexed.firstWhere((i) => i.$2 == node).$1 as NodeIdx;
  final m = getNodeMatrix(node);
  ;

  for (final p in document.nodes.items) {
    if (p.children.contains(i)) {
      return getNodeWorldMatrix(document, p)..multiply(m);
    }
  }

  return m;
}

/// Rotates [v] by [q].
///
/// vector_math's `Quaternion.rotate` / `rotated` apply the inverse rotation,
/// so this goes through a matrix (same convention as `asRotationMatrix` / `Matrix4.compose`).
Vector3 rotateByQuaternion(Quaternion q, Vector3 v) =>
    q.asRotationMatrix().transformed(v.clone());

Matrix4 getNodeMatrix(GltfNode node) {
  switch (node.transform) {
    case MatrixTransform(matrix: final m):
      return Matrix4.fromList(m);
    case TrsTransform(translation: final t, rotation: final r, scale: final s):
      return Matrix4.compose(
        t != null ? Vector3.fromFloat32List(t) : Vector3.zero(),
        r != null ? Quaternion.fromFloat32List(r) : Quaternion.identity(),
        s != null ? Vector3.fromFloat32List(s) : Vector3.all(1.0),
      );
  }
}
