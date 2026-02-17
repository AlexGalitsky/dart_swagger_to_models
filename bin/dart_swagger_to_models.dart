import 'dart:io';

import 'package:args/args.dart';
import 'package:dart_swagger_to_models/dart_swagger_to_models.dart';
import 'package:dart_swagger_to_models/src/config/config_loader.dart';

void main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption(
      'input',
      abbr: 'i',
      help: 'Путь к Swagger/OpenAPI спецификации (файл или URL).',
      valueHelp: 'swagger.yaml',
    )
    ..addOption(
      'output-dir',
      abbr: 'o',
      help: 'Директория для сохранения сгенерированных моделей.',
      valueHelp: 'lib/models',
    )
    ..addOption(
      'library-name',
      abbr: 'l',
      help: 'Имя библиотеки (исторический параметр, в per-file режиме практически не используется).',
      valueHelp: 'models',
      defaultsTo: 'models',
    )
    ..addOption(
      'style',
      abbr: 's',
      help: 'Стиль генерации моделей: plain_dart, json_serializable или freezed.',
      valueHelp: 'plain_dart',
      allowed: ['plain_dart', 'json_serializable', 'freezed'],
    )
    ..addOption(
      'project-dir',
      help: 'Корневая директория проекта для сканирования Dart файлов (поиск существующих моделей).',
      valueHelp: '.',
      defaultsTo: '.',
    )
    ..addOption(
      'config',
      abbr: 'c',
      help: 'Путь к конфигурационному файлу (по умолчанию ищется dart_swagger_to_models.yaml в корне проекта).',
      valueHelp: 'dart_swagger_to_models.yaml',
    )
    ..addFlag(
      'help',
      abbr: 'h',
      negatable: false,
      help: 'Показать справку.',
    );

  ArgResults argResults;
  try {
    argResults = parser.parse(arguments);
  } on FormatException catch (e) {
    stderr.writeln('Ошибка в аргументах: ${e.message}');
    stderr.writeln();
    _printUsage(parser);
    exitCode = 64; // EX_USAGE
    return;
  }

  if (argResults['help'] == true) {
    _printUsage(parser);
    return;
  }

  final input = argResults['input'] as String?;
  final outputDir = argResults['output-dir'] as String?;
  final libraryName = argResults['library-name'] as String;
  final styleName = argResults['style'] as String?;
  final projectDir = argResults['project-dir'] as String;
  final configPath = argResults['config'] as String?;

  GenerationStyle? style;
  if (styleName != null) {
    style = switch (styleName) {
      'json_serializable' => GenerationStyle.jsonSerializable,
      'freezed' => GenerationStyle.freezed,
      _ => GenerationStyle.plainDart,
    };
  }

  if (input == null || input.isEmpty) {
    stderr.writeln('Не указан --input/-i.');
    stderr.writeln();
    _printUsage(parser);
    exitCode = 64;
    return;
  }

  try {
    // Загружаем конфигурацию, если она есть
    Config? config;
    try {
      config = await ConfigLoader.loadConfig(configPath, projectDir);
    } catch (e) {
      stderr.writeln('Предупреждение: не удалось загрузить конфигурацию: $e');
      // Продолжаем без конфигурации
    }

    final result = await SwaggerToDartGenerator.generateModels(
      input: input,
      outputDir: outputDir,
      libraryName: libraryName,
      style: style,
      projectDir: projectDir,
      config: config,
    );

    stdout.writeln('Генерация завершена успешно.');
    stdout.writeln('Директория: ${result.outputDirectory}');
    for (final file in result.generatedFiles) {
      stdout.writeln('  - $file');
    }
  } catch (e, st) {
    stderr.writeln('Ошибка генерации моделей: $e');
    stderr.writeln(st);
    exitCode = 1;
  }
}

void _printUsage(ArgParser parser) {
  stdout.writeln('dart_swagger_to_models — генерация Dart-моделей из Swagger/OpenAPI');
  stdout.writeln();
  stdout.writeln('Использование:');
  stdout.writeln('  dart run dart_swagger_to_models:dart_swagger_to_models --input api.yaml');
  stdout.writeln();
  stdout.writeln('Опции:');
  stdout.writeln(parser.usage);
}
