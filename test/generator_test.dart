import 'dart:convert';
import 'dart:io';

import 'package:dart_swagger_to_models/dart_swagger_to_models.dart';
import 'package:test/test.dart';

void main() {
  group('SwaggerToDartGenerator', () {
    test('generates Dart models from simple Swagger 2.0', () async {
      final tempDir =
          await Directory.systemTemp.createTemp('dart_swagger_to_models_test_');
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
      expect(content, contains('final String email;'));
      expect(content, contains('factory User.fromJson'));
      expect(content, contains('Map<String, dynamic> toJson()'));
    });

    test('generates enum for string types with enum values', () async {
      final tempDir =
          await Directory.systemTemp.createTemp('dart_swagger_to_models_test_');
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
        projectDir: tempDir.path,
      );

      final statusFile =
          result.generatedFiles.firstWhere((f) => f.contains('status.dart'));
      final content = await File(statusFile).readAsString();
      expect(content, contains('enum Status'));
      expect(content, contains('active'));
      expect(content, contains('inactive'));
      expect(content, contains('pending'));
      expect(content, contains('Status? fromJson'));
      expect(content, contains('dynamic toJson() => value;'));
    });

    test('supports OpenAPI 3.0 with nullable fields', () async {
      final tempDir =
          await Directory.systemTemp.createTemp('dart_swagger_to_models_test_');
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
        projectDir: tempDir.path,
      );

      final productFile =
          result.generatedFiles.firstWhere((f) => f.contains('product.dart'));
      final content = await File(productFile).readAsString();
      expect(content, contains('class Product'));
      expect(content, contains('final int id;'));
      expect(content, contains('final String name;'));
      expect(content, contains('final String? description;'));
      expect(content, contains('final num price;'));
    });

    test('supports allOf (OpenAPI 3)', () async {
      final tempDir =
          await Directory.systemTemp.createTemp('dart_swagger_to_models_test_');
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
        projectDir: tempDir.path,
      );

      final baseFile = result.generatedFiles
          .firstWhere((f) => f.contains('base_entity.dart'));
      final userFile =
          result.generatedFiles.firstWhere((f) => f.contains('user.dart'));

      final baseContent = await File(baseFile).readAsString();
      final userContent = await File(userFile).readAsString();

      expect(baseContent, contains('class BaseEntity'));
      expect(baseContent, contains('final int id;'));
      expect(baseContent, contains('final DateTime createdAt;'));

      expect(userContent, contains('class User'));
      expect(userContent, contains('final String name;'));
      expect(userContent, contains('final String email;'));
    });

    test('supports arrays with nested types', () async {
      final tempDir =
          await Directory.systemTemp.createTemp('dart_swagger_to_models_test_');
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
        projectDir: tempDir.path,
      );

      final userFile =
          result.generatedFiles.firstWhere((f) => f.contains('user.dart'));
      final content = await File(userFile).readAsString();
      expect(content, contains('final List<String> tags;'));
      expect(content, contains('List<dynamic>'));
    });

    test('supports additionalProperties', () async {
      final tempDir =
          await Directory.systemTemp.createTemp('dart_swagger_to_models_test_');
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

    test('generates DartDoc from schema descriptions', () async {
      final tempDir =
          await Directory.systemTemp.createTemp('dart_swagger_to_models_docs_');
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
            'UserStatus': {
              'type': 'string',
              'description': 'Status of the user.',
              'enum': ['active', 'inactive'],
            },
            'User': {
              'type': 'object',
              'description': 'User model used in tests.',
              'properties': {
                'id': {
                  'type': 'integer',
                  'description': 'Unique identifier of the user.',
                },
                'name': {
                  'type': 'string',
                  'description': 'Display name of the user.',
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
        projectDir: tempDir.path,
      );

      final userStatusFile =
          result.generatedFiles.firstWhere((f) => f.contains('user_status.dart'));
      final userFile =
          result.generatedFiles.firstWhere((f) => f.contains('user.dart'));

      final enumContent = await File(userStatusFile).readAsString();
      final userContent = await File(userFile).readAsString();

      // Enum-level docs
      expect(enumContent, contains('/// Status of the user.'));
      expect(enumContent, contains('enum UserStatus'));

      // Class-level docs
      expect(userContent, contains('/// User model used in tests.'));
      expect(userContent, contains('class User'));

      // Field-level docs (id and name)
      expect(userContent,
          contains('/// Unique identifier of the user.\n  final int id;'));
      expect(userContent,
          contains('/// Display name of the user.\n  final String name;'));
    });

    test('generates simple validation extension from schema constraints',
        () async {
      final tempDir = await Directory.systemTemp
          .createTemp('dart_swagger_to_models_validation_');
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
              'properties': {
                'id': {
                  'type': 'integer',
                  'minimum': 1,
                },
                'name': {
                  'type': 'string',
                  'minLength': 3,
                  'maxLength': 50,
                },
                'tags': {
                  'type': 'array',
                  'items': {'type': 'string'},
                  'minItems': 1,
                  'maxItems': 5,
                },
              },
            },
          },
        },
      };

      await specFile.writeAsString(jsonEncode(spec));

      final configFile =
          File('${tempDir.path}/dart_swagger_to_models.yaml');
      await configFile.writeAsString('generateValidation: true\n');

      final result = await SwaggerToDartGenerator.generateModels(
        input: specFile.path,
        outputDir: '${tempDir.path}/models',
        libraryName: 'api_models',
        projectDir: tempDir.path,
      );

      final productFile =
          result.generatedFiles.firstWhere((f) => f.contains('product.dart'));
      final content = await File(productFile).readAsString();

      expect(content,
          contains('extension ProductValidation on Product'));
      expect(content, contains('List<String> validate()'));
      expect(content,
          contains("errors.add('Product.id must be >= 1.');"));
      expect(
          content,
          contains(
              "errors.add('Product.name length must be >= 3.');"));
      expect(
          content,
          contains(
              "errors.add('Product.name length must be <= 50.');"));
      expect(
          content,
          contains(
              "errors.add('Product.tags items count must be >= 1.');"));
      expect(
          content,
          contains(
              "errors.add('Product.tags items count must be <= 5.');"));
    });

    test('generates simple test data factory for supported types', () async {
      final tempDir = await Directory.systemTemp
          .createTemp('dart_swagger_to_models_testdata_');
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
            'User': {
              'type': 'object',
              'properties': {
                'id': {'type': 'integer'},
                'name': {'type': 'string'},
                'tags': {
                  'type': 'array',
                  'items': {'type': 'string'},
                },
              },
            },
          },
        },
      };

      await specFile.writeAsString(jsonEncode(spec));

      final configFile =
          File('${tempDir.path}/dart_swagger_to_models.yaml');
      await configFile.writeAsString('generateTestData: true\n');

      final result = await SwaggerToDartGenerator.generateModels(
        input: specFile.path,
        outputDir: '${tempDir.path}/models',
        libraryName: 'api_models',
        projectDir: tempDir.path,
      );

      final userFile =
          result.generatedFiles.firstWhere((f) => f.contains('user.dart'));
      final content = await File(userFile).readAsString();

      expect(content,
          contains('User createUserTestData({'));
      expect(content, contains('return User('));
      expect(content, contains('id: 1,'));
      expect(content, contains("name: 'example',"));
      expect(content, contains('tags: <String>[],'));
    });

    test('distinguishes int and num', () async {
      final tempDir =
          await Directory.systemTemp.createTemp('dart_swagger_to_models_test_');
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
        projectDir: tempDir.path,
      );

      final numbersFile =
          result.generatedFiles.firstWhere((f) => f.contains('numbers.dart'));
      final content = await File(numbersFile).readAsString();
      expect(content, contains('final int count;'));
      expect(content, contains('final num price;'));
    });
  });
}
