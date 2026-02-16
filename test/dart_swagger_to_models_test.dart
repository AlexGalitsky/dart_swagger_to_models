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
        projectDir: tempDir.path,
        endpoint: null,
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
        projectDir: tempDir.path,
        endpoint: null,
      );

      final productFile =
          result.generatedFiles.firstWhere((f) => f.contains('product.dart'));
      final content = await File(productFile).readAsString();
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
        projectDir: tempDir.path,
        endpoint: null,
      );

      final baseFile =
          result.generatedFiles.firstWhere((f) => f.contains('base_entity.dart'));
      final userFile =
          result.generatedFiles.firstWhere((f) => f.contains('user.dart'));

      final baseContent = await File(baseFile).readAsString();
      final userContent = await File(userFile).readAsString();

      expect(baseContent, contains('class BaseEntity'));
      expect(baseContent, contains('final int id;'));
      expect(baseContent, contains('final DateTime? createdAt;'));

      expect(userContent, contains('class User'));
      expect(userContent, contains('final String? name;'));
      expect(userContent, contains('final String? email;'));
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
        projectDir: tempDir.path,
        endpoint: null,
      );

      final userFile =
          result.generatedFiles.firstWhere((f) => f.contains('user.dart'));
      final content = await File(userFile).readAsString();
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
        projectDir: tempDir.path,
        endpoint: null,
      );

      final numbersFile =
          result.generatedFiles.firstWhere((f) => f.contains('numbers.dart'));
      final content = await File(numbersFile).readAsString();
      expect(content, contains('final int? count;'));
      expect(content, contains('final num? price;'));
    });
  });

  group('Generation styles', () {
    test('plain_dart (по умолчанию) генерирует ручной fromJson/toJson', () async {
      final tempDir =
          await Directory.systemTemp.createTemp('dart_swagger_to_models_style_plain_');
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
            },
          },
        },
      };

      await specFile.writeAsString(jsonEncode(spec));

      final result = await SwaggerToDartGenerator.generateModels(
        input: specFile.path,
        outputDir: '${tempDir.path}/models',
        libraryName: 'api_models',
        style: GenerationStyle.plainDart,
        projectDir: tempDir.path,
        endpoint: null,
      );

      final userFile =
          result.generatedFiles.firstWhere((f) => f.contains('user.dart'));
      final content = await File(userFile).readAsString();
      expect(content, isNot(contains('@JsonSerializable')));
      expect(content, isNot(contains('@freezed')));
      expect(content, contains('factory User.fromJson'));
      expect(content, contains('Map<String, dynamic> toJson()'));
    });

    test('json_serializable генерирует @JsonSerializable и делегирует в _\$UserFromJson', () async {
      final tempDir =
          await Directory.systemTemp.createTemp('dart_swagger_to_models_style_json_');
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
            },
          },
        },
      };

      await specFile.writeAsString(jsonEncode(spec));

      final result = await SwaggerToDartGenerator.generateModels(
        input: specFile.path,
        outputDir: '${tempDir.path}/models',
        libraryName: 'api_models',
        style: GenerationStyle.jsonSerializable,
        projectDir: tempDir.path,
        endpoint: null,
      );

      final userFile =
          result.generatedFiles.firstWhere((f) => f.contains('user.dart'));
      final content = await File(userFile).readAsString();
      expect(content, contains('@JsonSerializable()'));
      expect(
        content,
        contains('factory User.fromJson(Map<String, dynamic> json) => _\$UserFromJson(json);'),
      );
      expect(
        content,
        contains('Map<String, dynamic> toJson() => _\$UserToJson(this);'),
      );
      expect(content, contains("import 'package:json_annotation/json_annotation.dart';"));
      expect(content, contains("part 'user.g.dart';"));
    });

    test('freezed генерирует @freezed и const factory', () async {
      final tempDir =
          await Directory.systemTemp.createTemp('dart_swagger_to_models_style_freezed_');
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
            },
          },
        },
      };

      await specFile.writeAsString(jsonEncode(spec));

      final result = await SwaggerToDartGenerator.generateModels(
        input: specFile.path,
        outputDir: '${tempDir.path}/models',
        libraryName: 'api_models',
        style: GenerationStyle.freezed,
        projectDir: tempDir.path,
        endpoint: null,
      );

      final userFile =
          result.generatedFiles.firstWhere((f) => f.contains('user.dart'));
      final content = await File(userFile).readAsString();
      expect(content, contains('@freezed'));
      expect(content, contains('class User with _\$User {'));
      expect(content, contains('const factory User({'));
      expect(
        content,
        contains('factory User.fromJson(Map<String, dynamic> json) => _\$UserFromJson(json);'),
      );
      expect(content, contains("import 'package:freezed_annotation/freezed_annotation.dart';"));
      expect(content, contains("part 'user.freezed.dart';"));
      expect(content, contains("part 'user.g.dart';"));
    });

    group('Режим per-file (одна модель = один файл)', () {
      test('создаёт отдельные файлы для каждой модели', () async {
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
              'required': ['id'],
              'properties': {
                'id': {'type': 'integer'},
                'name': {'type': 'string'},
              },
            },
            'Order': {
              'type': 'object',
              'properties': {
                'id': {'type': 'integer'},
                'total': {'type': 'number'},
              },
            },
          },
        };

        await specFile.writeAsString(jsonEncode(spec));

        final result = await SwaggerToDartGenerator.generateModels(
          input: specFile.path,
          outputDir: '${tempDir.path}/models',
          libraryName: 'models',
          style: GenerationStyle.plainDart,
          projectDir: tempDir.path,
          endpoint: null,
        );

        expect(result.generatedFiles.length, greaterThan(1));
        expect(result.generatedFiles.any((f) => f.contains('user.dart')), isTrue);
        expect(result.generatedFiles.any((f) => f.contains('order.dart')), isTrue);

        // Проверяем содержимое файла user.dart
        final userFile =
            result.generatedFiles.firstWhere((f) => f.contains('user.dart'));
        final userContent = await File(userFile).readAsString();
        // endpoint не задан, поэтому маркер без URL
        expect(userContent, contains('/*SWAGGER-TO-DART:*/'));
        expect(userContent, contains('/*SWAGGER-TO-DART: Fields start*/'));
        expect(userContent, contains('/*SWAGGER-TO-DART: Fields stop*/'));
        expect(userContent, contains('class User'));
      });

      test('обновляет существующий файл, сохраняя содержимое вне маркеров', () async {
        final tempDir = await Directory.systemTemp.createTemp('dart_swagger_to_models_test_');
        final specFile = File('${tempDir.path}/swagger.json');
        final modelsDir = Directory('${tempDir.path}/models');
        await modelsDir.create(recursive: true);

        // Создаём существующий файл с маркерами
        final existingUserFile = File('${modelsDir.path}/user.dart');
        await existingUserFile.writeAsString('''
/*SWAGGER-TO-DART:api.example.com*/

import 'package:some_package/some_package.dart';

// Кастомный код до маркеров
void customFunction() {
  print('Custom code');
}

/*SWAGGER-TO-DART: Fields start*/
// Старое содержимое, которое будет заменено
class OldUser {
  final String oldField;
}
/*SWAGGER-TO-DART: Fields stop*/

// Кастомный код после маркеров
extension UserExtension on User {
  String get displayName => name ?? 'Unknown';
}
''');

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
              'required': ['id'],
              'properties': {
                'id': {'type': 'integer'},
                'name': {'type': 'string'},
              },
            },
          },
        };

        await specFile.writeAsString(jsonEncode(spec));

        final result = await SwaggerToDartGenerator.generateModels(
          input: specFile.path,
          outputDir: modelsDir.path,
          libraryName: 'models',
          style: GenerationStyle.plainDart,
          projectDir: tempDir.path,
          endpoint: 'api.example.com',
        );

        final updatedContent = await existingUserFile.readAsString();
        expect(updatedContent, contains('/*SWAGGER-TO-DART:api.example.com*/'));
        expect(updatedContent, contains('import \'package:some_package/some_package.dart\';'));
        expect(updatedContent, contains('void customFunction()'));
        expect(updatedContent, contains('class User'));
        expect(updatedContent, contains('final int id;'));
        expect(updatedContent, contains('final String? name;'));
        expect(updatedContent, contains('extension UserExtension'));
        expect(updatedContent, isNot(contains('class OldUser')));
        expect(updatedContent, isNot(contains('oldField')));
      });

      test('поддерживает json_serializable в режиме per-file', () async {
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
            'Product': {
              'type': 'object',
              'properties': {
                'id': {'type': 'integer'},
                'name': {'type': 'string'},
              },
            },
          },
        };

        await specFile.writeAsString(jsonEncode(spec));

        final result = await SwaggerToDartGenerator.generateModels(
          input: specFile.path,
          outputDir: '${tempDir.path}/models',
          libraryName: 'models',
          style: GenerationStyle.jsonSerializable,
          projectDir: tempDir.path,
          endpoint: null,
        );

        final productFile =
            result.generatedFiles.firstWhere((f) => f.contains('product.dart'));
        final content = await File(productFile).readAsString();
        expect(content, contains('/*SWAGGER-TO-DART:*/'));
        expect(content, contains("import 'package:json_annotation/json_annotation.dart';"));
        expect(content, contains("part 'product.g.dart';"));
        expect(content, contains('@JsonSerializable()'));
        expect(content, contains('class Product'));
        expect(content, contains('_\$ProductFromJson'));
        expect(content, contains('_\$ProductToJson'));
      });

      test('поддерживает freezed в режиме per-file', () async {
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
            'Category': {
              'type': 'object',
              'properties': {
                'id': {'type': 'integer'},
                'name': {'type': 'string'},
              },
            },
          },
        };

        await specFile.writeAsString(jsonEncode(spec));

        final result = await SwaggerToDartGenerator.generateModels(
          input: specFile.path,
          outputDir: '${tempDir.path}/models',
          libraryName: 'models',
          style: GenerationStyle.freezed,
          projectDir: tempDir.path,
          endpoint: null,
        );

        final categoryFile =
            result.generatedFiles.firstWhere((f) => f.contains('category.dart'));
        final content = await File(categoryFile).readAsString();
        expect(content, contains('/*SWAGGER-TO-DART:*/'));
        expect(content, contains("import 'package:freezed_annotation/freezed_annotation.dart';"));
        expect(content, contains("part 'category.freezed.dart';"));
        expect(content, contains("part 'category.g.dart';"));
        expect(content, contains('@freezed'));
        expect(content, contains('class Category with _\$Category'));
        expect(content, contains('const factory Category'));
      });
    });
  });
}
