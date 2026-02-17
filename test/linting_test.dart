import 'dart:convert';
import 'dart:io';

import 'package:dart_swagger_to_models/dart_swagger_to_models.dart';
import 'package:dart_swagger_to_models/src/config/config_loader.dart';
import 'package:dart_swagger_to_models/src/core/logger.dart';
import 'package:test/test.dart';

void main() {
  group('Spec quality hints (spec linting)', () {
    test('lint rules work by default', () async {
      final tempDir =
          await Directory.systemTemp.createTemp('dart_swagger_to_models_lint_');
      final specFile = File('${tempDir.path}/swagger.json');

      final spec = <String, dynamic>{
        'swagger': '2.0',
        'info': {'title': 'Test', 'version': '1.0.0'},
        'paths': <String, dynamic>{},
        'definitions': <String, dynamic>{
          'User': {
            'type': 'object',
            'properties': <String, dynamic>{
              'name': <String, dynamic>{},
              'id': {'type': 'integer'},
            },
          },
        },
      };

      await specFile.writeAsString(jsonEncode(spec));

      await SwaggerToDartGenerator.generateModels(
        input: specFile.path,
        outputDir: '${tempDir.path}/models',
        projectDir: tempDir.path,
      );

      expect(Logger.warnings.length, greaterThan(0));
    });

    test('lint rules can be disabled via config', () async {
      final tempDir = await Directory.systemTemp
          .createTemp('dart_swagger_to_models_lint_disabled_');
      final configFile = File('${tempDir.path}/dart_swagger_to_models.yaml');
      final specFile = File('${tempDir.path}/swagger.json');

      await configFile.writeAsString('''
lint:
  enabled: false
''');

      final spec = <String, dynamic>{
        'swagger': '2.0',
        'info': {'title': 'Test', 'version': '1.0.0'},
        'paths': <String, dynamic>{},
        'definitions': <String, dynamic>{
          'User': {
            'type': 'object',
            'properties': <String, dynamic>{
              'name': <String, dynamic>{},
            },
          },
        },
      };

      await specFile.writeAsString(jsonEncode(spec));

      Logger.clear();
      await SwaggerToDartGenerator.generateModels(
        input: specFile.path,
        outputDir: '${tempDir.path}/models',
        projectDir: tempDir.path,
        config: await ConfigLoader.loadConfig(null, tempDir.path),
      );

      expect(Logger.warnings.length, 0);
    });

    test('lint rules can be configured individually', () async {
      final tempDir = await Directory.systemTemp
          .createTemp('dart_swagger_to_models_lint_custom_');
      final configFile = File('${tempDir.path}/dart_swagger_to_models.yaml');
      final specFile = File('${tempDir.path}/swagger.json');

      await configFile.writeAsString('''
lint:
  rules:
    missing_type: error
    suspicious_id_field: off
''');

      final spec = <String, dynamic>{
        'swagger': '2.0',
        'info': {'title': 'Test', 'version': '1.0.0'},
        'paths': <String, dynamic>{},
        'definitions': <String, dynamic>{
          'User': {
            'type': 'object',
            'properties': <String, dynamic>{
              'name': <String, dynamic>{},
              'id': {'type': 'integer'},
            },
          },
        },
      };

      await specFile.writeAsString(jsonEncode(spec));

      Logger.clear();
      await SwaggerToDartGenerator.generateModels(
        input: specFile.path,
        outputDir: '${tempDir.path}/models',
        projectDir: tempDir.path,
        config: await ConfigLoader.loadConfig(null, tempDir.path),
      );

      expect(Logger.errors.length, greaterThan(0));
      expect(Logger.errors.any((e) => e.contains('has no type')), isTrue);
      expect(Logger.warnings.any((w) => w.contains('identifier')), isFalse);
    });

    test('empty object check', () async {
      final tempDir = await Directory.systemTemp
          .createTemp('dart_swagger_to_models_lint_empty_');
      final specFile = File('${tempDir.path}/swagger.json');

      final spec = <String, dynamic>{
        'swagger': '2.0',
        'info': {'title': 'Test', 'version': '1.0.0'},
        'paths': <String, dynamic>{},
        'definitions': <String, dynamic>{
          'EmptySchema': {
            'type': 'object',
            'properties': <String, dynamic>{},
          },
        },
      };

      await specFile.writeAsString(jsonEncode(spec));

      Logger.clear();
      await SwaggerToDartGenerator.generateModels(
        input: specFile.path,
        outputDir: '${tempDir.path}/models',
        projectDir: tempDir.path,
      );

      expect(Logger.warnings.any((w) => w.contains('empty object')), isTrue);
    });

    test('array without items check', () async {
      final tempDir = await Directory.systemTemp
          .createTemp('dart_swagger_to_models_lint_array_');
      final specFile = File('${tempDir.path}/swagger.json');

      final spec = <String, dynamic>{
        'swagger': '2.0',
        'info': {'title': 'Test', 'version': '1.0.0'},
        'paths': <String, dynamic>{},
        'definitions': <String, dynamic>{
          'User': {
            'type': 'object',
            'properties': {
              'tags': {
                'type': 'array',
              },
            },
          },
        },
      };

      await specFile.writeAsString(jsonEncode(spec));

      Logger.clear();
      await SwaggerToDartGenerator.generateModels(
        input: specFile.path,
        outputDir: '${tempDir.path}/models',
        projectDir: tempDir.path,
      );

      expect(
          Logger.warnings
              .any((w) => w.contains('array') && w.contains('items')),
          isTrue);
    });

    test('empty enum check', () async {
      final tempDir = await Directory.systemTemp
          .createTemp('dart_swagger_to_models_lint_empty_enum_');
      final specFile = File('${tempDir.path}/swagger.json');

      final spec = <String, dynamic>{
        'swagger': '2.0',
        'info': {'title': 'Test', 'version': '1.0.0'},
        'paths': <String, dynamic>{},
        'definitions': <String, dynamic>{
          'EmptyEnum': {
            'type': 'string',
            'enum': <String>[],
          },
        },
      };

      await specFile.writeAsString(jsonEncode(spec));

      Logger.clear();
      await SwaggerToDartGenerator.generateModels(
        input: specFile.path,
        outputDir: '${tempDir.path}/models',
        projectDir: tempDir.path,
      );

      expect(
          Logger.warnings.any(
              (w) => w.contains('Enum') && w.contains('contains no values')),
          isTrue);
    });

    test('type inconsistency check', () async {
      final tempDir = await Directory.systemTemp
          .createTemp('dart_swagger_to_models_lint_inconsistency_');
      final specFile = File('${tempDir.path}/swagger.json');

      final spec = <String, dynamic>{
        'swagger': '2.0',
        'info': {'title': 'Test', 'version': '1.0.0'},
        'paths': <String, dynamic>{},
        'definitions': <String, dynamic>{
          'User': {
            'type': 'object',
            'properties': {
              'count': {
                'type': 'integer',
                'format': 'date-time',
              },
            },
          },
        },
      };

      await specFile.writeAsString(jsonEncode(spec));

      Logger.clear();
      await SwaggerToDartGenerator.generateModels(
        input: specFile.path,
        outputDir: '${tempDir.path}/models',
        projectDir: tempDir.path,
      );

      expect(
          Logger.warnings
              .any((w) => w.contains('integer') && w.contains('format')),
          isTrue);
    });
  });
}
