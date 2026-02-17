import 'dart:convert';
import 'dart:io';

import 'package:dart_swagger_to_models/dart_swagger_to_models.dart';
import 'package:dart_swagger_to_models/src/config/config.dart';
import 'package:dart_swagger_to_models/src/config/config_loader.dart';
import 'package:dart_swagger_to_models/src/generators/plain_dart_generator.dart';
import 'package:dart_swagger_to_models/src/generators/style_registry.dart';
import 'package:test/test.dart';

void main() {
  group('Pluggable styles (0.3.1)', () {
    test('can register and use custom style', () async {
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

      StyleRegistry.register('test_style', () => PlainDartGenerator());

      try {
        await SwaggerToDartGenerator.generateModels(
          input: specFile.path,
          outputDir: '${tempDir.path}/models',
          projectDir: tempDir.path,
        );

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

    test('throws error when using unregistered style', () async {
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
          contains('not registered'),
        )),
      );
    });

    test('supports custom style via CLI', () async {
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

      StyleRegistry.register('cli_test_style', () => PlainDartGenerator());

      try {
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

    test('supports custom style via config file', () async {
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

      await configFile.writeAsString('''
defaultStyle: config_test_style
''');

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
