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

  if (input == null || input.isEmpty) {
    stderr.writeln('Не указан --input/-i.');
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
