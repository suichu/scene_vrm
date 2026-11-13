import 'dart:math';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_scene/scene.dart';
import 'package:material_ui/material_ui.dart';
import 'package:scene_vrm/scene_vrm.dart';
import 'package:vector_math/vector_math.dart' as vm32;
import 'package:flutter/services.dart' show rootBundle;
import 'package:vector_math/vector_math_64.dart' hide Colors;

import 'orbit.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VRM Example',
      theme: ThemeData(colorScheme: .fromSeed(seedColor: Colors.deepPurple)),
      home: const SceneInitializer(),
    );
  }
}

class SceneInitializer extends StatefulWidget {
  const SceneInitializer({super.key});

  @override
  State<SceneInitializer> createState() => _SceneInitializerState();
}

class _SceneInitializerState extends State<SceneInitializer> {
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    Scene.initializeStaticResources().then((_) async {
      setState(() {
        _initialized = true;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) return Container();
    return MyHomePage(title: 'VRM Example');
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  Uint8List? _blob;

  @override
  void initState() {
    super.initState();
    rootBundle.load("assets/mendako_chan.vrm").then((asset) {
      final blob = asset.buffer.asUint8List();
      setState(() {
        _blob = blob;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final blob = _blob;
    return Scaffold(
      body: Stack(
        children: [
          if (blob != null) _Viewer(blob: blob),
          Positioned(
            left: 16,
            bottom: 16,
            child: FloatingActionButton(
              mini: true,
              child: Icon(Icons.file_open),
              onPressed: () {
                FilePicker.pickFile().then((file) {
                  if (file != null) {
                    file
                        .readAsBytes()
                        .then((bytes) {
                          setState(() {
                            _blob = bytes;
                          });
                        })
                        .catchError((error) {
                          debugPrint(error.toString());
                        });
                  }
                });
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Viewer extends StatefulWidget {
  final Uint8List blob;

  _Viewer({required this.blob}) : super(key: ObjectKey(blob));

  @override
  State<_Viewer> createState() => _ViewerState();
}

class _ViewerState extends State<_Viewer> with SingleTickerProviderStateMixin {
  final Scene scene = Scene();
  final PerspectiveCamera camera = PerspectiveCamera(
    fovRadiansY: 60.0 * degrees2Radians,
    position: vm32.Vector3(0.0, 0.5, -1.5),
    target: vm32.Vector3(0.0, 0.5, 0.0),
  );
  final OrbitController orbit = OrbitController(
    fov: 60.0,
    lookFrom: Vector3(0.0, 0.5, -1.5),
    lookAt: Vector3(0.0, 0.5, 0.0),
  );
  bool _initialized = false;

  @override
  void initState() {
    super.initState();

    loadVrmBytes(widget.blob)
        .then((avatar) async {
          final humanoid = avatar.getComponent<Vrm>();
          if (humanoid != null) {
            final animation = await VrmAnimation.fromAsset(
              "assets/VRMA_01.vrma",
            );
            final clip = humanoid.createAnimationClip(animation);
            clip.play();
          }

          final ticker = createTicker((_) {
            setState(() {});
          });
          ticker.start();

          final bytes = await rootBundle.load("assets/lightroom_14b.hdr");
          final env = await EnvironmentMap.fromEquirectImageBytes(
            bytes: bytes.buffer.asUint8List(),
          );

          scene.add(avatar);
          scene.environment = env;

          orbit.addListener(() {
            setState(() {
              final from = orbit.transform.getTranslation();
              final up = orbit.transform.up;
              camera.up = vm32.Vector3(up.x, up.y, up.z);
              camera.position = vm32.Vector3(from.x, from.y, from.z);
              camera.target = vm32.Vector3(
                orbit.lookAt.x,
                orbit.lookAt.y,
                orbit.lookAt.z,
              );
            });
          });

          setState(() {
            _initialized = true;
          });
        })
        .catchError((error) {
          debugPrint(error.toString());
        });
  }

  @override
  void dispose() {
    super.dispose();
    orbit.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) return SizedBox.expand();

    return SizedBox.expand(
      child: OrbitGestureDetector(
        controller: orbit,
        child: CustomPaint(
          painter: _ScenePainter(scene: scene, camera: camera),
        ),
      ),
    );
  }
}

class _ScenePainter extends CustomPainter {
  final Scene scene;
  final PerspectiveCamera camera;

  _ScenePainter({required this.scene, required this.camera});

  @override
  void paint(Canvas canvas, Size size) {
    scene.render(camera, canvas, viewport: Offset.zero & size);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
