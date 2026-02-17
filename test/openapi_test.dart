import 'dart:convert';
import 'dart:io';

import 'package:dart_swagger_to_models/dart_swagger_to_models.dart';
import 'package:dart_swagger_to_models/src/core/logger.dart';
import 'package:test/test.dart';

void main() {
  group('Improved OpenAPI support (0.2.1)', () {
    test('handles nested allOf combinations', () async {
      final tempDir = await Directory.systemTemp
          .createTemp('dart_swagger_to_models_nested_allof_');
      final specFile = File('${tempDir.path}/openapi.json');

      final spec = <String, dynamic>{
        'openapi': '3.0.0',
        'info': {'title': 'Test', 'version': '1.0.0'},
        'paths': <String, dynamic>{},
        'components': {
          'schemas': {
            'Base': {
              'type': 'object',
              'properties': {
                'id': {'type': 'integer'},
              },
            },
            'Timestamped': {
              'allOf': [
                {'\$ref': '#/components/schemas/Base'},
                {
                  'type': 'object',
                  'properties': {
                    'createdAt': {'type': 'string', 'format': 'date-time'},
                  },
                },
              ],
            },
            'User': {
              'allOf': [
                {'\$ref': '#/components/schemas/Timestamped'},
                {
                  'type': 'object',
                  'properties': {
                    'name': {'type': 'string'},
                  },
                },
              ],
            },
          },
        },
      };

      await specFile.writeAsString(jsonEncode(spec));

      final result = await SwaggerToDartGenerator.generateModels(
        input: specFile.path,
        outputDir: '${tempDir.path}/models',
        projectDir: tempDir.path,
      );

      final userFile =
          result.generatedFiles.firstWhere((f) => f.contains('user.dart'));
      final content = await File(userFile).readAsString();

      expect(content, contains('class User'));
      expect(content, contains('final int id;'));
      expect(content, contains('final DateTime createdAt;'));
      expect(content, contains('final String name;'));
    });

    test('handles multiple inheritance through allOf', () async {
      final tempDir = await Directory.systemTemp
          .createTemp('dart_swagger_to_models_multiple_allof_');
      final specFile = File('${tempDir.path}/openapi.json');

      final spec = <String, dynamic>{
        'openapi': '3.0.0',
        'info': {'title': 'Test', 'version': '1.0.0'},
        'paths': <String, dynamic>{},
        'components': {
          'schemas': {
            'Identifiable': {
              'type': 'object',
              'required': ['id'],
              'properties': {
                'id': {'type': 'integer'},
              },
            },
            'Named': {
              'type': 'object',
              'required': ['name'],
              'properties': {
                'name': {'type': 'string'},
              },
            },
            'Timestamped': {
              'type': 'object',
              'properties': {
                'createdAt': {'type': 'string', 'format': 'date-time'},
              },
            },
            'Product': {
              'allOf': [
                {'\$ref': '#/components/schemas/Identifiable'},
                {'\$ref': '#/components/schemas/Named'},
                {'\$ref': '#/components/schemas/Timestamped'},
                {
                  'type': 'object',
                  'properties': {
                    'price': {'type': 'number'},
                  },
                },
              ],
            },
          },
        },
      };

      await specFile.writeAsString(jsonEncode(spec));

      final result = await SwaggerToDartGenerator.generateModels(
        input: specFile.path,
        outputDir: '${tempDir.path}/models',
        projectDir: tempDir.path,
      );

      final productFile =
          result.generatedFiles.firstWhere((f) => f.contains('product.dart'));
      final content = await File(productFile).readAsString();

      expect(content, contains('class Product'));
      expect(content, contains('final int id;'));
      expect(content, contains('final String name;'));
      expect(content, contains('final DateTime createdAt;'));
      expect(content, contains('final num price;'));
    });

    test('generates safe wrapper for oneOf without discriminator', () async {
      final tempDir = await Directory.systemTemp
          .createTemp('dart_swagger_to_models_oneof_');
      final specFile = File('${tempDir.path}/openapi.json');

      final spec = <String, dynamic>{
        'openapi': '3.0.0',
        'info': {'title': 'Test', 'version': '1.0.0'},
        'paths': <String, dynamic>{},
        'components': {
          'schemas': {
            'StringValue': {
              'type': 'object',
              'properties': {
                'value': {'type': 'string'},
              },
            },
            'NumberValue': {
              'type': 'object',
              'properties': {
                'value': {'type': 'number'},
              },
            },
            'Value': {
              'oneOf': [
                {'\$ref': '#/components/schemas/StringValue'},
                {'\$ref': '#/components/schemas/NumberValue'},
              ],
            },
          },
        },
      };

      await specFile.writeAsString(jsonEncode(spec));

      Logger.clear();
      final result = await SwaggerToDartGenerator.generateModels(
        input: specFile.path,
        outputDir: '${tempDir.path}/models',
        projectDir: tempDir.path,
      );

      final valueFiles =
          result.generatedFiles.where((f) => f.endsWith('value.dart')).toList();
      expect(valueFiles, isNotEmpty,
          reason: 'Should generate file for Value schema');

      File? valueFile;
      for (final filePath in valueFiles) {
        final content = await File(filePath).readAsString();
        if (content.contains('class Value') &&
            content.contains('final dynamic value;')) {
          valueFile = File(filePath);
          break;
        }
      }

      expect(valueFile, isNotNull,
          reason: 'Should find file with Value class (oneOf)');
      final content = await valueFile!.readAsString();

      expect(content, contains('class Value'));
      expect(content, contains('final dynamic value;'));
      expect(content, contains('factory Value.fromJson(dynamic json)'));
      expect(content, contains('dynamic toJson() => value;'));
      expect(
          Logger.warnings
              .any((w) => w.contains('oneOf') || w.contains('anyOf')),
          isFalse);
    });

    test('generates safe wrapper for anyOf without discriminator', () async {
      final tempDir = await Directory.systemTemp
          .createTemp('dart_swagger_to_models_anyof_');
      final specFile = File('${tempDir.path}/openapi.json');

      final spec = <String, dynamic>{
        'openapi': '3.0.0',
        'info': {'title': 'Test', 'version': '1.0.0'},
        'paths': <String, dynamic>{},
        'components': {
          'schemas': {
            'StringMessage': {
              'type': 'object',
              'properties': {
                'message': {'type': 'string'},
              },
            },
            'Error': {
              'anyOf': [
                {'\$ref': '#/components/schemas/StringMessage'},
                {'type': 'string'},
              ],
            },
          },
        },
      };

      await specFile.writeAsString(jsonEncode(spec));

      Logger.clear();
      final result = await SwaggerToDartGenerator.generateModels(
        input: specFile.path,
        outputDir: '${tempDir.path}/models',
        projectDir: tempDir.path,
      );

      final errorFile =
          result.generatedFiles.firstWhere((f) => f.contains('error.dart'));
      final content = await File(errorFile).readAsString();

      expect(content, contains('class Error'));
      expect(content, contains('final dynamic value;'));
      expect(content, contains('factory Error.fromJson(dynamic json)'));
    });

    test('generates union type for oneOf with discriminator', () async {
      final tempDir = await Directory.systemTemp
          .createTemp('dart_swagger_to_models_oneof_discriminator_');
      final specFile = File('${tempDir.path}/openapi.json');

      final spec = <String, dynamic>{
        'openapi': '3.0.0',
        'info': {'title': 'Test', 'version': '1.0.0'},
        'paths': <String, dynamic>{},
        'components': {
          'schemas': {
            'Cat': {
              'type': 'object',
              'properties': {
                'type': {
                  'type': 'string',
                  'enum': ['cat']
                },
                'meow': {'type': 'boolean'},
              },
            },
            'Dog': {
              'type': 'object',
              'properties': {
                'type': {
                  'type': 'string',
                  'enum': ['dog']
                },
                'bark': {'type': 'boolean'},
              },
            },
            'Pet': {
              'oneOf': [
                {'\$ref': '#/components/schemas/Cat'},
                {'\$ref': '#/components/schemas/Dog'},
              ],
              'discriminator': {
                'propertyName': 'type',
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
      );

      final petFile =
          result.generatedFiles.firstWhere((f) => f.contains('pet.dart'));
      final content = await File(petFile).readAsString();

      // Should generate union-style class with discriminator-based union
      expect(content, contains('class Pet'));
      expect(content, contains('final String type;'));
      expect(content, contains('final Cat? cat;'));
      expect(content, contains('final Dog? dog;'));
      expect(content, contains('const Pet._({'));
      expect(content, contains('factory Pet.fromCat(Cat value)'));
      expect(content, contains('factory Pet.fromDog(Dog value)'));
      expect(content, contains('factory Pet.fromJson(Map<String, dynamic> json)'));
      expect(content, contains('Map<String, dynamic> toJson()'));
      expect(content, contains('T when<T>({'));
    });

    test('handles circular dependencies in allOf', () async {
      final tempDir = await Directory.systemTemp
          .createTemp('dart_swagger_to_models_allof_cycle_');
      final specFile = File('${tempDir.path}/openapi.json');

      final spec = <String, dynamic>{
        'openapi': '3.0.0',
        'info': {'title': 'Test', 'version': '1.0.0'},
        'paths': <String, dynamic>{},
        'components': {
          'schemas': {
            'Base': {
              'type': 'object',
              'required': ['id'],
              'properties': {
                'id': {'type': 'integer'},
              },
            },
            'Extended': {
              'allOf': [
                {'\$ref': '#/components/schemas/Base'},
                {
                  'type': 'object',
                  'properties': {
                    'name': {'type': 'string'},
                  },
                },
              ],
            },
            'Final': {
              'allOf': [
                {'\$ref': '#/components/schemas/Extended'},
                {'\$ref': '#/components/schemas/Base'},
                {
                  'type': 'object',
                  'properties': {
                    'extra': {'type': 'string'},
                  },
                },
              ],
            },
          },
        },
      };

      await specFile.writeAsString(jsonEncode(spec));

      Logger.clear();
      final result = await SwaggerToDartGenerator.generateModels(
        input: specFile.path,
        outputDir: '${tempDir.path}/models',
        projectDir: tempDir.path,
      );

      final finalFile =
          result.generatedFiles.firstWhere((f) => f.contains('final.dart'));
      final content = await File(finalFile).readAsString();

      expect(content, contains('class Final'));
      expect(content, contains('final int id;'));
      expect(content, contains('final String name;'));
      expect(content, contains('final String extra;'));
    });
  });
}
