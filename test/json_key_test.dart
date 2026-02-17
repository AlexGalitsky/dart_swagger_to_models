import 'dart:convert';
import 'dart:io';

import 'package:dart_swagger_to_models/dart_swagger_to_models.dart';
import 'package:dart_swagger_to_models/src/config/config_loader.dart';
import 'package:test/test.dart';

void main() {
  group('Better ergonomics for json_serializable / freezed', () {
    test('generates @JsonKey for snake_case JSON keys in json_serializable',
        () async {
      final tempDir = await Directory.systemTemp
          .createTemp('dart_swagger_to_models_jsonkey_');
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
              'email': {'type': 'string'},
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

      final userFile =
          result.generatedFiles.firstWhere((f) => f.contains('user.dart'));
      final content = await File(userFile).readAsString();
      expect(content, contains("@JsonKey(name: 'user_id')"));
      expect(content, contains("@JsonKey(name: 'user_name')"));
      expect(content, isNot(contains("@JsonKey(name: 'email')")));
      expect(content, contains('final int userId;'));
      expect(content, contains('final String userName;'));
      expect(content, contains('final String email;'));
    });

    test('generates @JsonKey for snake_case JSON keys in freezed', () async {
      final tempDir = await Directory.systemTemp
          .createTemp('dart_swagger_to_models_jsonkey_freezed_');
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

      final userFile =
          result.generatedFiles.firstWhere((f) => f.contains('user.dart'));
      final content = await File(userFile).readAsString();
      expect(content, contains("@JsonKey(name: 'user_id')"));
      expect(content, contains("@JsonKey(name: 'user_name')"));
      expect(content, contains('required int userId,'));
      expect(content, contains('required String userName,'));
    });

    test('does not generate @JsonKey if useJsonKey: false', () async {
      final tempDir = await Directory.systemTemp
          .createTemp('dart_swagger_to_models_no_jsonkey_');
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

      final userFile =
          result.generatedFiles.firstWhere((f) => f.contains('user.dart'));
      final content = await File(userFile).readAsString();
      expect(content, isNot(contains("@JsonKey(name: 'user_id')")));
      expect(content, contains('final int userId;'));
    });

    test('useJsonKey override at schema level', () async {
      final tempDir = await Directory.systemTemp
          .createTemp('dart_swagger_to_models_jsonkey_override_');
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

      final userFile =
          result.generatedFiles.firstWhere((f) => f.contains('user.dart'));
      final orderFile =
          result.generatedFiles.firstWhere((f) => f.contains('order.dart'));

      final userContent = await File(userFile).readAsString();
      final orderContent = await File(orderFile).readAsString();

      expect(userContent, contains("@JsonKey(name: 'user_id')"));
      expect(orderContent, isNot(contains("@JsonKey(name: 'order_id')")));
    });
  });
}
