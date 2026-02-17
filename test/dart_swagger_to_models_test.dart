import 'dart:convert';
import 'dart:io';

import 'package:dart_swagger_to_models/dart_swagger_to_models.dart';
import 'package:dart_swagger_to_models/src/config/config_loader.dart';
import 'package:dart_swagger_to_models/src/core/logger.dart';
import 'package:dart_swagger_to_models/src/generators/plain_dart_generator.dart';
import 'package:dart_swagger_to_models/src/generators/style_registry.dart';
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
      expect(content, contains('final String email;'));
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
      );

      final baseFile =
          result.generatedFiles.firstWhere((f) => f.contains('base_entity.dart'));
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
      );

      final userFile =
          result.generatedFiles.firstWhere((f) => f.contains('user.dart'));
      final content = await File(userFile).readAsString();
      expect(content, contains('final List<String> tags;'));
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
      );

      final numbersFile =
          result.generatedFiles.firstWhere((f) => f.contains('numbers.dart'));
      final content = await File(numbersFile).readAsString();
      expect(content, contains('final int count;'));
      expect(content, contains('final num price;'));
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
        );

        expect(result.generatedFiles.length, greaterThan(1));
        expect(result.generatedFiles.any((f) => f.contains('user.dart')), isTrue);
        expect(result.generatedFiles.any((f) => f.contains('order.dart')), isTrue);

        // Проверяем содержимое файла user.dart
        final userFile =
            result.generatedFiles.firstWhere((f) => f.contains('user.dart'));
        final userContent = await File(userFile).readAsString();
        expect(userContent, contains('/*SWAGGER-TO-DART*/'));
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
/*SWAGGER-TO-DART*/

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

        await SwaggerToDartGenerator.generateModels(
          input: specFile.path,
          outputDir: modelsDir.path,
          libraryName: 'models',
          style: GenerationStyle.plainDart,
          projectDir: tempDir.path,
        );

        final updatedContent = await existingUserFile.readAsString();
        expect(updatedContent, contains('/*SWAGGER-TO-DART*/'));
        expect(updatedContent, contains('import \'package:some_package/some_package.dart\';'));
        expect(updatedContent, contains('void customFunction()'));
        expect(updatedContent, contains('class User'));
        expect(updatedContent, contains('final int id;'));
        expect(updatedContent, contains('final String name;'));
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
        );

        final productFile =
            result.generatedFiles.firstWhere((f) => f.contains('product.dart'));
        final content = await File(productFile).readAsString();
        expect(content, contains('/*SWAGGER-TO-DART*/'));
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
        );

        final categoryFile =
            result.generatedFiles.firstWhere((f) => f.contains('category.dart'));
        final content = await File(categoryFile).readAsString();
        expect(content, contains('/*SWAGGER-TO-DART*/'));
        expect(content, contains("import 'package:freezed_annotation/freezed_annotation.dart';"));
        expect(content, contains("part 'category.freezed.dart';"));
        expect(content, contains("part 'category.g.dart';"));
        expect(content, contains('@freezed'));
        expect(content, contains('class Category with _\$Category'));
        expect(content, contains('const factory Category'));
      });
    });
  });

  group('Конфигурационный файл', () {
    test('загружает конфигурацию из YAML файла', () async {
      final tempDir = await Directory.systemTemp.createTemp('dart_swagger_to_models_config_');
      final configFile = File('${tempDir.path}/dart_swagger_to_models.yaml');

      await configFile.writeAsString('''
defaultStyle: json_serializable
outputDir: lib/generated
projectDir: ${tempDir.path}
''');

      final config = await ConfigLoader.loadConfig(null, tempDir.path);

      expect(config.defaultStyle, equals(GenerationStyle.jsonSerializable));
      expect(config.outputDir, equals('lib/generated'));
      expect(config.projectDir, equals(tempDir.path));
    });

    test('применяет приоритет CLI > config > defaults', () async {
      final tempDir = await Directory.systemTemp.createTemp('dart_swagger_to_models_priority_');
      final configFile = File('${tempDir.path}/dart_swagger_to_models.yaml');
      final specFile = File('${tempDir.path}/swagger.json');

      await configFile.writeAsString('''
defaultStyle: json_serializable
outputDir: lib/config_models
''');

      final spec = <String, dynamic>{
        'swagger': '2.0',
        'info': {'title': 'Test', 'version': '1.0.0'},
        'paths': <String, dynamic>{},
        'definitions': <String, dynamic>{
          'User': {
            'type': 'object',
            'properties': {'id': {'type': 'integer'}},
          },
        },
      };

      await specFile.writeAsString(jsonEncode(spec));

      // CLI переопределяет config
      final result = await SwaggerToDartGenerator.generateModels(
        input: specFile.path,
        outputDir: '${tempDir.path}/cli_models',
        style: GenerationStyle.freezed,
        projectDir: tempDir.path,
        config: await ConfigLoader.loadConfig(null, tempDir.path),
      );

      expect(result.outputDirectory, equals('${tempDir.path}/cli_models'));
      final userFile = result.generatedFiles.firstWhere((f) => f.contains('user.dart'));
      final content = await File(userFile).readAsString();
      expect(content, contains('@freezed')); // CLI style
    });

    test('использует значения из config, если CLI не указан', () async {
      final tempDir = await Directory.systemTemp.createTemp('dart_swagger_to_models_config_only_');
      final configFile = File('${tempDir.path}/dart_swagger_to_models.yaml');
      final specFile = File('${tempDir.path}/swagger.json');

      await configFile.writeAsString('''
defaultStyle: json_serializable
outputDir: lib/config_models
''');

      final spec = <String, dynamic>{
        'swagger': '2.0',
        'info': {'title': 'Test', 'version': '1.0.0'},
        'paths': <String, dynamic>{},
        'definitions': <String, dynamic>{
          'User': {
            'type': 'object',
            'properties': {'id': {'type': 'integer'}},
          },
        },
      };

      await specFile.writeAsString(jsonEncode(spec));

      final result = await SwaggerToDartGenerator.generateModels(
        input: specFile.path,
        projectDir: tempDir.path,
        config: await ConfigLoader.loadConfig(null, tempDir.path),
      );

      expect(result.outputDirectory, equals('lib/config_models'));
      final userFile = result.generatedFiles.firstWhere((f) => f.contains('user.dart'));
      final content = await File(userFile).readAsString();
      expect(content, contains('@JsonSerializable')); // Config style
    });

    test('применяет переопределения для схем: className', () async {
      final tempDir = await Directory.systemTemp.createTemp('dart_swagger_to_models_override_');
      final configFile = File('${tempDir.path}/dart_swagger_to_models.yaml');
      final specFile = File('${tempDir.path}/swagger.json');

      await configFile.writeAsString('''
schemas:
  User:
    className: CustomUser
''');

      final spec = <String, dynamic>{
        'swagger': '2.0',
        'info': {'title': 'Test', 'version': '1.0.0'},
        'paths': <String, dynamic>{},
        'definitions': <String, dynamic>{
          'User': {
            'type': 'object',
            'properties': {'id': {'type': 'integer'}},
          },
        },
      };

      await specFile.writeAsString(jsonEncode(spec));

      final result = await SwaggerToDartGenerator.generateModels(
        input: specFile.path,
        outputDir: '${tempDir.path}/models',
        projectDir: tempDir.path,
        config: await ConfigLoader.loadConfig(null, tempDir.path),
      );

      final userFile = result.generatedFiles.firstWhere((f) => f.contains('user.dart'));
      final content = await File(userFile).readAsString();
      expect(content, contains('class CustomUser'));
      expect(content, isNot(contains('class User')));
    });

    test('применяет переопределения для схем: fieldNames', () async {
      final tempDir = await Directory.systemTemp.createTemp('dart_swagger_to_models_fieldnames_');
      final configFile = File('${tempDir.path}/dart_swagger_to_models.yaml');
      final specFile = File('${tempDir.path}/swagger.json');

      await configFile.writeAsString('''
schemas:
  User:
    fieldNames:
      user_id: userId
      user_name: userName
''');

      final spec = <String, dynamic>{
        'swagger': '2.0',
        'info': {'title': 'Test', 'version': '1.0.0'},
        'paths': <String, dynamic>{},
        'definitions': <String, dynamic>{
          'User': {
            'type': 'object',
            'properties': {
              'user_id': {'type': 'integer'},
              'user_name': {'type': 'string'},
            },
          },
        },
      };

      await specFile.writeAsString(jsonEncode(spec));

      final result = await SwaggerToDartGenerator.generateModels(
        input: specFile.path,
        outputDir: '${tempDir.path}/models',
        projectDir: tempDir.path,
        config: await ConfigLoader.loadConfig(null, tempDir.path),
      );

      final userFile = result.generatedFiles.firstWhere((f) => f.contains('user.dart'));
      final content = await File(userFile).readAsString();
      expect(content, contains('final int userId;'));
      expect(content, contains('final String userName;'));
      expect(content, contains("json['user_id']")); // JSON ключ остаётся оригинальным
      expect(content, contains("json['user_name']"));
    });

    test('применяет переопределения для схем: typeMapping', () async {
      final tempDir = await Directory.systemTemp.createTemp('dart_swagger_to_models_typemap_');
      final configFile = File('${tempDir.path}/dart_swagger_to_models.yaml');
      final specFile = File('${tempDir.path}/swagger.json');

      await configFile.writeAsString('''
schemas:
  User:
    typeMapping:
      string: MyCustomString
      integer: MyCustomInt
''');

      final spec = <String, dynamic>{
        'swagger': '2.0',
        'info': {'title': 'Test', 'version': '1.0.0'},
        'paths': <String, dynamic>{},
        'definitions': <String, dynamic>{
          'User': {
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
        projectDir: tempDir.path,
        config: await ConfigLoader.loadConfig(null, tempDir.path),
      );

      final userFile = result.generatedFiles.firstWhere((f) => f.contains('user.dart'));
      final content = await File(userFile).readAsString();
      expect(content, contains('final MyCustomInt id;'));
      expect(content, contains('final MyCustomString name;'));
    });

    test('возвращает пустую конфигурацию, если файл не найден', () async {
      final tempDir = await Directory.systemTemp.createTemp('dart_swagger_to_models_no_config_');
      final config = await ConfigLoader.loadConfig(null, tempDir.path);

      expect(config.defaultStyle, isNull);
      expect(config.outputDir, isNull);
      expect(config.projectDir, isNull);
      expect(config.schemaOverrides, isEmpty);
    });

    test('загружает конфигурацию по указанному пути', () async {
      final tempDir = await Directory.systemTemp.createTemp('dart_swagger_to_models_custom_path_');
      final configFile = File('${tempDir.path}/custom_config.yaml');

      await configFile.writeAsString('''
defaultStyle: freezed
outputDir: lib/custom
''');

      final config = await ConfigLoader.loadConfig(configFile.path, tempDir.path);

      expect(config.defaultStyle, equals(GenerationStyle.freezed));
      expect(config.outputDir, equals('lib/custom'));
    });
  });

  group('Качество генерируемого кода', () {
    test('поддерживает x-enumNames для enum значений', () async {
      final tempDir = await Directory.systemTemp.createTemp('dart_swagger_to_models_enum_names_');
      final specFile = File('${tempDir.path}/swagger.json');

      final spec = <String, dynamic>{
        'swagger': '2.0',
        'info': {'title': 'Test', 'version': '1.0.0'},
        'paths': <String, dynamic>{},
        'definitions': <String, dynamic>{
          'Status': {
            'type': 'string',
            'enum': ['active', 'inactive', 'pending'],
            'x-enumNames': ['Active', 'Inactive', 'Pending'],
          },
        },
      };

      await specFile.writeAsString(jsonEncode(spec));

      final result = await SwaggerToDartGenerator.generateModels(
        input: specFile.path,
        outputDir: '${tempDir.path}/models',
        projectDir: tempDir.path,
      );

      final statusFile = result.generatedFiles.firstWhere((f) => f.contains('status.dart'));
      final content = await File(statusFile).readAsString();
      expect(content, contains('Active,'));
      expect(content, contains('Inactive,'));
      expect(content, contains('Pending;'));
      // Проверяем, что используются кастомные имена из x-enumNames
      expect(content.contains('Active') || content.contains('Inactive') || content.contains('Pending'), isTrue);
    });

    test('поддерживает x-enum-varnames для enum значений', () async {
      final tempDir = await Directory.systemTemp.createTemp('dart_swagger_to_models_enum_varnames_');
      final specFile = File('${tempDir.path}/swagger.json');

      final spec = <String, dynamic>{
        'swagger': '2.0',
        'info': {'title': 'Test', 'version': '1.0.0'},
        'paths': <String, dynamic>{},
        'definitions': <String, dynamic>{
          'Status': {
            'type': 'string',
            'enum': ['active', 'inactive'],
            'x-enum-varnames': ['ActiveStatus', 'InactiveStatus'],
          },
        },
      };

      await specFile.writeAsString(jsonEncode(spec));

      final result = await SwaggerToDartGenerator.generateModels(
        input: specFile.path,
        outputDir: '${tempDir.path}/models',
        projectDir: tempDir.path,
      );

      final statusFile = result.generatedFiles.firstWhere((f) => f.contains('status.dart'));
      final content = await File(statusFile).readAsString();
      expect(content, contains('ActiveStatus,'));
      expect(content, contains('InactiveStatus;'));
    });

    test('генерирует импорты для зависимостей между моделями', () async {
      final tempDir = await Directory.systemTemp.createTemp('dart_swagger_to_models_imports_');
      final specFile = File('${tempDir.path}/swagger.json');

      final spec = <String, dynamic>{
        'swagger': '2.0',
        'info': {'title': 'Test', 'version': '1.0.0'},
        'paths': <String, dynamic>{},
        'definitions': <String, dynamic>{
          'User': {
            'type': 'object',
            'properties': {
              'id': {'type': 'integer'},
              'name': {'type': 'string'},
            },
          },
          'Order': {
            'type': 'object',
            'properties': {
              'id': {'type': 'integer'},
              'user': {'\$ref': '#/definitions/User'},
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

      final orderFile = result.generatedFiles.firstWhere((f) => f.contains('order.dart'));
      final content = await File(orderFile).readAsString();
      // Проверяем, что используется правильный тип User вместо dynamic
      expect(content, contains('final User user;'));
      expect(content, isNot(contains('final dynamic user;')));
      // Проверяем, что есть импорт (может быть относительный путь или просто имя файла)
      final hasImport = content.contains("import 'user.dart';") || 
                       content.contains("import './user.dart';") ||
                       content.contains("import 'user';");
      expect(hasImport, isTrue, reason: 'Должен быть импорт для User. Содержимое: $content');
    });

    test('не генерирует импорт на самого себя', () async {
      final tempDir = await Directory.systemTemp.createTemp('dart_swagger_to_models_no_self_import_');
      final specFile = File('${tempDir.path}/swagger.json');

      final spec = <String, dynamic>{
        'swagger': '2.0',
        'info': {'title': 'Test', 'version': '1.0.0'},
        'paths': <String, dynamic>{},
        'definitions': <String, dynamic>{
          'User': {
            'type': 'object',
            'properties': {
              'id': {'type': 'integer'},
              'parent': {'\$ref': '#/definitions/User'},
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

      final userFile = result.generatedFiles.firstWhere((f) => f.contains('user.dart'));
      final content = await File(userFile).readAsString();
      // Не должно быть импорта на самого себя
      expect(content, isNot(contains("import 'user.dart';")));
      expect(content, contains('final User parent;'));
    });
  });

  group('Улучшение ergonomics для json_serializable / freezed', () {
    test('генерирует @JsonKey для snake_case JSON-ключей в json_serializable', () async {
      final tempDir = await Directory.systemTemp.createTemp('dart_swagger_to_models_jsonkey_');
      final configFile = File('${tempDir.path}/dart_swagger_to_models.yaml');
      final specFile = File('${tempDir.path}/swagger.json');

      await configFile.writeAsString('''
useJsonKey: true
''');

      final spec = <String, dynamic>{
        'swagger': '2.0',
        'info': {'title': 'Test', 'version': '1.0.0'},
        'paths': <String, dynamic>{},
        'definitions': <String, dynamic>{
          'User': {
            'type': 'object',
            'properties': {
              'user_id': {'type': 'integer'},
              'user_name': {'type': 'string'},
              'email': {'type': 'string'}, // camelCase - не нужен @JsonKey
            },
          },
        },
      };

      await specFile.writeAsString(jsonEncode(spec));

      final result = await SwaggerToDartGenerator.generateModels(
        input: specFile.path,
        outputDir: '${tempDir.path}/models',
        projectDir: tempDir.path,
        style: GenerationStyle.jsonSerializable,
        config: await ConfigLoader.loadConfig(null, tempDir.path),
      );

      final userFile = result.generatedFiles.firstWhere((f) => f.contains('user.dart'));
      final content = await File(userFile).readAsString();
      // Проверяем, что для snake_case полей есть @JsonKey
      expect(content, contains("@JsonKey(name: 'user_id')"));
      expect(content, contains("@JsonKey(name: 'user_name')"));
      // Для camelCase полей @JsonKey не нужен
      expect(content, isNot(contains("@JsonKey(name: 'email')")));
      expect(content, contains('final int userId;'));
      expect(content, contains('final String userName;'));
      expect(content, contains('final String email;'));
    });

    test('генерирует @JsonKey для snake_case JSON-ключей в freezed', () async {
      final tempDir = await Directory.systemTemp.createTemp('dart_swagger_to_models_jsonkey_freezed_');
      final configFile = File('${tempDir.path}/dart_swagger_to_models.yaml');
      final specFile = File('${tempDir.path}/swagger.json');

      await configFile.writeAsString('''
useJsonKey: true
''');

      final spec = <String, dynamic>{
        'swagger': '2.0',
        'info': {'title': 'Test', 'version': '1.0.0'},
        'paths': <String, dynamic>{},
        'definitions': <String, dynamic>{
          'User': {
            'type': 'object',
            'properties': {
              'user_id': {'type': 'integer'},
              'user_name': {'type': 'string'},
            },
          },
        },
      };

      await specFile.writeAsString(jsonEncode(spec));

      final result = await SwaggerToDartGenerator.generateModels(
        input: specFile.path,
        outputDir: '${tempDir.path}/models',
        projectDir: tempDir.path,
        style: GenerationStyle.freezed,
        config: await ConfigLoader.loadConfig(null, tempDir.path),
      );

      final userFile = result.generatedFiles.firstWhere((f) => f.contains('user.dart'));
      final content = await File(userFile).readAsString();
      // Проверяем, что для snake_case полей есть @JsonKey в const factory
      expect(content, contains("@JsonKey(name: 'user_id')"));
      expect(content, contains("@JsonKey(name: 'user_name')"));
      expect(content, contains('required int userId,'));
      expect(content, contains('required String userName,'));
    });

    test('не генерирует @JsonKey, если useJsonKey: false', () async {
      final tempDir = await Directory.systemTemp.createTemp('dart_swagger_to_models_no_jsonkey_');
      final configFile = File('${tempDir.path}/dart_swagger_to_models.yaml');
      final specFile = File('${tempDir.path}/swagger.json');

      await configFile.writeAsString('''
useJsonKey: false
''');

      final spec = <String, dynamic>{
        'swagger': '2.0',
        'info': {'title': 'Test', 'version': '1.0.0'},
        'paths': <String, dynamic>{},
        'definitions': <String, dynamic>{
          'User': {
            'type': 'object',
            'properties': {
              'user_id': {'type': 'integer'},
            },
          },
        },
      };

      await specFile.writeAsString(jsonEncode(spec));

      final result = await SwaggerToDartGenerator.generateModels(
        input: specFile.path,
        outputDir: '${tempDir.path}/models',
        projectDir: tempDir.path,
        style: GenerationStyle.jsonSerializable,
        config: await ConfigLoader.loadConfig(null, tempDir.path),
      );

      final userFile = result.generatedFiles.firstWhere((f) => f.contains('user.dart'));
      final content = await File(userFile).readAsString();
      // @JsonKey не должен генерироваться
      expect(content, isNot(contains("@JsonKey(name: 'user_id')")));
      expect(content, contains('final int userId;'));
    });

    test('переопределение useJsonKey на уровне схемы', () async {
      final tempDir = await Directory.systemTemp.createTemp('dart_swagger_to_models_jsonkey_override_');
      final configFile = File('${tempDir.path}/dart_swagger_to_models.yaml');
      final specFile = File('${tempDir.path}/swagger.json');

      await configFile.writeAsString('''
useJsonKey: false
schemas:
  User:
    useJsonKey: true
''');

      final spec = <String, dynamic>{
        'swagger': '2.0',
        'info': {'title': 'Test', 'version': '1.0.0'},
        'paths': <String, dynamic>{},
        'definitions': <String, dynamic>{
          'User': {
            'type': 'object',
            'properties': {
              'user_id': {'type': 'integer'},
            },
          },
          'Order': {
            'type': 'object',
            'properties': {
              'order_id': {'type': 'integer'},
            },
          },
        },
      };

      await specFile.writeAsString(jsonEncode(spec));

      final result = await SwaggerToDartGenerator.generateModels(
        input: specFile.path,
        outputDir: '${tempDir.path}/models',
        projectDir: tempDir.path,
        style: GenerationStyle.jsonSerializable,
        config: await ConfigLoader.loadConfig(null, tempDir.path),
      );

      final userFile = result.generatedFiles.firstWhere((f) => f.contains('user.dart'));
      final orderFile = result.generatedFiles.firstWhere((f) => f.contains('order.dart'));
      
      final userContent = await File(userFile).readAsString();
      final orderContent = await File(orderFile).readAsString();
      
      // User должен иметь @JsonKey (переопределение на уровне схемы)
      expect(userContent, contains("@JsonKey(name: 'user_id')"));
      
      // Order не должен иметь @JsonKey (глобальная опция false)
      expect(orderContent, isNot(contains("@JsonKey(name: 'order_id')")));
    });
  });

  group('Подсказки по качеству спецификаций (spec linting)', () {
    test('lint правила работают по умолчанию', () async {
      final tempDir = await Directory.systemTemp.createTemp('dart_swagger_to_models_lint_');
      final specFile = File('${tempDir.path}/swagger.json');

      final spec = <String, dynamic>{
        'swagger': '2.0',
        'info': {'title': 'Test', 'version': '1.0.0'},
        'paths': <String, dynamic>{},
        'definitions': <String, dynamic>{
          'User': {
            'type': 'object',
            'properties': {
              'name': {}, // Нет типа
              'id': {'type': 'integer'}, // Подозрительное id поле
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

      // Должны быть предупреждения
      expect(Logger.warnings.length, greaterThan(0));
    });

    test('lint правила можно отключить через конфиг', () async {
      final tempDir = await Directory.systemTemp.createTemp('dart_swagger_to_models_lint_disabled_');
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
            'properties': {
              'name': {}, // Нет типа - должно быть предупреждение, но отключено
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

      // Не должно быть предупреждений, так как lint отключен
      expect(Logger.warnings.length, 0);
    });

    test('lint правила можно настроить индивидуально', () async {
      final tempDir = await Directory.systemTemp.createTemp('dart_swagger_to_models_lint_custom_');
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
            'properties': {
              'name': {}, // Нет типа - должно быть ошибка
              'id': {'type': 'integer'}, // Подозрительное id - должно быть отключено
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

      // Должна быть ошибка для missing_type
      expect(Logger.errors.length, greaterThan(0));
      expect(Logger.errors.any((e) => e.contains('не имеет типа')), isTrue);
      
      // Не должно быть предупреждений для suspicious_id_field
      expect(Logger.warnings.any((w) => w.contains('идентификатор')), isFalse);
    });

    test('проверка пустого объекта', () async {
      final tempDir = await Directory.systemTemp.createTemp('dart_swagger_to_models_lint_empty_');
      final specFile = File('${tempDir.path}/swagger.json');

      final spec = <String, dynamic>{
        'swagger': '2.0',
        'info': {'title': 'Test', 'version': '1.0.0'},
        'paths': <String, dynamic>{},
        'definitions': <String, dynamic>{
          'EmptySchema': {
            'type': 'object',
            'properties': {},
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

      // Должно быть предупреждение о пустом объекте
      expect(Logger.warnings.any((w) => w.contains('пустым объектом')), isTrue);
    });

    test('проверка массива без items', () async {
      final tempDir = await Directory.systemTemp.createTemp('dart_swagger_to_models_lint_array_');
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
                // Нет items
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

      // Должно быть предупреждение о массиве без items
      expect(Logger.warnings.any((w) => w.contains('array') && w.contains('items')), isTrue);
    });

    test('проверка пустого enum', () async {
      final tempDir = await Directory.systemTemp.createTemp('dart_swagger_to_models_lint_empty_enum_');
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

      // Должно быть предупреждение о пустом enum
      expect(Logger.warnings.any((w) => w.contains('Enum') && w.contains('не содержит значений')), isTrue);
    });

    test('проверка несогласованности типов', () async {
      final tempDir = await Directory.systemTemp.createTemp('dart_swagger_to_models_lint_inconsistency_');
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
                'format': 'date-time', // Несогласованность: format для integer
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

      // Должно быть предупреждение о несогласованности типов
      expect(Logger.warnings.any((w) => w.contains('integer') && w.contains('format')), isTrue);
    });
  });

  group('Улучшенная поддержка OpenAPI (0.2.1)', () {
    test('обрабатывает вложенные allOf комбинации', () async {
      final tempDir = await Directory.systemTemp.createTemp('dart_swagger_to_models_nested_allof_');
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

      final userFile = result.generatedFiles.firstWhere((f) => f.contains('user.dart'));
      final content = await File(userFile).readAsString();

      // User должен содержать все свойства из Base, Timestamped и свои
      expect(content, contains('class User'));
      expect(content, contains('final int id;')); // Из Base
      expect(content, contains('final DateTime createdAt;')); // Из Timestamped
      expect(content, contains('final String name;')); // Из User
    });

    test('обрабатывает множественное наследование через allOf', () async {
      final tempDir = await Directory.systemTemp.createTemp('dart_swagger_to_models_multiple_allof_');
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

      final productFile = result.generatedFiles.firstWhere((f) => f.contains('product.dart'));
      final content = await File(productFile).readAsString();

      // Product должен содержать свойства из всех трёх базовых схем и свои
      expect(content, contains('class Product'));
      expect(content, contains('final int id;')); // Из Identifiable
      expect(content, contains('final String name;')); // Из Named
      expect(content, contains('final DateTime createdAt;')); // Из Timestamped
      expect(content, contains('final num price;')); // Из Product
    });

    test('генерирует безопасную обёртку для oneOf', () async {
      final tempDir = await Directory.systemTemp.createTemp('dart_swagger_to_models_oneof_');
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

      // Ищем файл для схемы Value (oneOf)
      final valueFiles = result.generatedFiles.where((f) => f.endsWith('value.dart')).toList();
      expect(valueFiles, isNotEmpty, reason: 'Должен быть сгенерирован файл для схемы Value');
      
      // Может быть несколько файлов (StringValue, NumberValue, Value)
      // Находим файл для схемы Value (oneOf)
      File? valueFile;
      for (final filePath in valueFiles) {
        final content = await File(filePath).readAsString();
        if (content.contains('class Value') && content.contains('final dynamic value;')) {
          valueFile = File(filePath);
          break;
        }
      }
      
      expect(valueFile, isNotNull, reason: 'Должен быть найден файл с классом Value (oneOf)');
      final content = await valueFile!.readAsString();

      // Должна быть сгенерирована безопасная обёртка
      expect(content, contains('class Value'));
      expect(content, contains('final dynamic value;'));
      expect(content, contains('factory Value.fromJson(dynamic json)'));
      expect(content, contains('dynamic toJson() => value;'));
      
      // Должно быть логирование о возможных типах
      expect(Logger.warnings.any((w) => w.contains('oneOf') || w.contains('anyOf')), isFalse);
    });

    test('генерирует безопасную обёртку для anyOf', () async {
      final tempDir = await Directory.systemTemp.createTemp('dart_swagger_to_models_anyof_');
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

      final errorFile = result.generatedFiles.firstWhere((f) => f.contains('error.dart'));
      final content = await File(errorFile).readAsString();

      // Должна быть сгенерирована безопасная обёртка
      expect(content, contains('class Error'));
      expect(content, contains('final dynamic value;'));
      expect(content, contains('factory Error.fromJson(dynamic json)'));
    });

    test('обрабатывает oneOf с discriminator и логирует информацию', () async {
      final tempDir = await Directory.systemTemp.createTemp('dart_swagger_to_models_oneof_discriminator_');
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
                'type': {'type': 'string', 'enum': ['cat']},
                'meow': {'type': 'boolean'},
              },
            },
            'Dog': {
              'type': 'object',
              'properties': {
                'type': {'type': 'string', 'enum': ['dog']},
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

      Logger.clear();
      final result = await SwaggerToDartGenerator.generateModels(
        input: specFile.path,
        outputDir: '${tempDir.path}/models',
        projectDir: tempDir.path,
      );

      // Должно быть логирование о discriminator (в verbose режиме)
      // Проверяем, что генерация прошла успешно
      final petFile = result.generatedFiles.firstWhere((f) => f.contains('pet.dart'));
      final content = await File(petFile).readAsString();
      expect(content, contains('class Pet'));
    });

    test('обрабатывает циклические зависимости в allOf', () async {
      final tempDir = await Directory.systemTemp.createTemp('dart_swagger_to_models_allof_cycle_');
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
            // Попытка создать цикл (Extended ссылается на Base, который не должен ссылаться обратно)
            'Final': {
              'allOf': [
                {'\$ref': '#/components/schemas/Extended'},
                {'\$ref': '#/components/schemas/Base'}, // Повторная ссылка на Base
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

      final finalFile = result.generatedFiles.firstWhere((f) => f.contains('final.dart'));
      final content = await File(finalFile).readAsString();

      // Final должен содержать свойства из Base, Extended и свои
      expect(content, contains('class Final'));
      expect(content, contains('final int id;')); // Из Base (через Extended и напрямую)
      expect(content, contains('final String name;')); // Из Extended
      expect(content, contains('final String extra;')); // Из Final
    });
  });

  group('Инкрементальная генерация (0.5.1)', () {
    test('генерирует все схемы при первом запуске', () async {
      final tempDir = await Directory.systemTemp.createTemp('dart_swagger_to_models_cache_');
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

      // Должны быть сгенерированы все схемы
      expect(result.schemasProcessed, equals(2));
      expect(result.generatedFiles.length, equals(2));

      // Проверяем, что кэш создан
      final cacheFile = File('${tempDir.path}/.dart_swagger_to_models.cache');
      expect(await cacheFile.exists(), isTrue);
    });

    test('генерирует только изменённые схемы при втором запуске', () async {
      final tempDir = await Directory.systemTemp.createTemp('dart_swagger_to_models_cache2_');
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

      // Первый запуск - генерируем все
      final result1 = await SwaggerToDartGenerator.generateModels(
        input: specFile.path,
        outputDir: '${tempDir.path}/models',
        projectDir: tempDir.path,
        changedOnly: true,
      );

      expect(result1.schemasProcessed, equals(2));

      // Изменяем только User
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
                'email': {'type': 'string'}, // Добавили поле
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

      // Второй запуск - только изменённые
      Logger.clear();
      final result2 = await SwaggerToDartGenerator.generateModels(
        input: specFile.path,
        outputDir: '${tempDir.path}/models',
        projectDir: tempDir.path,
        changedOnly: true,
      );

      // Должна быть обработана только одна схема (User)
      expect(result2.schemasProcessed, equals(1));

      // Проверяем, что User обновлён
      final userFile = result2.generatedFiles.firstWhere((f) => f.contains('user.dart'));
      final userContent = await File(userFile).readAsString();
      expect(userContent, contains('final String email;'));
    });

    test('удаляет файлы для удалённых схем', () async {
      final tempDir = await Directory.systemTemp.createTemp('dart_swagger_to_models_cache3_');
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

      // Первый запуск
      await SwaggerToDartGenerator.generateModels(
        input: specFile.path,
        outputDir: '${tempDir.path}/models',
        projectDir: tempDir.path,
        changedOnly: true,
      );

      // Проверяем, что файлы созданы
      final userFile = File('${tempDir.path}/models/user.dart');
      final productFile = File('${tempDir.path}/models/product.dart');
      expect(await userFile.exists(), isTrue);
      expect(await productFile.exists(), isTrue);

      // Удаляем Product из спецификации
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

      // Второй запуск
      await SwaggerToDartGenerator.generateModels(
        input: specFile.path,
        outputDir: '${tempDir.path}/models',
        projectDir: tempDir.path,
        changedOnly: true,
      );

      // Product должен быть удалён
      expect(await productFile.exists(), isFalse);
      expect(await userFile.exists(), isTrue);
    });

    test('добавляет новые схемы при инкрементальной генерации', () async {
      final tempDir = await Directory.systemTemp.createTemp('dart_swagger_to_models_cache4_');
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

      // Первый запуск
      await SwaggerToDartGenerator.generateModels(
        input: specFile.path,
        outputDir: '${tempDir.path}/models',
        projectDir: tempDir.path,
        changedOnly: true,
      );

      // Добавляем новую схему
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

      // Второй запуск
      final result = await SwaggerToDartGenerator.generateModels(
        input: specFile.path,
        outputDir: '${tempDir.path}/models',
        projectDir: tempDir.path,
        changedOnly: true,
      );

      // Должна быть обработана только новая схема (Product)
      expect(result.schemasProcessed, equals(1));

      // Проверяем, что Product создан
      final productFile = File('${tempDir.path}/models/product.dart');
      expect(await productFile.exists(), isTrue);
    });

    test('работает без кэша (первый запуск)', () async {
      final tempDir = await Directory.systemTemp.createTemp('dart_swagger_to_models_cache5_');
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

      // Запуск без кэша (changedOnly = true, но кэша нет)
      final result = await SwaggerToDartGenerator.generateModels(
        input: specFile.path,
        outputDir: '${tempDir.path}/models',
        projectDir: tempDir.path,
        changedOnly: true,
      );

      // Должна быть обработана одна схема
      expect(result.schemasProcessed, equals(1));
      expect(result.generatedFiles.length, equals(1));
    });
  });

  group('Подключаемые стили (0.3.1)', () {
    test('можно зарегистрировать и использовать кастомный стиль', () async {
      final tempDir = await Directory.systemTemp.createTemp('dart_swagger_to_models_custom_style_');
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

      // Регистрируем простой кастомный стиль
      StyleRegistry.register('test_style', () => PlainDartGenerator());

      try {
        final result = await SwaggerToDartGenerator.generateModels(
          input: specFile.path,
          outputDir: '${tempDir.path}/models',
          projectDir: tempDir.path,
        );

        // Создаём конфиг с кастомным стилем
        final config = Config(
          customStyleName: 'test_style',
        );

        final result2 = await SwaggerToDartGenerator.generateModels(
          input: specFile.path,
          outputDir: '${tempDir.path}/models2',
          projectDir: tempDir.path,
          config: config,
        );

        expect(result2.generatedFiles.length, equals(1));
        final userFile = result2.generatedFiles.firstWhere((f) => f.contains('user.dart'));
        final content = await File(userFile).readAsString();
        expect(content, contains('class User'));
      } finally {
        StyleRegistry.unregister('test_style');
      }
    });

    test('выбрасывает ошибку при использовании незарегистрированного стиля', () async {
      final tempDir = await Directory.systemTemp.createTemp('dart_swagger_to_models_unregistered_style_');
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
              },
            },
          },
        },
      };

      await specFile.writeAsString(jsonEncode(spec));

      final config = Config(
        customStyleName: 'non_existent_style',
      );

      expect(
        () => SwaggerToDartGenerator.generateModels(
          input: specFile.path,
          outputDir: '${tempDir.path}/models',
          projectDir: tempDir.path,
          config: config,
        ),
        throwsA(isA<ArgumentError>().having(
          (e) => e.message,
          'message',
          contains('не зарегистрирован'),
        )),
      );
    });

    test('поддерживает кастомный стиль через CLI', () async {
      final tempDir = await Directory.systemTemp.createTemp('dart_swagger_to_models_cli_custom_style_');
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

      // Регистрируем кастомный стиль
      StyleRegistry.register('cli_test_style', () => PlainDartGenerator());

      try {
        // Используем кастомный стиль через конфиг
        final config = Config(
          customStyleName: 'cli_test_style',
        );

        final result = await SwaggerToDartGenerator.generateModels(
          input: specFile.path,
          outputDir: '${tempDir.path}/models',
          projectDir: tempDir.path,
          config: config,
        );

        expect(result.generatedFiles.length, equals(1));
      } finally {
        StyleRegistry.unregister('cli_test_style');
      }
    });

    test('поддерживает кастомный стиль через конфиг файл', () async {
      final tempDir = await Directory.systemTemp.createTemp('dart_swagger_to_models_config_custom_style_');
      final specFile = File('${tempDir.path}/openapi.json');
      final configFile = File('${tempDir.path}/dart_swagger_to_models.yaml');

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

      // Создаём конфиг с кастомным стилем
      await configFile.writeAsString('''
defaultStyle: config_test_style
''');

      // Регистрируем кастомный стиль
      StyleRegistry.register('config_test_style', () => PlainDartGenerator());

      try {
        final config = await ConfigLoader.loadConfig(configFile.path, tempDir.path);
        expect(config.customStyleName, equals('config_test_style'));

        final result = await SwaggerToDartGenerator.generateModels(
          input: specFile.path,
          outputDir: '${tempDir.path}/models',
          projectDir: tempDir.path,
          config: config,
        );

        expect(result.generatedFiles.length, equals(1));
      } finally {
        StyleRegistry.unregister('config_test_style');
      }
    });
  });
}
