import 'dart:io';

import 'package:args/args.dart';
import 'package:dart_swagger_to_models/dart_swagger_to_models.dart';

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
      defaultsTo: 'lib/models',
    )
    ..addOption(
      'library-name',
      abbr: 'l',
      help: 'Имя библиотеки (имя файла без .dart).',
      valueHelp: 'models',
      defaultsTo: 'models',
    )
    ..addOption(
      'style',
      abbr: 's',
      help: 'Стиль генерации моделей: plain_dart, json_serializable или freezed.',
      valueHelp: 'plain_dart',
      allowed: ['plain_dart', 'json_serializable', 'freezed'],
      defaultsTo: 'plain_dart',
    )
    ..addFlag(
      'per-file',
      help: 'Режим генерации: одна модель = один файл (режим 2.2).',
      defaultsTo: false,
    )
    ..addOption(
      'project-dir',
      help: 'Корневая директория проекта для сканирования Dart файлов (используется с --per-file).',
      valueHelp: '.',
      defaultsTo: '.',
    )
    ..addOption(
      'endpoint',
      help: 'Адрес endpoint для маркера /*SWAGGER-TO-DART:{endpoint}*/ (используется с --per-file).',
      valueHelp: 'api.example.com',
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
  final outputDir = argResults['output-dir'] as String;
  final libraryName = argResults['library-name'] as String;
  final styleName = argResults['style'] as String;
  final perFile = argResults['per-file'] as bool;
  final projectDir = argResults['project-dir'] as String;
  final endpoint = argResults['endpoint'] as String?;

  final style = switch (styleName) {
    'json_serializable' => GenerationStyle.jsonSerializable,
    'freezed' => GenerationStyle.freezed,
    _ => GenerationStyle.plainDart,
  };

  if (input == null || input.isEmpty) {
    stderr.writeln('Не указан --input/-i.');
    stderr.writeln();
    _printUsage(parser);
    exitCode = 64;
    return;
  }

  if (perFile && endpoint == null) {
    stderr.writeln('При использовании --per-file необходимо указать --endpoint.');
    stderr.writeln();
    _printUsage(parser);
    exitCode = 64;
    return;
  }

  try {
    final result = await SwaggerToDartGenerator.generateModels(
      input: input,
      outputDir: outputDir,
      libraryName: libraryName,
      style: style,
      perFile: perFile,
      projectDir: perFile ? projectDir : null,
      endpoint: perFile ? endpoint! : null,
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
  stdout.writeln('  dart run bin/dart_swagger_to_models.dart --input api.yaml');
  stdout.writeln();
  stdout.writeln('Опции:');
  stdout.writeln(parser.usage);
}
