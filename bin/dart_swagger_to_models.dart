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
      help: 'Path to Swagger/OpenAPI specification (file or URL).',
      valueHelp: 'swagger.yaml',
    )
    ..addOption(
      'output-dir',
      abbr: 'o',
      help: 'Directory for saving generated models.',
      valueHelp: 'lib/models',
    )
    ..addOption(
      'library-name',
      abbr: 'l',
      help: 'Library name (historical parameter, not used in per-file mode).',
      valueHelp: 'models',
      defaultsTo: 'models',
    )
    ..addOption(
      'style',
      abbr: 's',
      help: 'Model generation style: plain_dart, json_serializable, or freezed.',
      valueHelp: 'plain_dart',
      allowed: ['plain_dart', 'json_serializable', 'freezed'],
    )
    ..addOption(
      'project-dir',
      help: 'Project root directory for scanning Dart files (search for existing models).',
      valueHelp: '.',
      defaultsTo: '.',
    )
    ..addOption(
      'config',
      abbr: 'c',
      help: 'Path to configuration file (default: searches for dart_swagger_to_models.yaml in project root).',
      valueHelp: 'dart_swagger_to_models.yaml',
    )
    ..addFlag(
      'format',
      help: 'Run dart format for all generated files.',
      defaultsTo: false,
    )
    ..addFlag(
      'verbose',
      abbr: 'v',
      help: 'Verbose output (includes debug information).',
      defaultsTo: false,
    )
    ..addFlag(
      'quiet',
      abbr: 'q',
      help: 'Quiet output (only errors and critical messages).',
      defaultsTo: false,
    )
    ..addFlag(
      'changed-only',
      help: 'Incremental generation: regenerate only changed schemas.',
      defaultsTo: false,
    )
    ..addFlag(
      'help',
      abbr: 'h',
      negatable: false,
      help: 'Show help.',
    );

  ArgResults argResults;
  try {
    argResults = parser.parse(arguments);
  } on FormatException catch (e) {
    stderr.writeln('Argument error: ${e.message}');
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
    stderr.writeln('--input/-i is not specified.');
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
      Logger.verbose('Configuration loaded from ${configPath ?? 'dart_swagger_to_models.yaml'}');
    } catch (e) {
      Logger.warning('Failed to load configuration: $e');
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

    Logger.info('Loading specification from: $input');
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
      Logger.info('Formatting generated files...');
      for (final file in result.generatedFiles) {
        try {
          final process = await Process.run(
            'dart',
            ['format', file],
            runInShell: true,
          );
          if (process.exitCode != 0) {
            Logger.warning('Failed to format $file');
          } else {
            Logger.verbose('Formatted: $file');
          }
        } catch (e) {
          Logger.warning('Failed to run dart format for $file: $e');
        }
      }
    }

    // Print summary
    _printSummary(result);

    // Print warnings if any
    if (Logger.warnings.isNotEmpty && !isQuiet) {
      stdout.writeln();
      stdout.writeln('Warnings:');
      for (final warning in Logger.warnings) {
        stdout.writeln('  ⚠️  $warning');
      }
    }

    // Print errors if any
    if (Logger.errors.isNotEmpty) {
      stderr.writeln();
      stderr.writeln('Errors:');
      for (final error in Logger.errors) {
        stderr.writeln('  ❌ $error');
      }
      exitCode = 1;
    } else {
      Logger.success('Generation completed successfully!');
    }
  } catch (e, st) {
    Logger.error('Error generating models: $e');
    if (isVerbose) {
      stderr.writeln(st);
    }
    exitCode = 1;
  }
}

void _printSummary(GenerationResult result) {
  stdout.writeln();
  stdout.writeln('═══════════════════════════════════════');
  stdout.writeln('        Generation Summary');
  stdout.writeln('═══════════════════════════════════════');
  stdout.writeln('Schemas processed:      ${result.schemasProcessed}');
  stdout.writeln('Enums processed:        ${result.enumsProcessed}');
  stdout.writeln('Files created:          ${result.filesCreated}');
  stdout.writeln('Files updated:          ${result.filesUpdated}');
  stdout.writeln('Total files:            ${result.generatedFiles.length}');
  stdout.writeln('Output directory:       ${result.outputDirectory}');
  stdout.writeln('═══════════════════════════════════════');
}

void _printUsage(ArgParser parser) {
  stdout.writeln('dart_swagger_to_models — Generate Dart models from Swagger/OpenAPI');
  stdout.writeln();
  stdout.writeln('Usage:');
  stdout.writeln('  dart run dart_swagger_to_models:dart_swagger_to_models --input api.yaml');
  stdout.writeln();
  stdout.writeln('Options:');
  stdout.writeln(parser.usage);
}
