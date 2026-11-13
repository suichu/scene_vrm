import 'package:flutter_scene/scene.dart';
import 'package:gltfx/gltfx.dart';
import 'package:gltfx_ext_vrm/gltfx_ext_vrm.dart';

sealed class ExpressionBind {}

class ExpressionMorphBind extends ExpressionBind {
  final Node target;
  final int morph;

  /// Morph target weight when the expression weight is 1.0.
  final double weight;

  ExpressionMorphBind(this.target, this.morph, {this.weight = 1.0});

  void apply(double expressionWeight) {
    target.setMorphWeight(morph, expressionWeight * weight);
  }
}

/// Creates a [MorphBind] if [target] has a morph target at index [morph].
ExpressionMorphBind? _morphBind(Node target, int morph, double weight) {
  final count = target.morphWeights?.length ?? 0;
  if (morph < 0 || morph >= count) return null;
  return ExpressionMorphBind(target, morph, weight: weight);
}

class Expression {
  final List<ExpressionBind> binds;

  /// If true, the weight is rounded to 0 or 1 using 0.5 as the threshold.
  final bool isBinary;
  double _weight = 0.0;

  Expression({this.binds = const [], this.isBinary = false});

  factory Expression.import(
    GltfDocument document,
    VrmcVrmExpression data, {
    required Node node,
  }) {
    final binds = <ExpressionBind>[];
    for (final bind in data.morphTargetBinds) {
      final name = document.nodes[bind.node].name;
      if (name == null) continue;

      final target = node.getChildByName(name);
      if (target == null) continue;

      final b = _morphBind(target, bind.index, bind.weight);
      if (b != null) binds.add(b);
    }
    return Expression(binds: binds, isBinary: data.isBinary);
  }

  /// Loads from a VRM 0.x BlendShapeGroup.
  ///
  /// In 0.x, a bind references `mesh` (a mesh index) and weight is 0-100.
  /// It is applied to every node that uses the same mesh.
  factory Expression.import0(
    GltfDocument document,
    VrmBlendShapeGroup data, {
    required Node node,
  }) {
    final binds = <ExpressionBind>[];
    for (final bind in data.binds) {
      // The schema says NodeIdx, but per the 0.x spec it is a mesh index
      final meshIndex = bind.mesh.value;
      for (final srcNode in document.nodes.items) {
        if (srcNode.mesh?.value != meshIndex) continue;
        final name = srcNode.name;
        if (name == null) continue;
        final target = node.getChildByName(name);
        if (target == null) continue;

        final b = _morphBind(target, bind.index, bind.weight / 100.0);
        if (b != null) binds.add(b);
      }
    }
    return Expression(binds: binds, isBinary: data.isBinary ?? false);
  }

  double get weight => _weight;

  set weight(double value) {
    _weight = value.clamp(0.0, 1.0);
    final applied = isBinary ? (_weight > 0.5 ? 1.0 : 0.0) : _weight;

    for (final bind in binds) {
      if (bind is ExpressionMorphBind) {
        bind.apply(applied);
      }
    }
  }
}

class ExpressionPreset {
  final Expression? happy;
  final Expression? angry;
  final Expression? sad;
  final Expression? relaxed;
  final Expression? surprised;
  final Expression? aa;
  final Expression? ih;
  final Expression? ou;
  final Expression? ee;
  final Expression? oh;
  final Expression? blink;
  final Expression? blinkLeft;
  final Expression? blinkRight;
  final Expression? lookUp;
  final Expression? lookDown;
  final Expression? lookLeft;
  final Expression? lookRight;
  final Expression? neutral;

  const ExpressionPreset({
    this.happy,
    this.angry,
    this.sad,
    this.relaxed,
    this.surprised,
    this.aa,
    this.ih,
    this.ou,
    this.ee,
    this.oh,
    this.blink,
    this.blinkLeft,
    this.blinkRight,
    this.lookUp,
    this.lookDown,
    this.lookLeft,
    this.lookRight,
    this.neutral,
  });
}

class Expressions {
  final ExpressionPreset preset;
  final Map<String, Expression> custom;

  const Expressions({
    this.preset = const ExpressionPreset(),
    this.custom = const {},
  });

  factory Expressions.import(
    GltfDocument document,
    VrmcVrmExpressions data, {
    required Node node,
  }) {
    final preset = ExpressionPreset(
      happy: data.preset.happy != null
          ? Expression.import(document, data.preset.happy!, node: node)
          : null,
      angry: data.preset.angry != null
          ? Expression.import(document, data.preset.angry!, node: node)
          : null,
      sad: data.preset.sad != null
          ? Expression.import(document, data.preset.sad!, node: node)
          : null,
      relaxed: data.preset.relaxed != null
          ? Expression.import(document, data.preset.relaxed!, node: node)
          : null,
      surprised: data.preset.surprised != null
          ? Expression.import(document, data.preset.surprised!, node: node)
          : null,
      aa: data.preset.aa != null
          ? Expression.import(document, data.preset.aa!, node: node)
          : null,
      ih: data.preset.ih != null
          ? Expression.import(document, data.preset.ih!, node: node)
          : null,
      ou: data.preset.ou != null
          ? Expression.import(document, data.preset.ou!, node: node)
          : null,
      ee: data.preset.ee != null
          ? Expression.import(document, data.preset.ee!, node: node)
          : null,
      oh: data.preset.oh != null
          ? Expression.import(document, data.preset.oh!, node: node)
          : null,
      blink: data.preset.blink != null
          ? Expression.import(document, data.preset.blink!, node: node)
          : null,
      blinkLeft: data.preset.blinkLeft != null
          ? Expression.import(document, data.preset.blinkLeft!, node: node)
          : null,
      blinkRight: data.preset.blinkRight != null
          ? Expression.import(document, data.preset.blinkRight!, node: node)
          : null,
      lookUp: data.preset.lookUp != null
          ? Expression.import(document, data.preset.lookUp!, node: node)
          : null,
      lookDown: data.preset.lookDown != null
          ? Expression.import(document, data.preset.lookDown!, node: node)
          : null,
      lookLeft: data.preset.lookLeft != null
          ? Expression.import(document, data.preset.lookLeft!, node: node)
          : null,
      lookRight: data.preset.lookRight != null
          ? Expression.import(document, data.preset.lookRight!, node: node)
          : null,
      neutral: data.preset.neutral != null
          ? Expression.import(document, data.preset.neutral!, node: node)
          : null,
    );
    final custom = <String, Expression>{};
    final srcCustom = data.custom;
    for (final entry in srcCustom.entries) {
      custom[entry.key] = Expression.import(document, entry.value, node: node);
    }

    return Expressions(preset: preset, custom: custom);
  }

  /// Loads from VRM 0.x `blendShapeMaster`.
  ///
  /// Preset names are mapped to their VRM 1.0 names
  /// (joy→happy, sorrow→sad, fun→relaxed, a/i/u/e/o→aa/ih/ou/ee/oh, etc.).
  /// Groups with `unknown` or no preset are registered by name in [custom].
  factory Expressions.import0(
    GltfDocument document,
    VrmBlendShape data, {
    required Node node,
  }) {
    final presets = <BlendShapePreset0, Expression>{};
    final custom = <String, Expression>{};

    for (final group in data.blendShapeGroups ?? const <VrmBlendShapeGroup>[]) {
      final expression = Expression.import0(document, group, node: node);
      final preset = group.presetName;
      if (preset != null && preset != BlendShapePreset0.unknown) {
        presets.putIfAbsent(preset, () => expression);
      } else {
        final name = group.name;
        if (name != null && name.isNotEmpty) {
          custom.putIfAbsent(name, () => expression);
        }
      }
    }

    return Expressions(
      preset: ExpressionPreset(
        happy: presets[BlendShapePreset0.joy],
        angry: presets[BlendShapePreset0.angry],
        sad: presets[BlendShapePreset0.sorrow],
        relaxed: presets[BlendShapePreset0.fun],
        aa: presets[BlendShapePreset0.a],
        ih: presets[BlendShapePreset0.i],
        ou: presets[BlendShapePreset0.u],
        ee: presets[BlendShapePreset0.e],
        oh: presets[BlendShapePreset0.o],
        blink: presets[BlendShapePreset0.blink],
        blinkLeft: presets[BlendShapePreset0.blinkL],
        blinkRight: presets[BlendShapePreset0.blinkR],
        lookUp: presets[BlendShapePreset0.lookup],
        lookDown: presets[BlendShapePreset0.lookdown],
        lookLeft: presets[BlendShapePreset0.lookleft],
        lookRight: presets[BlendShapePreset0.lookright],
        neutral: presets[BlendShapePreset0.neutral],
      ),
      custom: custom,
    );
  }
}
