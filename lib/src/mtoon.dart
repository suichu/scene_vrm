import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:flutter_scene/gpu.dart';
import 'package:flutter_scene/scene.dart';
import 'package:gltfx/gltfx.dart';
import 'package:vector_math/vector_math.dart';
import 'package:gltfx_ext_vrm/gltfx_ext_vrm.dart';

class MToonMaterial extends PreprocessedMaterial {
  MToonMaterial({
    required super.fragmentShader,
    required super.metadata,
    super.vertexShaders,
    super.radianceCubeFragmentShader,
  });

  @override
  void bind(dynamic pass, TransientWriter transientsBuffer, Lighting lighting) {
    parameters.setVec3(
      "sun_direction",
      lighting.directionalLightDirection ?? Vector3(0, 1, 0),
    );

    final sunColor =
        (lighting.directionalLight?.color ?? Vector3(0, 0, 0)) *
        (lighting.directionalLight?.intensity ?? 1.0);

    parameters.setVec4(
      "sun_color",
      Vector4(sunColor.x, sunColor.y, sunColor.z, 1.0),
    );

    parameters.setFloat("environment_intensity", lighting.environmentIntensity);

    parameters.setTexture(
      "irradiance_field",
      lighting.environmentMap.diffuseShTexture,
    );

    super.bind(pass, transientsBuffer, lighting);
  }
}

Future<void> loadMToon(GltfDocument document, Node root) async {
  final mtoons = <int, (Material, Material?)>{};
  final imageCache = <TextureIdx, Texture2D>{};

  Future<Texture2D> decode(TextureIdx i) async {
    final imgIdx = document.textures[i].source;
    if (imgIdx == null) throw Exception("Image index not found for texture $i");

    if (!imageCache.containsKey(i)) {
      final data = document.imageData[imgIdx];
      if (data == null) throw Exception("Image data not found for index $i");
      final img = await decodeImageFromList(data);
      imageCache[i] = await Texture2D.fromImage(img);
    }
    return imageCache[i]!;
  }

  final samplerCache = <TextureIdx, SamplerOptions>{};

  /// Converts the glTF sampler referenced by texture [i] to SamplerOptions.
  SamplerOptions samplerFor(TextureIdx i, Texture2D tex) =>
      samplerCache.putIfAbsent(i, () {
        final samplerIdx = document.textures[i].sampler;
        if (samplerIdx == null ||
            samplerIdx.value < 0 ||
            samplerIdx.value >= document.samplers.length) {
          return tex.sampledSampler;
        }
        return gltfSamplerOptions(
          document.samplers[samplerIdx],
          tex.sampledSampler,
        );
      });

  /// Decodes texture [i] and returns it with SamplerOptions following its glTF sampler.
  /// Returns null if [i] is null.
  Future<(Texture, SamplerOptions?)?> load(TextureIdx? i) async {
    if (i == null) return null;
    final tex = await decode(i);
    return (tex.gpuTexture, samplerFor(i, tex));
  }

  final vrm0Materials = document.extensions?.get(vrm)?.materialProperties;

  for (final (idx, m) in document.materials.indexed) {
    final MToonSource? source;
    if (m.extensions?.get(vrmcMaterialsMToon) case final mtoon?) {
      source = MToonSource.fromGltf(m, mtoon);
    } else if (vrm0Materials != null && idx < vrm0Materials.length) {
      source = MToonSource.fromVrm0(vrm0Materials[idx]);
    } else {
      source = null;
    }

    if (source != null) {
      final mtoon = source.mtoon;
      final mat = await loadFmatMaterial(
        "assets/mtoon.fmat",
        factory:
            ({required fragmentShader, required metadata, vertexShaders}) =>
                MToonMaterial(
                  fragmentShader: fragmentShader,
                  metadata: metadata,
                  vertexShaders: vertexShaders,
                ),
      );

      final mName = m.name;
      if (mName != null) {
        mat.name = mName;
      }
      mat.parameters.setVec4(
        "color",
        Vector4.fromFloat32List(
          source.baseColorFactor ?? Float32List.fromList([1, 1, 1, 1]),
        ),
      );

      final (baseColorTex, baseColorSampler) =
          await load(source.baseColorTexture) ??
          (Material.getWhitePlaceholderTexture(), null);
      mat.parameters.setTexture(
        "base_color_texture",
        baseColorTex,
        sampler: baseColorSampler,
      );

      mat.parameters.setVec4(
        "shade_color",
        Vector4(
          mtoon.shadeColorFactor?[0] ?? 0,
          mtoon.shadeColorFactor?[1] ?? 0,
          mtoon.shadeColorFactor?[2] ?? 0,
          1,
        ),
      );

      mat.parameters.setFloat("shading_shift", mtoon.shadingShiftFactor);

      mat.parameters.setFloat("shading_toony", mtoon.shadingToonyFactor);

      final (shadeTex, shadeSampler) =
          await load(mtoon.shadeMultiplyTexture?.index) ??
          (Material.getWhitePlaceholderTexture(), null);
      mat.parameters.setTexture(
        "shade_color_texture",
        shadeTex,
        sampler: shadeSampler,
      );

      final (shadingShiftTex, shadingShiftSampler) =
          await load(mtoon.shadingShiftTexture?.index) ??
          (Material.getBlackPlaceholderTexture(), null);
      mat.parameters.setTexture(
        "shading_shift_texture",
        shadingShiftTex,
        sampler: shadingShiftSampler,
      );

      final rimColor = Vector3(
        mtoon.parametricRimColorFactor?[0] ?? 0,
        mtoon.parametricRimColorFactor?[1] ?? 0,
        mtoon.parametricRimColorFactor?[2] ?? 0,
      );

      final matcapFactor = Vector3(
        mtoon.matcapFactor?[0] ?? 1,
        mtoon.matcapFactor?[1] ?? 1,
        mtoon.matcapFactor?[2] ?? 1,
      );

      final emissiveFactor = Vector3(
        source.emissiveFactor?[0] ?? 0,
        source.emissiveFactor?[1] ?? 0,
        source.emissiveFactor?[2] ?? 0,
      );

      mat.parameters
        ..setFloat("gi_equalization_factor", mtoon.giEqualizationFactor)
        ..setVec3("matcap_factor", matcapFactor)
        ..setVec3("rim_color", rimColor)
        ..setFloat("rim_power", mtoon.parametricRimFresnelPowerFactor)
        ..setFloat("rim_lift", mtoon.parametricRimLiftFactor)
        ..setFloat("rim_mix", mtoon.rimLightingMixFactor)
        ..setVec3("emissive_factor", emissiveFactor);

      final (emissiveTex, emissiveSampler) =
          await load(source.emissiveTexture) ??
          (Material.getWhitePlaceholderTexture(), null);
      mat.parameters.setTexture(
        "emissive_texture",
        emissiveTex,
        sampler: emissiveSampler,
      );

      final emissiveStrength = source.emissiveStrength;
      if (emissiveStrength != null) {
        mat.parameters.setFloat("emissive_strength", emissiveStrength);
      }

      final (matcapTex, matcapSampler) =
          await load(mtoon.matcapTexture?.index) ??
          (Material.getBlackPlaceholderTexture(), null);
      mat.parameters.setTexture(
        "matcap_texture",
        matcapTex,
        sampler: matcapSampler,
      );

      final (rimTex, rimSampler) =
          await load(mtoon.rimMultiplyTexture?.index) ??
          (Material.getWhitePlaceholderTexture(), null);
      mat.parameters.setTexture("rim_texture", rimTex, sampler: rimSampler);

      final (uvMaskTex, uvMaskSampler) =
          await load(mtoon.uvAnimationMaskTexture?.index) ??
          (Material.getWhitePlaceholderTexture(), null);
      mat.parameters.setTexture(
        "uv_animation_mask",
        uvMaskTex,
        sampler: uvMaskSampler,
      );

      mat.parameters.setVec2(
        "uv_scroll",
        Vector2(
          mtoon.uvAnimationScrollXSpeedFactor,
          mtoon.uvAnimationScrollYSpeedFactor,
        ),
      );

      mat.parameters.setFloat(
        "uv_rotation",
        mtoon.uvAnimationRotationSpeedFactor,
      );

      final outlineMode = mtoon.outlineWidthMode;
      if (outlineMode != OutlineWidthMode.none &&
          mtoon.outlineWidthFactor > 0.0) {
        final outline = await loadFmatMaterial("assets/outline.fmat");
        if (mName != null) {
          outline.name = '${mName}_outline';
        }
        if (outlineMode == OutlineWidthMode.screenCoordinates) {
          outline.parameters.setInt("outline_mode", 1);
        }

        outline.parameters.setFloat("outline_width", mtoon.outlineWidthFactor);

        outline.parameters.setVec4(
          "outline_color",
          Vector4(
            mtoon.outlineColorFactor?[0] ?? 0,
            mtoon.outlineColorFactor?[1] ?? 0,
            mtoon.outlineColorFactor?[2] ?? 0,
            1,
          ),
        );

        /*
        final outlineWidthMultiplyTexture = mtoon.outlineWidthMultiplyTexture;
        if (outlineWidthMultiplyTexture != null) {
          final tex = await decode(outlineWidthMultiplyTexture.index);
          outline.parameters.setTexture(
            "outline_width_multiply_texture",
            tex.gpuTexture,
          );
        } else {
          outline.parameters.setTexture(
            "outline_width_multiply_texture",
            Material.getWhitePlaceholderTexture(),
          );
        }
        */

        mtoons[idx] = (mat, outline);
      } else {
        mtoons[idx] = (mat, null);
      }
    }
  }

  final mtoonInstalled = HashSet<Mesh>();

  for (final jsNode in document.nodes.items) {
    if (jsNode.mesh != null) {
      final jsMesh = document.meshes[jsNode.mesh!];
      if (jsMesh.primitives.any((e) => mtoons.containsKey(e.material))) {
        if (jsNode.name != null) {
          final nd = root.getChildByName(jsNode.name!);
          if (nd != null) {
            final mesh = nd.mesh;
            if (mesh != null && !mtoonInstalled.contains(mesh)) {
              final outlines = <MeshPrimitive>[];
              for (var i = 0; i < mesh.primitives.length; i++) {
                final m = mtoons[jsMesh.primitives[i].material];
                if (m != null) {
                  final p = mesh.primitives[i];
                  p.material = m.$1;
                  final outlineMaterial = m.$2;
                  if (outlineMaterial != null) {
                    final outline = MeshPrimitive(p.geometry, outlineMaterial);
                    outlines.add(outline);
                  }
                }
              }
              mesh.primitives.insertAll(0, outlines);
              mtoonInstalled.add(mesh);
            }
          }
        }
      }
    }
  }
}

/// Parameters needed to build an MToon material.
///
/// Stored in the 1.0 representation so it can be built from both VRM 1.0
/// (`VRMC_materials_mtoon` + glTF material) and VRM 0.x (`materialProperties`). All colors are linear.
class MToonSource {
  final VrmcMaterialsMToon mtoon;
  final Float32List? baseColorFactor;
  final TextureIdx? baseColorTexture;
  final Float32List? emissiveFactor;
  final TextureIdx? emissiveTexture;
  final double? emissiveStrength;

  const MToonSource({
    required this.mtoon,
    this.baseColorFactor,
    this.baseColorTexture,
    this.emissiveFactor,
    this.emissiveTexture,
    this.emissiveStrength,
  });

  factory MToonSource.fromGltf(GltfMaterial m, VrmcMaterialsMToon mtoon) =>
      MToonSource(
        mtoon: mtoon,
        baseColorFactor: m.pbrMetallicRoughness?.baseColorFactor,
        baseColorTexture: m.pbrMetallicRoughness?.baseColorTexture?.index,
        emissiveFactor: m.emissiveFactor,
        emissiveTexture: m.emissiveTexture?.index,
        emissiveStrength: m.extensions
            ?.get(khrMaterialsEmissiveStrength)
            ?.emissiveStrength,
      );

  /// Converts from VRM 0.x `materialProperties`. Returns null if the shader is not `VRM/MToon`.
  ///
  /// The conversion follows the VRM 1.0 migration spec (UniVRM / three-vrm compatibility handling).
  static MToonSource? fromVrm0(VrmMaterial m) {
    if (m.shader != 'VRM/MToon') return null;

    final f = m.floatProperties;
    final v = m.vectorProperties;
    final t = m.textureProperties;

    TextureIdx? tex(String name) {
      final i = t[name];
      return i != null && i >= 0 ? TextureIdx(i) : null;
    }

    GltfTextureInfo? texInfo(String name) {
      final i = tex(name);
      return i != null ? GltfTextureInfo(index: i, texCoord: 0) : null;
    }

    /// Converts an sRGB color to linear (alpha is unchanged).
    Float32List? color(String name, {bool alpha = false}) {
      final c = v[name];
      if (c == null || c.length < 3) return null;
      return Float32List.fromList([
        srgbToLinear(c[0]),
        srgbToLinear(c[1]),
        srgbToLinear(c[2]),
        if (alpha) c.length >= 4 ? c[3] : 1.0,
      ]);
    }

    final (:shadingShift, :shadingToony) = convertVrm0Shading(
      shadeShift: f['_ShadeShift'] ?? 0.0,
      shadeToony: f['_ShadeToony'] ?? 0.9,
    );

    final outlineWidthMode = switch ((f['_OutlineWidthMode'] ?? 0).round()) {
      1 => OutlineWidthMode.worldCoordinates,
      2 => OutlineWidthMode.screenCoordinates,
      _ => OutlineWidthMode.none,
    };
    final outlineColorMode = (f['_OutlineColorMode'] ?? 0).round();

    final matcapTexture = texInfo('_SphereAdd');

    return MToonSource(
      mtoon: VrmcMaterialsMToon(
        specVersion: '1.0',
        shadeColorFactor: color('_ShadeColor'),
        shadeMultiplyTexture: texInfo('_ShadeTexture'),
        shadingShiftFactor: shadingShift,
        shadingToonyFactor: shadingToony,
        giEqualizationFactor: 1.0 - (f['_IndirectLightIntensity'] ?? 0.1),
        matcapFactor: matcapTexture != null
            ? Float32List.fromList([1, 1, 1])
            : Float32List.fromList([0, 0, 0]),
        matcapTexture: matcapTexture,
        parametricRimColorFactor: color('_RimColor'),
        parametricRimFresnelPowerFactor: f['_RimFresnelPower'] ?? 1.0,
        parametricRimLiftFactor: f['_RimLift'] ?? 0.0,
        rimMultiplyTexture: texInfo('_RimTexture'),
        rimLightingMixFactor: f['_RimLightingMix'] ?? 0.0,
        outlineWidthMode: outlineWidthMode,
        // 0.x world mode is in centimeters
        outlineWidthFactor: (f['_OutlineWidth'] ?? 0.0) * 0.01,
        outlineWidthMultiplyTexture: texInfo('_OutlineWidthTexture'),
        outlineColorFactor: color('_OutlineColor'),
        outlineLightingMixFactor: outlineColorMode == 1
            ? f['_OutlineLightingMix'] ?? 1.0
            : 0.0,
        uvAnimationMaskTexture: texInfo('_UvAnimMaskTexture'),
        uvAnimationScrollXSpeedFactor: f['_UvAnimScrollX'] ?? 0.0,
        // The UV V direction is reversed between 0.x and 1.0
        uvAnimationScrollYSpeedFactor: -(f['_UvAnimScrollY'] ?? 0.0),
        uvAnimationRotationSpeedFactor: f['_UvAnimRotation'] ?? 0.0,
      ),
      baseColorFactor: color('_Color', alpha: true),
      baseColorTexture: tex('_MainTex'),
      emissiveFactor: color('_EmissionColor'),
      emissiveTexture: tex('_EmissionMap'),
    );
  }
}

/// Converts a glTF [sampler] to Flutter GPU [SamplerOptions].
/// Filters not specified in glTF inherit from [base] (the texture's default sampling).
///
/// wrap maps 33071 CLAMP_TO_EDGE / 33648 MIRRORED_REPEAT / 10497 REPEAT.
/// mipmap minFilters (9984-9987) also determine mipFilter. NEAREST / LINEAR
/// (9728 / 9729) should sample only the base level, but SamplerOptions has no such mode, so
/// the mipFilter of [base] is kept. Anisotropic filtering is enabled only when all filters are linear.
SamplerOptions gltfSamplerOptions(GltfSampler sampler, SamplerOptions base) {
  SamplerAddressMode wrap(int mode) => switch (mode) {
    GltfSampler.clampToEdge => SamplerAddressMode.clampToEdge,
    GltfSampler.mirroredRepeat => SamplerAddressMode.mirror,
    _ => SamplerAddressMode.repeat,
  };

  final mag = switch (sampler.magFilter) {
    GltfSampler.nearest => MinMagFilter.nearest,
    GltfSampler.linear => MinMagFilter.linear,
    _ => base.magFilter,
  };

  final (min, mip) = switch (sampler.minFilter) {
    GltfSampler.nearest => (MinMagFilter.nearest, base.mipFilter),
    GltfSampler.linear => (MinMagFilter.linear, base.mipFilter),
    GltfSampler.nearestMipmapNearest => (
      MinMagFilter.nearest,
      MipFilter.nearest,
    ),
    GltfSampler.linearMipmapNearest => (MinMagFilter.linear, MipFilter.nearest),
    GltfSampler.nearestMipmapLinear => (MinMagFilter.nearest, MipFilter.linear),
    GltfSampler.linearMipmapLinear => (MinMagFilter.linear, MipFilter.linear),
    _ => (base.minFilter, base.mipFilter),
  };

  final allLinear =
      min == MinMagFilter.linear &&
      mag == MinMagFilter.linear &&
      mip == MipFilter.linear;

  return SamplerOptions(
    minFilter: min,
    magFilter: mag,
    mipFilter: mip,
    widthAddressMode: wrap(sampler.wrapS),
    heightAddressMode: wrap(sampler.wrapT),
    maxAnisotropy: allLinear ? base.maxAnisotropy : 1,
  );
}

/// Converts VRM 0.x `_ShadeShift` / `_ShadeToony` to VRM 1.0
/// `shadingShiftFactor` / `shadingToonyFactor`.
({double shadingShift, double shadingToony}) convertVrm0Shading({
  required double shadeShift,
  required double shadeToony,
}) {
  final t = 0.5 + 0.5 * shadeShift;
  final shadingToony = shadeToony + (1.0 - shadeToony) * t;
  final shadingShift = -shadeShift - (1.0 - shadingToony);
  return (shadingShift: shadingShift, shadingToony: shadingToony);
}

/// Converts an sRGB value (0-1) to linear.
double srgbToLinear(double c) =>
    c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
