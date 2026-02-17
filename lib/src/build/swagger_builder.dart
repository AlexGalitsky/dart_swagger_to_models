import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:build/build.dart';
import 'package:dart_swagger_to_models/dart_swagger_to_models.dart';
import 'package:dart_swagger_to_models/src/config/config_loader.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// Builder for generating Dart models from Swagger/OpenAPI specifications.
///
/// This Builder processes spec files (`.yaml`, `.yml`, `.json`)
/// and generates Dart models in the configured output directory.
///
/// Configuration is read from `dart_swagger_to_models.yaml` in the project root.
///
/// Usage:
/// 1. Create a `build.yaml` file in the project root:
/// ```yaml
/// targets:
///   $default:
///     builders:
///       dart_swagger_to_models|swaggerBuilder:
///         enabled: true
/// ```
/// 2. Put your spec files into `swagger/` or `openapi/` directories
/// 3. Run `dart run build_runner build`
class SwaggerBuilder implements Builder {
  /// Configuration file name.
  static const String configFileName = 'dart_swagger_to_models.yaml';

  @override
  Map<String, List<String>> get buildExtensions => {
        // Process spec files and generate Dart files
        '.yaml': ['.dart'],
        '.yml': ['.dart'],
        '.json': ['.dart'],
      };

  @override
  FutureOr<void> build(BuildStep buildStep) async {
    final inputId = buildStep.inputId;

    // Skip files that are not OpenAPI/Swagger specs
    if (!_isSpecFile(inputId.path)) {
      return;
    }

    // Read specification
    final specContent = await buildStep.readAsString(inputId);
    Map<String, dynamic> spec;
    try {
      if (inputId.path.endsWith('.json')) {
        spec = jsonDecode(specContent) as Map<String, dynamic>;
      } else {
        // For YAML use yaml package
        final yaml = loadYaml(specContent) as Map;
        spec = Map<String, dynamic>.from(
            yaml.map((k, v) => MapEntry(k.toString(), v)));
      }
    } catch (e) {
      log.warning('Failed to parse specification ${inputId.path}: $e');
      return;
    }

    // Ensure this is really a Swagger/OpenAPI specification
    if (!_isSwaggerOrOpenApiSpec(spec)) {
      return; // Skip files that are not specs
    }

    // Find project root
    final projectRoot = await _findProjectRoot(buildStep);

    // Read configuration
    final configPath = p.join(projectRoot, configFileName);
    Config? config;
    try {
      config = await ConfigLoader.loadConfig(configPath, projectRoot);
    } catch (e) {
      // Configuration is optional
      log.fine('Configuration not found: $e');
    }

    // Determine output directory
    final outputDir = config?.outputDir ?? 'lib/generated/models';
    final effectiveOutputDir =
        p.isAbsolute(outputDir) ? outputDir : p.join(projectRoot, outputDir);

    // Create temporary file for the spec (build_runner works with AssetId)
    final tempSpecFile = File(p.join(
        Directory.systemTemp.path, '${inputId.path.replaceAll('/', '_')}'));
    try {
      await tempSpecFile.writeAsString(specContent);

      // Generate models
      final result = await SwaggerToDartGenerator.generateModels(
        input: tempSpecFile.path,
        outputDir: effectiveOutputDir,
        projectDir: projectRoot,
        config: config,
      );

      // Write generated files as output assets
      for (final generatedFile in result.generatedFiles) {
        final file = File(generatedFile);
        if (await file.exists()) {
          final content = await file.readAsString();
          // Determine AssetId for the output file
          final relativePath = p.relative(generatedFile, from: projectRoot);
          final outputAssetId = AssetId(
            inputId.package,
            relativePath.replaceAll('\\', '/'),
          );
          await buildStep.writeAsString(outputAssetId, content);
        }
      }

      log.info(
        'Generated ${result.generatedFiles.length} files from ${inputId.path}',
      );
    } catch (e, st) {
      log.severe('Error generating models from ${inputId.path}: $e');
      log.fine(st.toString());
    } finally {
      // Delete temporary file
      if (await tempSpecFile.exists()) {
        await tempSpecFile.delete();
      }
    }
  }

  /// Checks whether a file is an OpenAPI/Swagger spec.
  bool _isSpecFile(String path) {
    final lowerPath = path.toLowerCase();
    return (lowerPath.contains('swagger') ||
            lowerPath.contains('openapi') ||
            lowerPath.contains('api')) &&
        (path.endsWith('.yaml') ||
            path.endsWith('.yml') ||
            path.endsWith('.json'));
  }

  /// Checks whether the content is a Swagger/OpenAPI spec.
  bool _isSwaggerOrOpenApiSpec(Map<String, dynamic> spec) {
    return spec.containsKey('swagger') ||
        spec.containsKey('openapi') ||
        (spec.containsKey('info') &&
            (spec.containsKey('paths') ||
                spec.containsKey('definitions') ||
                spec.containsKey('components')));
  }

  /// Finds the project root directory.
  Future<String> _findProjectRoot(BuildStep buildStep) async {
    // Look for pubspec.yaml up the directory tree
    var current = p.dirname(buildStep.inputId.path);
    var package = buildStep.inputId.package;

    while (current.isNotEmpty &&
        current != '.' &&
        current != p.rootPrefix(current)) {
      final pubspecId = AssetId(package, p.join(current, 'pubspec.yaml'));
      if (await buildStep.canRead(pubspecId)) {
        // For build_runner we need to return a path relative to the package
        return current.isEmpty ? '.' : current;
      }
      final parent = p.dirname(current);
      if (parent == current || parent.isEmpty) break;
      current = parent;
    }
    return '.';
  }
}

/// Builder factory for registration in build.yaml.
Builder swaggerBuilder(BuilderOptions options) => SwaggerBuilder();
