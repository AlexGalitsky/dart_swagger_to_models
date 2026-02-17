import 'dart:convert';
import 'dart:io';

import 'package:dart_swagger_to_models/dart_swagger_to_models.dart';
import 'package:test/test.dart';

void main() {
  group('Generation styles', () {
    test('plain_dart (default) generates manual fromJson/toJson', () async {
      final tempDir = await Directory.systemTemp
          .createTemp('dart_swagger_to_models_style_plain_');
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

    test(
        'json_serializable generates @JsonSerializable and delegates to _\$UserFromJson',
        () async {
      final tempDir = await Directory.systemTemp
          .createTemp('dart_swagger_to_models_style_json_');
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
        contains(
            'factory User.fromJson(Map<String, dynamic> json) => _\$UserFromJson(json);'),
      );
      expect(
        content,
        contains('Map<String, dynamic> toJson() => _\$UserToJson(this);'),
      );
      expect(content,
          contains("import 'package:json_annotation/json_annotation.dart';"));
      expect(content, contains("part 'user.g.dart';"));
    });

    test('freezed generates @freezed and const factory', () async {
      final tempDir = await Directory.systemTemp
          .createTemp('dart_swagger_to_models_style_freezed_');
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
        contains(
            'factory User.fromJson(Map<String, dynamic> json) => _\$UserFromJson(json);'),
      );
      expect(
          content,
          contains(
              "import 'package:freezed_annotation/freezed_annotation.dart';"));
      expect(content, contains("part 'user.freezed.dart';"));
      expect(content, contains("part 'user.g.dart';"));
    });

    group('Per-file mode (one model = one file)', () {
      test('creates separate files for each model', () async {
        final tempDir = await Directory.systemTemp
            .createTemp('dart_swagger_to_models_test_');
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
        expect(
            result.generatedFiles.any((f) => f.contains('user.dart')), isTrue);
        expect(
            result.generatedFiles.any((f) => f.contains('order.dart')), isTrue);

        final userFile =
            result.generatedFiles.firstWhere((f) => f.contains('user.dart'));
        final userContent = await File(userFile).readAsString();
        expect(userContent, contains('/*SWAGGER-TO-DART*/'));
        expect(userContent, contains('/*SWAGGER-TO-DART: Codegen start*/'));
        expect(userContent, contains('/*SWAGGER-TO-DART: Codegen stop*/'));
        expect(userContent, contains('class User'));
      });

      test('updates existing file, preserving content outside markers',
          () async {
        final tempDir = await Directory.systemTemp
            .createTemp('dart_swagger_to_models_test_');
        final specFile = File('${tempDir.path}/swagger.json');
        final modelsDir = Directory('${tempDir.path}/models');
        await modelsDir.create(recursive: true);

        final existingUserFile = File('${modelsDir.path}/user.dart');
        await existingUserFile.writeAsString('''
/*SWAGGER-TO-DART*/

import 'package:some_package/some_package.dart';

void customFunction() {
  print('Custom code');
}

/*SWAGGER-TO-DART: Codegen start*/
class OldUser {
  final String oldField;
}
/*SWAGGER-TO-DART: Codegen stop*/

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
        expect(updatedContent,
            contains('import \'package:some_package/some_package.dart\';'));
        expect(updatedContent, contains('void customFunction()'));
        expect(updatedContent, contains('class User'));
        expect(updatedContent, contains('final int id;'));
        expect(updatedContent, contains('final String name;'));
        expect(updatedContent, contains('extension UserExtension'));
        expect(updatedContent, isNot(contains('class OldUser')));
        expect(updatedContent, isNot(contains('oldField')));
      });

      test('supports json_serializable in per-file mode', () async {
        final tempDir = await Directory.systemTemp
            .createTemp('dart_swagger_to_models_test_');
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
        expect(content,
            contains("import 'package:json_annotation/json_annotation.dart';"));
        expect(content, contains("part 'product.g.dart';"));
        expect(content, contains('@JsonSerializable()'));
        expect(content, contains('class Product'));
        expect(content, contains('_\$ProductFromJson'));
        expect(content, contains('_\$ProductToJson'));
      });

      test('supports freezed in per-file mode', () async {
        final tempDir = await Directory.systemTemp
            .createTemp('dart_swagger_to_models_test_');
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

        final categoryFile = result.generatedFiles
            .firstWhere((f) => f.contains('category.dart'));
        final content = await File(categoryFile).readAsString();
        expect(content, contains('/*SWAGGER-TO-DART*/'));
        expect(
            content,
            contains(
                "import 'package:freezed_annotation/freezed_annotation.dart';"));
        expect(content, contains("part 'category.freezed.dart';"));
        expect(content, contains("part 'category.g.dart';"));
        expect(content, contains('@freezed'));
        expect(content, contains('class Category with _\$Category'));
        expect(content, contains('const factory Category'));
      });
    });
  });
}
