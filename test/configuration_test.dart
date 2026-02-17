import 'dart:convert';
import 'dart:io';

import 'package:dart_swagger_to_models/dart_swagger_to_models.dart';
import 'package:dart_swagger_to_models/src/config/config_loader.dart';
import 'package:test/test.dart';

void main() {
  group('Configuration file', () {
    test('loads configuration from YAML file', () async {
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

    test('applies priority CLI > config > defaults', () async {
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
      expect(content, contains('@freezed'));
    });

    test('uses values from config if CLI is not specified', () async {
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
      expect(content, contains('@JsonSerializable'));
    });

    test('applies schema overrides: className', () async {
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

    test('applies schema overrides: fieldNames', () async {
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
      expect(content, contains("json['user_id']"));
      expect(content, contains("json['user_name']"));
    });

    test('applies schema overrides: typeMapping', () async {
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

    test('returns empty configuration if file not found', () async {
      final tempDir = await Directory.systemTemp.createTemp('dart_swagger_to_models_no_config_');
      final config = await ConfigLoader.loadConfig(null, tempDir.path);

      expect(config.defaultStyle, isNull);
      expect(config.outputDir, isNull);
      expect(config.projectDir, isNull);
      expect(config.schemaOverrides, isEmpty);
    });

    test('loads configuration from specified path', () async {
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
}
