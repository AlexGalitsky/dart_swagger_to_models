import 'dart:convert';
import 'dart:io';

import 'package:dart_swagger_to_models/dart_swagger_to_models.dart';
import 'package:test/test.dart';

void main() {
  group('SwaggerToDartGenerator', () {
    test('генерирует Dart-модели из простого Swagger 2.0', () async {
      final tempDir = await Directory.systemTemp.createTemp('dart_swagger_to_models_test_');
      final specFile = File('${tempDir.path}/swagger.json');

      final spec = <String, dynamic>{
        'swagger': '2.0',
        'info': {
          'title': 'Test API',
          'version': '1.0.0',
        },
        'paths': <String, dynamic>{},
        'definitions': <String, dynamic>{
          'User': {
            'type': 'object',
            'required': ['id', 'name'],
            'properties': {
              'id': {'type': 'integer'},
              'name': {'type': 'string'},
              'email': {'type': 'string'},
            },
          },
        },
      };

      await specFile.writeAsString(jsonEncode(spec));

      final result = await SwaggerToDartGenerator.generateModels(
        input: specFile.path,
        outputDir: '${tempDir.path}/models',
        libraryName: 'api_models',
      );

      expect(result.generatedFiles, hasLength(1));
      final generated = File(result.generatedFiles.first);
      expect(await generated.exists(), isTrue);

      final content = await generated.readAsString();
      expect(content, contains('class User'));
      expect(content, contains('final int id;'));
      expect(content, contains('final String name;'));
      expect(content, contains('final String? email;'));
      expect(content, contains('factory User.fromJson'));
      expect(content, contains('Map<String, dynamic> toJson()'));
    });

    test('генерирует enum для строковых типов с enum значениями', () async {
      final tempDir = await Directory.systemTemp.createTemp('dart_swagger_to_models_test_');
      final specFile = File('${tempDir.path}/swagger.json');

      final spec = <String, dynamic>{
        'swagger': '2.0',
        'info': {
          'title': 'Test API',
          'version': '1.0.0',
        },
        'paths': <String, dynamic>{},
        'definitions': <String, dynamic>{
          'Status': {
            'type': 'string',
            'enum': ['active', 'inactive', 'pending'],
          },
          'User': {
            'type': 'object',
            'properties': {
              'status': {'\$ref': '#/definitions/Status'},
            },
          },
        },
      };

      await specFile.writeAsString(jsonEncode(spec));

      final result = await SwaggerToDartGenerator.generateModels(
        input: specFile.path,
        outputDir: '${tempDir.path}/models',
        libraryName: 'api_models',
      );

      final content = await File(result.generatedFiles.first).readAsString();
      expect(content, contains('enum Status'));
      expect(content, contains('active'));
      expect(content, contains('inactive'));
      expect(content, contains('pending'));
      expect(content, contains('Status.fromJson'));
      expect(content, contains('status?.toJson()'));
    });

    test('поддерживает OpenAPI 3.0 с nullable полями', () async {
      final tempDir = await Directory.systemTemp.createTemp('dart_swagger_to_models_test_');
      final specFile = File('${tempDir.path}/openapi.json');

      final spec = <String, dynamic>{
        'openapi': '3.0.0',
        'info': {
          'title': 'Test API',
          'version': '1.0.0',
        },
        'paths': <String, dynamic>{},
        'components': {
          'schemas': {
            'Product': {
              'type': 'object',
              'required': ['id'],
              'properties': {
                'id': {'type': 'integer', 'format': 'int64'},
                'name': {'type': 'string'},
                'description': {'type': 'string', 'nullable': true},
                'price': {'type': 'number'},
              },
            },
          },
        },
      };

      await specFile.writeAsString(jsonEncode(spec));

      final result = await SwaggerToDartGenerator.generateModels(
        input: specFile.path,
        outputDir: '${tempDir.path}/models',
        libraryName: 'api_models',
      );

      final content = await File(result.generatedFiles.first).readAsString();
      expect(content, contains('class Product'));
      expect(content, contains('final int id;'));
      expect(content, contains('final String? name;'));
      expect(content, contains('final String? description;'));
      expect(content, contains('final num? price;'));
    });

    test('поддерживает allOf (OpenAPI 3)', () async {
      final tempDir = await Directory.systemTemp.createTemp('dart_swagger_to_models_test_');
      final specFile = File('${tempDir.path}/openapi.json');

      final spec = <String, dynamic>{
        'openapi': '3.0.0',
        'info': {
          'title': 'Test API',
          'version': '1.0.0',
        },
        'paths': <String, dynamic>{},
        'components': {
          'schemas': {
            'BaseEntity': {
              'type': 'object',
              'required': ['id'],
              'properties': {
                'id': {'type': 'integer'},
                'createdAt': {'type': 'string', 'format': 'date-time'},
              },
            },
            'User': {
              'allOf': [
                {'\$ref': '#/components/schemas/BaseEntity'},
                {
                  'type': 'object',
                  'properties': {
                    'name': {'type': 'string'},
                    'email': {'type': 'string'},
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
        libraryName: 'api_models',
      );

      final content = await File(result.generatedFiles.first).readAsString();
      expect(content, contains('class User'));
      expect(content, contains('final int id;'));
      expect(content, contains('final DateTime? createdAt;'));
      expect(content, contains('final String? name;'));
      expect(content, contains('final String? email;'));
    });

    test('поддерживает массивы с вложенными типами', () async {
      final tempDir = await Directory.systemTemp.createTemp('dart_swagger_to_models_test_');
      final specFile = File('${tempDir.path}/swagger.json');

      final spec = <String, dynamic>{
        'swagger': '2.0',
        'info': {
          'title': 'Test API',
          'version': '1.0.0',
        },
        'paths': <String, dynamic>{},
        'definitions': <String, dynamic>{
          'User': {
            'type': 'object',
            'properties': {
              'id': {'type': 'integer'},
              'tags': {
                'type': 'array',
                'items': {'type': 'string'},
              },
            },
          },
        },
      };

      await specFile.writeAsString(jsonEncode(spec));

      final result = await SwaggerToDartGenerator.generateModels(
        input: specFile.path,
        outputDir: '${tempDir.path}/models',
        libraryName: 'api_models',
      );

      final content = await File(result.generatedFiles.first).readAsString();
      expect(content, contains('final List<String>? tags;'));
      expect(content, contains('List<dynamic>'));
    });

    test('поддерживает additionalProperties', () async {
      final tempDir = await Directory.systemTemp.createTemp('dart_swagger_to_models_test_');
      final specFile = File('${tempDir.path}/openapi.json');

      final spec = <String, dynamic>{
        'openapi': '3.0.0',
        'info': {
          'title': 'Test API',
          'version': '1.0.0',
        },
        'paths': <String, dynamic>{},
        'components': {
          'schemas': {
            'Response': {
              'type': 'object',
              'properties': {
                'metadata': {
                  'type': 'object',
                  'additionalProperties': {
                    'type': 'string',
                  },
                },
              },
            },
          },
        },
      };

      await specFile.writeAsString(jsonEncode(spec));

      final result = await SwaggerToDartGenerator.generateModels(
        input: specFile.path,
        outputDir: '${tempDir.path}/models',
        libraryName: 'api_models',
      );

      final content = await File(result.generatedFiles.first).readAsString();
      expect(content, contains('class Response'));
      expect(content, contains('Map<String, String>'));
    });

    test('различает int и num', () async {
      final tempDir = await Directory.systemTemp.createTemp('dart_swagger_to_models_test_');
      final specFile = File('${tempDir.path}/swagger.json');

      final spec = <String, dynamic>{
        'swagger': '2.0',
        'info': {
          'title': 'Test API',
          'version': '1.0.0',
        },
        'paths': <String, dynamic>{},
        'definitions': <String, dynamic>{
          'Numbers': {
            'type': 'object',
            'properties': {
              'count': {'type': 'integer'},
              'price': {'type': 'number'},
            },
          },
        },
      };

      await specFile.writeAsString(jsonEncode(spec));

      final result = await SwaggerToDartGenerator.generateModels(
        input: specFile.path,
        outputDir: '${tempDir.path}/models',
        libraryName: 'api_models',
      );

      final content = await File(result.generatedFiles.first).readAsString();
      expect(content, contains('final int? count;'));
      expect(content, contains('final num? price;'));
    });
  });
}
