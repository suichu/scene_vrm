import 'package:hooks/hooks.dart';
import 'package:flutter_scene/build_hooks.dart';

void main(List<String> args) {
  build(args, (input, output) async {
    await buildMaterials(buildInput: input, buildOutput: output);
  });
}
