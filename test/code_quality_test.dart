import 'dart:convert';
import 'dart:io';

import 'package:dart_swagger_to_models/dart_swagger_to_models.dart';
import 'package:test/test.dart';

void main() {
  group('Generated code quality', () {
    test('supports x-enumNames for enum values', () async {
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
      expect(content.contains('Active') || content.contains('Inactive') || content.contains('Pending'), isTrue);
    });

    test('supports x-enum-varnames for enum values', () async {
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

    test('generates imports for dependencies between models', () async {
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
      expect(content, contains('final User user;'));
      expect(content, isNot(contains('final dynamic user;')));
      final hasImport = content.contains("import 'user.dart';") || 
                       content.contains("import './user.dart';") ||
                       content.contains("import 'user';");
      expect(hasImport, isTrue, reason: 'Should have import for User. Content: $content');
    });

    test('does not generate import for itself', () async {
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
      expect(content, isNot(contains("import 'user.dart';")));
      expect(content, contains('final User parent;'));
    });
  });
}
