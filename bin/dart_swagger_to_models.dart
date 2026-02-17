import 'dart:io';

import 'package:args/args.dart';
import 'package:dart_swagger_to_models/dart_swagger_to_models.dart';
import 'package:dart_swagger_to_models/src/config/config_loader.dart';
import 'package:dart_swagger_to_models/src/core/logger.dart';

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
      'format',
      help: 'Запустить dart format для всех сгенерированных файлов.',
      defaultsTo: false,
    )
    ..addFlag(
      'verbose',
      abbr: 'v',
      help: 'Подробный вывод (включает отладочную информацию).',
      defaultsTo: false,
    )
    ..addFlag(
      'quiet',
      abbr: 'q',
      help: 'Минимальный вывод (только ошибки и критичные сообщения).',
      defaultsTo: false,
    )
    ..addFlag(
      'changed-only',
      help: 'Инкрементальная генерация: перегенерировать только изменённые схемы.',
      defaultsTo: false,
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
  final shouldFormat = argResults['format'] as bool;
  final isVerbose = argResults['verbose'] as bool;
  final isQuiet = argResults['quiet'] as bool;
  final changedOnly = argResults['changed-only'] as bool;

  // Set logging level
  if (isQuiet) {
    Logger.setLevel(LogLevel.quiet);
  } else if (isVerbose) {
    Logger.setLevel(LogLevel.verbose);
  } else {
    Logger.setLevel(LogLevel.normal);
  }

  GenerationStyle? style;
  String? customStyleName;
  if (styleName != null) {
    // Try to parse as built-in style
    switch (styleName.toLowerCase()) {
      case 'plain_dart':
        style = GenerationStyle.plainDart;
        break;
      case 'json_serializable':
        style = GenerationStyle.jsonSerializable;
        break;
      case 'freezed':
        style = GenerationStyle.freezed;
        break;
      default:
        // If not built-in style, consider it custom
        customStyleName = styleName;
        break;
    }
  }

  if (input == null || input.isEmpty) {
    stderr.writeln('Не указан --input/-i.');
    stderr.writeln();
    _printUsage(parser);
    exitCode = 64;
    return;
  }

  try {
    // Load configuration if present
    Config? config;
    try {
      config = await ConfigLoader.loadConfig(configPath, projectDir);
      Logger.verbose('Конфигурация загружена из ${configPath ?? 'dart_swagger_to_models.yaml'}');
    } catch (e) {
      Logger.warning('Не удалось загрузить конфигурацию: $e');
      // Continue without configuration
    }

    // If custom style is specified via CLI, add it to config
    if (customStyleName != null) {
      if (config != null) {
        config = Config(
          defaultStyle: config.defaultStyle,
          customStyleName: customStyleName, // CLI has priority
          outputDir: config.outputDir,
          projectDir: config.projectDir,
          useJsonKey: config.useJsonKey,
          lint: config.lint,
          schemaOverrides: config.schemaOverrides,
        );
      } else {
        // If no config, create new one with custom style
        config = Config(
          customStyleName: customStyleName,
        );
      }
    }

    Logger.info('Загрузка спецификации из: $input');
    final result = await SwaggerToDartGenerator.generateModels(
      input: input,
      outputDir: outputDir,
      libraryName: libraryName,
      style: style,
      projectDir: projectDir,
      config: config,
      changedOnly: changedOnly,
    );

    // Format files if --format flag is specified
    if (shouldFormat) {
      Logger.info('Форматирование сгенерированных файлов...');
      for (final file in result.generatedFiles) {
        try {
          final process = await Process.run(
            'dart',
            ['format', file],
            runInShell: true,
          );
          if (process.exitCode != 0) {
            Logger.warning('Не удалось отформатировать $file');
          } else {
            Logger.verbose('Отформатирован: $file');
          }
        } catch (e) {
          Logger.warning('Не удалось запустить dart format для $file: $e');
        }
      }
    }

    // Print summary
    _printSummary(result);

    // Print warnings if any
    if (Logger.warnings.isNotEmpty && !isQuiet) {
      stdout.writeln();
      stdout.writeln('Предупреждения:');
      for (final warning in Logger.warnings) {
        stdout.writeln('  ⚠️  $warning');
      }
    }

    // Print errors if any
    if (Logger.errors.isNotEmpty) {
      stderr.writeln();
      stderr.writeln('Ошибки:');
      for (final error in Logger.errors) {
        stderr.writeln('  ❌ $error');
      }
      exitCode = 1;
    } else {
      Logger.success('Генерация завершена успешно!');
    }
  } catch (e, st) {
    Logger.error('Ошибка генерации моделей: $e');
    if (isVerbose) {
      stderr.writeln(st);
    }
    exitCode = 1;
  }
}

void _printSummary(GenerationResult result) {
  stdout.writeln();
  stdout.writeln('═══════════════════════════════════════');
  stdout.writeln('           Сводка генерации');
  stdout.writeln('═══════════════════════════════════════');
  stdout.writeln('Обработано схем:        ${result.schemasProcessed}');
  stdout.writeln('Обработано enum\'ов:     ${result.enumsProcessed}');
  stdout.writeln('Создано файлов:         ${result.filesCreated}');
  stdout.writeln('Обновлено файлов:       ${result.filesUpdated}');
  stdout.writeln('Всего файлов:           ${result.generatedFiles.length}');
  stdout.writeln('Выходная директория:    ${result.outputDirectory}');
  stdout.writeln('═══════════════════════════════════════');
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
