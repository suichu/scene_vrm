import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart';

class RestTransform extends Component {
  Matrix4 local;
  Matrix4 world;

  RestTransform({required this.local, required this.world});
}
