import 'dart:convert';
import 'dart:io';

import 'package:dart_swagger_to_models/dart_swagger_to_models.dart';
import 'package:dart_swagger_to_models/src/core/logger.dart';
import 'package:test/test.dart';

void main() {
  group('Incremental generation (0.5.1)', () {
    test('generates all schemas on first run', () async {
      final tempDir = await Directory.systemTemp
          .createTemp('dart_swagger_to_models_cache_');
      final specFile = File('${tempDir.path}/openapi.json');

      final spec = <String, dynamic>{
        'openapi': '3.0.0',
        'info': {'title': 'Test', 'version': '1.0.0'},
        'paths': <String, dynamic>{},
        'components': {
          'schemas': {
            'User': {
              'type': 'object',
              'properties': {
                'id': {'type': 'integer'},
                'name': {'type': 'string'},
              },
            },
            'Product': {
              'type': 'object',
              'properties': {
                'id': {'type': 'integer'},
                'title': {'type': 'string'},
              },
            },
          },
        },
      };

      await specFile.writeAsString(jsonEncode(spec));

      final result = await SwaggerToDartGenerator.generateModels(
        input: specFile.path,
        outputDir: '${tempDir.path}/models',
        projectDir: tempDir.path,
        changedOnly: true,
      );

      expect(result.schemasProcessed, equals(2));
      expect(result.generatedFiles.length, equals(2));

      final cacheFile = File('${tempDir.path}/.dart_swagger_to_models.cache');
      expect(await cacheFile.exists(), isTrue);
    });

    test('generates only changed schemas on second run', () async {
      final tempDir = await Directory.systemTemp
          .createTemp('dart_swagger_to_models_cache2_');
      final specFile = File('${tempDir.path}/openapi.json');

      final spec1 = <String, dynamic>{
        'openapi': '3.0.0',
        'info': {'title': 'Test', 'version': '1.0.0'},
        'paths': <String, dynamic>{},
        'components': {
          'schemas': {
            'User': {
              'type': 'object',
              'properties': {
                'id': {'type': 'integer'},
                'name': {'type': 'string'},
              },
            },
            'Product': {
              'type': 'object',
              'properties': {
                'id': {'type': 'integer'},
                'title': {'type': 'string'},
              },
            },
          },
        },
      };

      await specFile.writeAsString(jsonEncode(spec1));

      final result1 = await SwaggerToDartGenerator.generateModels(
        input: specFile.path,
        outputDir: '${tempDir.path}/models',
        projectDir: tempDir.path,
        changedOnly: true,
      );

      expect(result1.schemasProcessed, equals(2));

      final spec2 = <String, dynamic>{
        'openapi': '3.0.0',
        'info': {'title': 'Test', 'version': '1.0.0'},
        'paths': <String, dynamic>{},
        'components': {
          'schemas': {
            'User': {
              'type': 'object',
              'properties': {
                'id': {'type': 'integer'},
                'name': {'type': 'string'},
                'email': {'type': 'string'},
              },
            },
            'Product': {
              'type': 'object',
              'properties': {
                'id': {'type': 'integer'},
                'title': {'type': 'string'},
              },
            },
          },
        },
      };

      await specFile.writeAsString(jsonEncode(spec2));

      Logger.clear();
      final result2 = await SwaggerToDartGenerator.generateModels(
        input: specFile.path,
        outputDir: '${tempDir.path}/models',
        projectDir: tempDir.path,
        changedOnly: true,
      );

      expect(result2.schemasProcessed, equals(1));

      final userFile =
          result2.generatedFiles.firstWhere((f) => f.contains('user.dart'));
      final userContent = await File(userFile).readAsString();
      expect(userContent, contains('final String email;'));
    });

    test('deletes files for removed schemas', () async {
      final tempDir = await Directory.systemTemp
          .createTemp('dart_swagger_to_models_cache3_');
      final specFile = File('${tempDir.path}/openapi.json');

      final spec1 = <String, dynamic>{
        'openapi': '3.0.0',
        'info': {'title': 'Test', 'version': '1.0.0'},
        'paths': <String, dynamic>{},
        'components': {
          'schemas': {
            'User': {
              'type': 'object',
              'properties': {
                'id': {'type': 'integer'},
                'name': {'type': 'string'},
              },
            },
            'Product': {
              'type': 'object',
              'properties': {
                'id': {'type': 'integer'},
                'title': {'type': 'string'},
              },
            },
          },
        },
      };

      await specFile.writeAsString(jsonEncode(spec1));

      await SwaggerToDartGenerator.generateModels(
        input: specFile.path,
        outputDir: '${tempDir.path}/models',
        projectDir: tempDir.path,
        changedOnly: true,
      );

      final userFile = File('${tempDir.path}/models/user.dart');
      final productFile = File('${tempDir.path}/models/product.dart');
      expect(await userFile.exists(), isTrue);
      expect(await productFile.exists(), isTrue);

      final spec2 = <String, dynamic>{
        'openapi': '3.0.0',
        'info': {'title': 'Test', 'version': '1.0.0'},
        'paths': <String, dynamic>{},
        'components': {
          'schemas': {
            'User': {
              'type': 'object',
              'properties': {
                'id': {'type': 'integer'},
                'name': {'type': 'string'},
              },
            },
          },
        },
      };

      await specFile.writeAsString(jsonEncode(spec2));

      await SwaggerToDartGenerator.generateModels(
        input: specFile.path,
        outputDir: '${tempDir.path}/models',
        projectDir: tempDir.path,
        changedOnly: true,
      );

      expect(await productFile.exists(), isFalse);
      expect(await userFile.exists(), isTrue);
    });

    test('adds new schemas during incremental generation', () async {
      final tempDir = await Directory.systemTemp
          .createTemp('dart_swagger_to_models_cache4_');
      final specFile = File('${tempDir.path}/openapi.json');

      final spec1 = <String, dynamic>{
        'openapi': '3.0.0',
        'info': {'title': 'Test', 'version': '1.0.0'},
        'paths': <String, dynamic>{},
        'components': {
          'schemas': {
            'User': {
              'type': 'object',
              'properties': {
                'id': {'type': 'integer'},
                'name': {'type': 'string'},
              },
            },
          },
        },
      };

      await specFile.writeAsString(jsonEncode(spec1));

      await SwaggerToDartGenerator.generateModels(
        input: specFile.path,
        outputDir: '${tempDir.path}/models',
        projectDir: tempDir.path,
        changedOnly: true,
      );

      final spec2 = <String, dynamic>{
        'openapi': '3.0.0',
        'info': {'title': 'Test', 'version': '1.0.0'},
        'paths': <String, dynamic>{},
        'components': {
          'schemas': {
            'User': {
              'type': 'object',
              'properties': {
                'id': {'type': 'integer'},
                'name': {'type': 'string'},
              },
            },
            'Product': {
              'type': 'object',
              'properties': {
                'id': {'type': 'integer'},
                'title': {'type': 'string'},
              },
            },
          },
        },
      };

      await specFile.writeAsString(jsonEncode(spec2));

      final result = await SwaggerToDartGenerator.generateModels(
        input: specFile.path,
        outputDir: '${tempDir.path}/models',
        projectDir: tempDir.path,
        changedOnly: true,
      );

      expect(result.schemasProcessed, equals(1));

      final productFile = File('${tempDir.path}/models/product.dart');
      expect(await productFile.exists(), isTrue);
    });

    test('works without cache (first run)', () async {
      final tempDir = await Directory.systemTemp
          .createTemp('dart_swagger_to_models_cache5_');
      final specFile = File('${tempDir.path}/openapi.json');

      final spec = <String, dynamic>{
        'openapi': '3.0.0',
        'info': {'title': 'Test', 'version': '1.0.0'},
        'paths': <String, dynamic>{},
        'components': {
          'schemas': {
            'User': {
              'type': 'object',
              'properties': {
                'id': {'type': 'integer'},
                'name': {'type': 'string'},
              },
            },
          },
        },
      };

      await specFile.writeAsString(jsonEncode(spec));

      final result = await SwaggerToDartGenerator.generateModels(
        input: specFile.path,
        outputDir: '${tempDir.path}/models',
        projectDir: tempDir.path,
        changedOnly: true,
      );

      expect(result.schemasProcessed, equals(1));
      expect(result.generatedFiles.length, equals(1));
    });
  });
}
