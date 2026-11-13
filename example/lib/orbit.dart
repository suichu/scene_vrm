import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/gestures.dart';
import 'package:vector_math/vector_math_64.dart'
    show Quaternion, Vector3, radians;

class OrbitController extends ChangeNotifier {
  double fov;
  double _distance;
  Quaternion _rotation;
  Vector3 _lookAt;

  OrbitController({
    required this.fov,
    required Vector3 lookFrom,
    required lookAt,
  }) : _distance = (lookFrom - lookAt).length,
       _rotation = Quaternion.fromTwoVectors(
         Vector3(0, 0, -1),
         lookAt - lookFrom,
       ),
       _lookAt = lookAt;

  void reset({
    required Vector3 lookFrom,
    required Vector3 lookAt,
    double? fov,
  }) {
    _distance = (lookFrom - lookAt).length;
    _rotation = Quaternion.fromTwoVectors(Vector3(0, 0, 1), lookAt - lookFrom);
    _lookAt = lookAt;
    if (fov != null) this.fov = fov;

    notifyListeners();
  }

  double get distance => _distance;
  set distance(double value) {
    _distance = value;
    notifyListeners();
  }

  Quaternion get rotation => _rotation;
  set rotation(Quaternion value) {
    _rotation = value;
    notifyListeners();
  }

  Vector3 get lookAt => _lookAt;
  set lookAt(Vector3 value) {
    _lookAt = value;
    notifyListeners();
  }

  Matrix4 get transform =>
      Matrix4.compose(lookAt, _rotation, Vector3.all(1.0))
        ..translateByVector3(Vector3(0, 0, -_distance));
}

class OrbitGestureDetector extends StatefulWidget {
  final OrbitController controller;
  final Widget child;

  const OrbitGestureDetector({
    super.key,
    required this.controller,
    required this.child,
  });

  @override
  OrbitGestureDetectorState createState() => OrbitGestureDetectorState();
}

class OrbitGestureDetectorState extends State<OrbitGestureDetector>
    with SingleTickerProviderStateMixin {
  late Ticker _ticker;
  FrictionSimulation? _sim;
  double _radius = 0.0;
  double _elapsed = 0.0;
  double _scrollDirection = 0.0;
  double _currentPosition = 0.0;
  double _startDistance = 0.0;
  PointerDeviceKind _kind = PointerDeviceKind.touch;

  @override
  void initState() {
    _ticker = createTicker((elapsed) {
      _elapsed += elapsed.inMilliseconds / 1000.0;
      final sim = _sim;
      if (sim == null) {
        _ticker.stop();
        return;
      }

      final x = sim.x(_elapsed);
      if (x - _currentPosition > 0.0) {
        final d = Offset.fromDirection(_scrollDirection, x - _currentPosition);
        onOrbit(d);
        _currentPosition = x;
      }
      if (sim.isDone(_elapsed)) {
        _ticker.stop();
      }
    });

    super.initState();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void onOrbit(Offset delta, {double tilt = 0.0}) {
    if (delta.distance == 0.0) return;

    final denom = _radius * radians(45);
    widget.controller.rotation =
        Quaternion.axisAngle(Vector3(0, 1, 0), delta.dx / denom) *
        widget.controller.rotation *
        Quaternion.axisAngle(Vector3(-1, 0, 0), delta.dy / denom);
  }

  void onPan(Offset delta) {
    final v = Vector3(-delta.dx, delta.dy, 0.0);
    widget.controller.lookAt +=
        (v /
              _radius /
              (tan(radians(widget.controller.fov / 2)) *
                  widget.controller.distance))
          ..applyQuaternion(widget.controller.rotation);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _radius = constraints.maxHeight / 2;
        final touchDetector = GestureDetector(
          supportedDevices: {
            PointerDeviceKind.touch,
            PointerDeviceKind.trackpad,
          },
          onScaleStart: (details) {
            _ticker.stop();
            _startDistance = widget.controller.distance;
            _kind = details.kind ?? PointerDeviceKind.touch;
          },
          onScaleUpdate: (details) {
            widget.controller.distance = _startDistance / details.scale;
            onOrbit(details.focalPointDelta);
          },
          onScaleEnd: (details) {
            final vel = details.velocity.pixelsPerSecond.distance;
            _sim = FrictionSimulation(0.035, 0.0, vel * 0.8);
            _elapsed = 0.0;
            _currentPosition = 0.0;
            _scrollDirection = details.velocity.pixelsPerSecond.direction;
            _ticker.start();
          },
          child: widget.child,
        );

        final mouseDetector = RawGestureDetector(
          gestures: {
            PanGestureRecognizer:
                GestureRecognizerFactoryWithHandlers<PanGestureRecognizer>(
                  () => PanGestureRecognizer(
                    debugOwner: this,
                    supportedDevices: {PointerDeviceKind.mouse},
                    allowedButtonsFilter: (buttons) =>
                        buttons == kTertiaryButton,
                  ),
                  (PanGestureRecognizer instance) {
                    instance.onUpdate = (details) {
                      onOrbit(details.delta, tilt: details.delta.dy);
                    };
                  },
                ),
          },
          child: RawGestureDetector(
            gestures: {
              PanGestureRecognizer:
                  GestureRecognizerFactoryWithHandlers<PanGestureRecognizer>(
                    () => PanGestureRecognizer(
                      debugOwner: this,
                      supportedDevices: {PointerDeviceKind.mouse},
                      allowedButtonsFilter: (buttons) =>
                          buttons == kPrimaryButton,
                    ),
                    (PanGestureRecognizer instance) {
                      instance.onUpdate = (details) {
                        onPan(details.delta);
                      };
                    },
                  ),
            },
            child: touchDetector,
          ),
        );

        return Listener(
          onPointerSignal: (event) {
            if (event is PointerScrollEvent) {
              widget.controller.distance += event.scrollDelta.dy / _radius;
            }
          },
          child: mouseDetector,
        );
      },
    );
  }
}
