import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'src/config/config.dart';
import 'src/core/cache.dart';
import 'src/core/lint_rules.dart';
import 'src/core/logger.dart';
import 'src/core/types.dart';
import 'src/generators/class_generator_strategy.dart';
import 'src/generators/generator_factory.dart';

export 'src/config/config.dart' show Config, SchemaOverride;
export 'src/core/types.dart'
    show SpecVersion, GenerationStyle, GenerationResult, GenerationContext;
export 'src/generators/class_generator_strategy.dart' show ClassGeneratorStrategy, FieldInfo;
export 'src/generators/style_registry.dart' show StyleRegistry;
// Builder is exported separately to avoid loading dart:mirrors during normal use.
// To use the Builder, import: import 'package:dart_swagger_to_models/src/build/swagger_builder.dart';

/// Main library facade.
class SwaggerToDartGenerator {
  /// Loads specification from a local file or URL.
  static Future<Map<String, dynamic>> loadSpec(String source) async {
    if (source.startsWith('http://') || source.startsWith('https://')) {
      final response = await http.get(Uri.parse(source));
      if (response.statusCode >= 400) {
      throw Exception(
        'Failed to load specification from URL $source '
        '(status: ${response.statusCode})',
      );
      }
      return _decodeSpec(response.body, sourceHint: source);
    }

    final file = File(source);
    if (!await file.exists()) {
      throw Exception('Specification file not found: $source');
    }
    final content = await file.readAsString();
    return _decodeSpec(content, sourceHint: source);
  }

  static Map<String, dynamic> _decodeSpec(
    String content, {
    required String sourceHint,
  }) {
    final lower = sourceHint.toLowerCase();
    final isYaml = lower.endsWith('.yaml') || lower.endsWith('.yml');

    if (isYaml) {
      final yamlDoc = loadYaml(content);
      return jsonDecode(jsonEncode(yamlDoc)) as Map<String, dynamic>;
    }

    return jsonDecode(content) as Map<String, dynamic>;
  }

  /// Detects the specification version.
  static SpecVersion detectVersion(Map<String, dynamic> spec) {
    if (spec.containsKey('swagger')) {
      return SpecVersion.swagger2;
    }
    if (spec.containsKey('openapi')) {
      return SpecVersion.openApi3;
    }
    throw Exception('Failed to detect specification version (swagger/openapi).');
  }

  /// Generates Dart models: one model = one file.
  ///
  /// [input] - path to file or URL of the specification.
  /// [outputDir] - directory where models will be written (default: `lib/models`).
  /// [libraryName] - historical parameter (not used in per-file mode).
  /// [style] - model generation style (plain_dart/json_serializable/freezed).
  /// [projectDir] - project root directory for scanning Dart files
  ///                (search for existing model files with markers).
  /// [config] - generator configuration (optional).
  /// [changedOnly] - if true, generates only changed schemas (incremental generation).
  static Future<GenerationResult> generateModels({
    required String input,
    String? outputDir,
    String libraryName = 'models',
    GenerationStyle? style,
    String? projectDir,
    Config? config,
    bool changedOnly = false,
  }) async {
    // Apply configuration with priority: parameters > config > default values
    final effectiveConfig = config ?? Config.empty();
    final effectiveOutputDir = outputDir ?? effectiveConfig.outputDir ?? 'lib/models';
    // If custom style is specified in config, use it; otherwise use defaultStyle or passed style
    final effectiveStyle = effectiveConfig.customStyleName != null
        ? null // Custom style will be used via config.customStyleName
        : (style ?? effectiveConfig.defaultStyle ?? GenerationStyle.plainDart);
    final effectiveProjectDir = projectDir ?? effectiveConfig.projectDir ?? '.';

    final spec = await loadSpec(input);
    final version = detectVersion(spec);
    final schemas = _extractSchemas(spec, version);

    if (schemas.isEmpty) {
      throw Exception(
        'No schemas found in specification (definitions/components.schemas).',
      );
    }

    // For resolveRef to work correctly, we need to pass all schemas
    // For Swagger 2.0 this is definitions, for OpenAPI 3 this is components.schemas
    final allSchemasMap = _getAllSchemas(spec, version);
    // For resolveRef we need to structure schemas correctly
    final schemasForContext = version == SpecVersion.swagger2
        ? <String, dynamic>{
            'definitions': allSchemasMap,
          }
        : <String, dynamic>{
            'components': <String, dynamic>{
              'schemas': allSchemasMap,
            },
          };

    final context = GenerationContext(
      allSchemas: schemasForContext,
      version: version,
    );

    return _generateModelsPerFile(
      schemas: schemas,
      context: context,
      style: effectiveStyle,
      outputDir: effectiveOutputDir,
      projectDir: effectiveProjectDir,
      config: effectiveConfig,
      changedOnly: changedOnly,
    );
  }

  /// Generates models in per-file mode (one model = one file).
  static Future<GenerationResult> _generateModelsPerFile({
    required Map<String, dynamic> schemas,
    required GenerationContext context,
    required String outputDir,
    required String projectDir,
    GenerationStyle? style,
    Config? config,
    bool changedOnly = false,
  }) async {
    Logger.clear();
    Logger.verbose('Начало генерации моделей');
    Logger.verbose('Стиль: $style');
    Logger.verbose('Выходная директория: $outputDir');
    if (changedOnly) {
      Logger.verbose('Режим инкрементальной генерации: только изменённые схемы');
    }

    final generatedFiles = <String>[];
    final outDir = Directory(outputDir);
    if (!await outDir.exists()) {
      Logger.verbose('Создание выходной директории: $outputDir');
      await outDir.create(recursive: true);
    }

    // Load cache for incremental generation
    final cache = await GenerationCache.load(projectDir);
    final schemasToProcess = <String, Map<String, dynamic>>{};

    if (changedOnly && cache != null) {
      // Determine which schemas have changed
      for (final entry in schemas.entries) {
        final schemaMap = <String, dynamic>{
          ...?entry.value as Map<String, dynamic>?,
        };
        if (cache.hasChanged(entry.key, schemaMap)) {
          schemasToProcess[entry.key] = schemaMap;
          Logger.verbose('Схема "${entry.key}" изменилась, будет перегенерирована');
        } else {
          Logger.verbose('Схема "${entry.key}" не изменилась, пропускаем');
        }
      }

      // Check for deleted schemas
      final currentSchemaNames = schemas.keys.toSet();
      final cachedSchemaNames = cache.cachedSchemas;
      final deletedSchemas = cachedSchemaNames.difference(currentSchemaNames);
      
      if (deletedSchemas.isNotEmpty) {
        Logger.verbose('Обнаружены удалённые схемы: ${deletedSchemas.join(", ")}');
        for (final deletedSchema in deletedSchemas) {
          cache.removeHash(deletedSchema);
          // Delete file if it exists
          final fileName = _toSnakeCase(deletedSchema);
          final filePath = p.join(outputDir, '$fileName.dart');
          final file = File(filePath);
          if (await file.exists()) {
            await file.delete();
            Logger.verbose('Удалён файл для удалённой схемы: $fileName.dart');
          }
        }
      }
    } else {
      // Full generation mode
      schemasToProcess.addAll(schemas.map((k, v) => MapEntry(
            k,
            <String, dynamic>{
              ...?v as Map<String, dynamic>?,
            },
          )));
    }

    // Scan project for existing files with markers
    Logger.verbose('Сканирование проекта для поиска существующих файлов...');
    final existingFiles = await _scanProjectForMarkers(
      projectDir,
      outputDir,
    );
    Logger.verbose('Найдено существующих файлов: ${existingFiles.length}');

    // Check schemas for suspicious constructs (only for processed schemas)
    final lintConfig = config?.lint ?? LintConfig.defaultConfig();
    _validateSchemas(schemasToProcess, context, lintConfig);

    // First, generate enums
    final enumSchemas = <String, Map<String, dynamic>>{};
    schemasToProcess.forEach((name, schema) {
      final schemaMap = <String, dynamic>{
        ...?schema as Map<String, dynamic>?,
      };
      if (context.isEnum(schemaMap)) {
        enumSchemas[name] = schemaMap;
      }
    });

    Logger.verbose('Найдено enum схем: ${enumSchemas.length}');

    int filesCreated = 0;
    int filesUpdated = 0;

    // Generate enums into separate files
    for (final entry in enumSchemas.entries) {
      try {
        final override = config?.schemaOverrides[entry.key];
        final modelName = override?.className ?? _toPascalCase(entry.key);
        final fileName = _toSnakeCase(entry.key);
        final filePath = p.join(outputDir, '$fileName.dart');
        final existingContent = existingFiles[modelName];

        final fileContent = existingContent != null
            ? _updateExistingFileWithEnum(
                existingContent,
                entry.key,
                entry.value,
                context,
                style,
                config: config,
              )
            : _createNewFileWithEnum(
                entry.key,
                entry.value,
                context,
                style,
                fileName,
                config: config,
              );

        final file = File(filePath);
        await file.writeAsString(fileContent);
        generatedFiles.add(filePath);
        context.generatedEnums.add(modelName);

        if (existingContent != null) {
          filesUpdated++;
          Logger.verbose('Обновлён enum: $modelName');
        } else {
          filesCreated++;
          Logger.verbose('Создан enum: $modelName');
        }

        // Update cache
        if (cache != null) {
          final hash = GenerationCache.computeSchemaHash(entry.value);
          cache.setHash(entry.key, hash);
        }
      } catch (e) {
        Logger.error('Ошибка при генерации enum "${entry.key}": $e');
        rethrow;
      }
    }

    // Then generate classes into separate files
    final classSchemas = schemasToProcess.entries
        .where((e) {
          final schemaMap = <String, dynamic>{
            ...?e.value as Map<String, dynamic>?,
          };
          return !context.isEnum(schemaMap);
        })
        .length;
    Logger.verbose('Найдено схем классов: $classSchemas');

    for (final entry in schemasToProcess.entries) {
      final schemaMap = <String, dynamic>{
        ...?entry.value as Map<String, dynamic>?,
      };
      if (!context.isEnum(schemaMap)) {
        try {
          final override = config?.schemaOverrides[entry.key];
          final modelName = override?.className ?? _toPascalCase(entry.key);
          final fileName = _toSnakeCase(entry.key);
          final filePath = p.join(outputDir, '$fileName.dart');
          final existingContent = existingFiles[modelName];

          final fileContent = existingContent != null
              ? _updateExistingFileWithClass(
                  existingContent,
                  entry.key,
                  schemaMap,
                  context,
                  style,
                  outputDir,
                  config: config,
                  override: override,
                )
              : _createNewFileWithClass(
                  entry.key,
                  schemaMap,
                  context,
                  style,
                  fileName,
                  outputDir,
                  config: config,
                  override: override,
                );

          final file = File(filePath);
          await file.writeAsString(fileContent);
          generatedFiles.add(filePath);
          context.generatedClasses.add(modelName);

          if (existingContent != null) {
            filesUpdated++;
            Logger.verbose('Обновлён класс: $modelName');
          } else {
            filesCreated++;
            Logger.verbose('Создан класс: $modelName');
          }

          // Update cache
          if (cache != null) {
            final hash = GenerationCache.computeSchemaHash(schemaMap);
            cache.setHash(entry.key, hash);
          }
        } catch (e) {
          Logger.error('Ошибка при генерации класса "${entry.key}": $e');
          rethrow;
        }
      }
    }

    // Update cache for all schemas (even unchanged ones, if changedOnly = false)
    if (cache != null && !changedOnly) {
      for (final entry in schemas.entries) {
        final schemaMap = <String, dynamic>{
          ...?entry.value as Map<String, dynamic>?,
        };
        final hash = GenerationCache.computeSchemaHash(schemaMap);
        cache.setHash(entry.key, hash);
      }
    }

    // Save cache
    if (cache != null) {
      await cache.save();
      Logger.verbose('Кэш сохранён в ${cache.cacheFilePath}');
    }

    // Check for missing $ref after generation
    _checkMissingRefs(schemas, context, lintConfig);

    return GenerationResult(
      outputDirectory: outputDir,
      generatedFiles: generatedFiles,
      schemasProcessed: schemasToProcess.length,
      enumsProcessed: enumSchemas.length,
      filesCreated: filesCreated,
      filesUpdated: filesUpdated,
    );
  }

  /// Scans project for Dart files with markers.
  /// Returns Map<ModelName, FileContent>.
  static Future<Map<String, String>> _scanProjectForMarkers(
    String projectDir,
    String outputDir,
  ) async {
    final result = <String, String>{};
    // Support both formats: /*SWAGGER-TO-DART*/ and /*SWAGGER-TO-DART:...*/ for backward compatibility
    final markerPattern = RegExp(r'/\*SWAGGER-TO-DART(:[^*]*)?\*/');

    // First scan outputDir
    final outputDirectory = Directory(outputDir);
    if (await outputDirectory.exists()) {
      await for (final entity in outputDirectory.list(recursive: false)) {
        if (entity is File && entity.path.endsWith('.dart')) {
          try {
            final content = await entity.readAsString();
            final match = markerPattern.firstMatch(content);
            if (match != null) {
              final fileName = p.basenameWithoutExtension(entity.path);
              final modelName = _toPascalCase(fileName);
              result[modelName] = content;
            }
          } catch (_) {
            // Ignore file reading errors
          }
        }
      }
    }

    // Then scan projectDir (recursively)
    final projectDirectory = Directory(projectDir);
    if (await projectDirectory.exists()) {
      await for (final entity in projectDirectory.list(recursive: true)) {
        if (entity is File && entity.path.endsWith('.dart')) {
          // Skip files from outputDir, as we already checked them
          if (p.isWithin(outputDir, entity.path)) {
            continue;
          }
          try {
            final content = await entity.readAsString();
            final match = markerPattern.firstMatch(content);
            if (match != null) {
              final fileName = p.basenameWithoutExtension(entity.path);
              final modelName = _toPascalCase(fileName);
              // Don't overwrite if already exists in outputDir
              result.putIfAbsent(modelName, () => content);
            }
          } catch (_) {
            // Ignore file reading errors
          }
        }
      }
    }

    return result;
  }

  /// Creates a new file with enum.
  static String _createNewFileWithEnum(
    String enumName,
    Map<String, dynamic> schema,
    GenerationContext context,
    GenerationStyle? style,
    String fileName, {
    Config? config,
  }) {
    final buffer = StringBuffer();
    buffer.writeln('/*SWAGGER-TO-DART*/');
    buffer.writeln();

    // Add imports and parts depending on style
    // For enums imports are not needed, but we keep them for consistency
    final strategy = GeneratorFactory.createStrategy(style, customStyleName: config?.customStyleName);
    final imports = strategy.generateImportsAndParts(fileName);
    for (final import in imports) {
      buffer.writeln(import);
    }
    if (imports.isNotEmpty) {
      buffer.writeln();
    }

    buffer.writeln('/*SWAGGER-TO-DART: Codegen start*/');
    buffer.writeln();
    buffer.write(_generateEnum(enumName, schema, context));
    buffer.writeln();
    buffer.writeln('/*SWAGGER-TO-DART: Codegen stop*/');

    return buffer.toString();
  }

  /// Collects dependencies (types used in schema) for generating imports.
  static Set<String> _collectDependencies(
    Map<String, dynamic> schema,
    GenerationContext context,
    String currentSchemaName,
    String outputDir,
  ) {
    final dependencies = <String>{};
    final visited = <String>{};

    void collectFromSchema(Map<String, dynamic> schemaMap, String? parentName) {
      // Handle $ref
      final ref = schemaMap[r'$ref'] as String?;
      if (ref != null) {
        final refSchema = context.resolveRef(ref, context: parentName);
        if (refSchema != null) {
          final refName = ref.split('/').last;
          final refTypeName = _toPascalCase(refName);
          
          // Don't add dependency on self
          if (refTypeName != currentSchemaName && !visited.contains(refTypeName)) {
            visited.add(refTypeName);
            // Check that this is not a built-in type
            if (refSchema.containsKey('properties') || context.isEnum(refSchema)) {
              dependencies.add(refTypeName);
            }
            // Recursively collect dependencies from ref schema
            collectFromSchema(refSchema, refTypeName);
          }
        }
      }

      // Handle properties
      final properties = schemaMap['properties'] as Map<String, dynamic>?;
      if (properties != null) {
        properties.forEach((_, propSchema) {
          if (propSchema is Map<String, dynamic>) {
            collectFromSchema(propSchema, parentName);
          }
        });
      }

      // Handle items (for arrays)
      final items = schemaMap['items'] as Map<String, dynamic>?;
      if (items != null) {
        collectFromSchema(items, parentName);
      }

      // Handle additionalProperties
      final additionalProps = schemaMap['additionalProperties'];
      if (additionalProps is Map<String, dynamic>) {
        collectFromSchema(additionalProps, parentName);
      }

      // Handle allOf
      final allOf = schemaMap['allOf'] as List?;
      if (allOf != null) {
        for (final item in allOf) {
          if (item is Map<String, dynamic>) {
            collectFromSchema(item, parentName);
          }
        }
      }
    }

    collectFromSchema(schema, null);
    return dependencies;
  }

  /// Generates imports for dependencies.
  static List<String> _generateImportsForDependencies(
    Set<String> dependencies,
    String outputDir,
    String currentFileName,
  ) {
    final imports = <String>[];
    final currentFilePath = p.join(outputDir, currentFileName);
    final currentDir = p.dirname(currentFilePath);
    
    for (final dep in dependencies) {
      final depFileName = _toSnakeCase(dep);
      final depPath = p.join(outputDir, '$depFileName.dart');
      final relativePath = p.relative(depPath, from: currentDir);
      // Normalize path for import (use / instead of \)
      var importPath = relativePath.replaceAll(r'\', '/');
      // Remove .dart extension
      if (importPath.endsWith('.dart')) {
        importPath = importPath.substring(0, importPath.length - 5);
      }
      imports.add("import '$importPath';");
    }

    return imports..sort();
  }

  /// Creates a new file with class.
  static String _createNewFileWithClass(
    String className,
    Map<String, dynamic> schema,
    GenerationContext context,
    GenerationStyle? style,
    String fileName,
    String outputDir, {
    Config? config,
    SchemaOverride? override,
  }) {
    final buffer = StringBuffer();
    buffer.writeln('/*SWAGGER-TO-DART*/');
    buffer.writeln();

    // Collect dependencies for imports
    final schemaName = override?.className ?? _toPascalCase(className);
    final dependencies = _collectDependencies(schema, context, schemaName, outputDir);
    final modelImports = _generateImportsForDependencies(dependencies, outputDir, '$fileName.dart');

    // Add imports and parts depending on style
    final strategy = GeneratorFactory.createStrategy(style, customStyleName: config?.customStyleName);
    final styleImports = strategy.generateImportsAndParts(fileName);
    
    // Combine imports: first model imports, then style imports
    final allImports = <String>[...modelImports, ...styleImports];
    for (final import in allImports) {
      buffer.writeln(import);
    }
    if (allImports.isNotEmpty) {
      buffer.writeln();
    }

    buffer.writeln('/*SWAGGER-TO-DART: Codegen start*/');
    buffer.writeln();
    buffer.write(_generateClass(className, schema, context, style, config: config, override: override));
    buffer.writeln();
    buffer.writeln('/*SWAGGER-TO-DART: Codegen stop*/');

    return buffer.toString();
  }

  /// Updates existing file with enum, replacing content between markers.
  static String _updateExistingFileWithEnum(
    String existingContent,
    String enumName,
    Map<String, dynamic> schema,
    GenerationContext context,
    GenerationStyle? style, {
    Config? config,
  }) {
    final startMarker = '/*SWAGGER-TO-DART: Codegen start*/';
    final stopMarker = '/*SWAGGER-TO-DART: Codegen stop*/';

    final startIndex = existingContent.indexOf(startMarker);
    final stopIndex = existingContent.indexOf(stopMarker);

    if (startIndex == -1 || stopIndex == -1 || startIndex >= stopIndex) {
      // Markers not found, create new file
      return _createNewFileWithEnum(
        enumName,
        schema,
        context,
        style,
        _toSnakeCase(enumName),
        config: config,
      );
    }

    final before = existingContent.substring(0, startIndex + startMarker.length);
    final after = existingContent.substring(stopIndex);
    final newEnumCode = _generateEnum(enumName, schema, context);

    return '$before\n$newEnumCode\n$after';
  }

  /// Updates existing file with class, replacing content between markers.
  static String _updateExistingFileWithClass(
    String existingContent,
    String className,
    Map<String, dynamic> schema,
    GenerationContext context,
    GenerationStyle? style,
    String outputDir, {
    Config? config,
    SchemaOverride? override,
  }) {
    final startMarker = '/*SWAGGER-TO-DART: Codegen start*/';
    final stopMarker = '/*SWAGGER-TO-DART: Codegen stop*/';

    final startIndex = existingContent.indexOf(startMarker);
    final stopIndex = existingContent.indexOf(stopMarker);

    if (startIndex == -1 || stopIndex == -1 || startIndex >= stopIndex) {
      // Markers not found, create new file
      return _createNewFileWithClass(
        className,
        schema,
        context,
        style,
        _toSnakeCase(className),
        outputDir,
        config: config,
        override: override,
      );
    }

    final before = existingContent.substring(0, startIndex + startMarker.length);
    final after = existingContent.substring(stopIndex);
    final newClassCode = _generateClass(className, schema, context, style, config: config, override: override);

    return '$before\n$newClassCode\n$after';
  }

  /// Converts name to snake_case for file name.
  static String _toSnakeCase(String name) {
    final pascal = _toPascalCase(name);
    if (pascal.isEmpty) return '';
    final buffer = StringBuffer();
    for (var i = 0; i < pascal.length; i++) {
      final char = pascal[i];
      if (char == char.toUpperCase() && i > 0) {
        buffer.write('_');
      }
      buffer.write(char.toLowerCase());
    }
    return buffer.toString();
  }

  static Map<String, dynamic> _getAllSchemas(
    Map<String, dynamic> spec,
    SpecVersion version,
  ) {
    final result = <String, dynamic>{};
    final schemas = _extractSchemas(spec, version);
    result.addAll(schemas);

    // For OpenAPI 3 also add components
    if (version == SpecVersion.openApi3) {
      final components = spec['components'] as Map<String, dynamic>?;
      if (components != null) {
        result.addAll(components);
      }
    }

    return result;
  }

  static Map<String, dynamic> _extractSchemas(
    Map<String, dynamic> spec,
    SpecVersion version,
  ) {
    switch (version) {
      case SpecVersion.swagger2:
        final definitions = spec['definitions'];
        if (definitions is Map<String, dynamic>) {
          return definitions;
        }
        return <String, dynamic>{};
      case SpecVersion.openApi3:
        final components = spec['components'];
        if (components is Map<String, dynamic>) {
          final schemas = components['schemas'];
          if (schemas is Map<String, dynamic>) {
            return schemas;
          }
        }
        return <String, dynamic>{};
    }
  }

  static String _generateEnum(
    String name,
    Map<String, dynamic> schema,
    GenerationContext context,
  ) {
    final enumName = _toPascalCase(name);
    final enumValues = schema['enum'] as List?;
    if (enumValues == null || enumValues.isEmpty) return '';

    // Support x-enumNames / x-enum-varnames
    final enumNames = schema['x-enumNames'] as List? ?? schema['x-enum-varnames'] as List?;
    final hasCustomNames = enumNames != null && enumNames.length == enumValues.length;

    final buffer = StringBuffer()
      ..writeln('enum $enumName {');

    for (var i = 0; i < enumValues.length; i++) {
      final value = enumValues[i];
      String enumValue;
      
      if (hasCustomNames && enumNames[i] is String) {
        // Use custom name from x-enumNames / x-enum-varnames
        enumValue = _toEnumValueName(enumNames[i] as String);
      } else if (value is String) {
        // Convert string to valid enum value name
        enumValue = _toEnumValueName(value);
      } else {
        enumValue = 'value$i';
      }

      buffer.write('  $enumValue');
      if (i < enumValues.length - 1) {
        buffer.writeln(',');
      } else {
        buffer.writeln(';');
      }
    }

    buffer
      ..writeln()
      ..writeln('  const $enumName(this.value);')
      ..writeln()
      ..writeln('  final dynamic value;')
      ..writeln()
      ..writeln('  static $enumName? fromJson(dynamic json) {')
      ..writeln('    if (json == null) return null;')
      ..writeln('    for (final value in $enumName.values) {')
      ..writeln('      if (value.value == json) return value;')
      ..writeln('    }')
      ..writeln('    return null;')
      ..writeln('  }')
      ..writeln()
      ..writeln('  dynamic toJson() => value;')
      ..writeln('}');

    return buffer.toString();
  }

  static String _toEnumValueName(String value) {
    // Convert string to valid enum value name
    final cleaned = value
        .replaceAll(RegExp(r'[^A-Za-z0-9_]'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .trim();
    if (cleaned.isEmpty) return 'unknown';
    if (RegExp(r'^[0-9]').hasMatch(cleaned)) {
      return 'value_$cleaned';
    }
    return cleaned;
  }

  static String _generateClass(
    String name,
    Map<String, dynamic> schema,
    GenerationContext context,
    GenerationStyle? style, {
    Config? config,
    SchemaOverride? override,
  }) {
    // Handle allOf (OpenAPI 3)
    if (schema.containsKey('allOf') && schema['allOf'] is List) {
      return _generateAllOfClass(name, schema, context, style, config: config, override: override);
    }

    // Handle oneOf/anyOf (OpenAPI 3)
    final oneOf = schema['oneOf'] as List?;
    final anyOf = schema['anyOf'] as List?;
    if (oneOf != null || anyOf != null) {
      return _generateOneOfClass(
        name,
        schema,
        context,
        oneOf: oneOf,
        anyOf: anyOf,
        override: override,
      );
    }

    final className = override?.className ?? _toPascalCase(name);
    final properties = schema['properties'] as Map<String, dynamic>? ?? {};
    final additionalProps = schema['additionalProperties'];

    // If object only has additionalProperties and no properties — generate
    // the same for all styles.
    if (properties.isEmpty && additionalProps != null && additionalProps != false) {
      final valueType = additionalProps is Map<String, dynamic>
          ? _dartTypeForSchema(additionalProps, context, required: true)
          : 'dynamic';
      final classBuffer = StringBuffer()
        ..writeln('class $className {')
        ..writeln('  final Map<String, $valueType>? data;')
        ..writeln()
        ..writeln('  const $className({this.data});')
        ..writeln()
        ..writeln('  factory $className.fromJson(Map<String, dynamic> json) {')
        ..writeln('    return $className(');
      if (additionalProps is Map<String, dynamic>) {
        final valueExpr = _fromJsonExpression('v', additionalProps, context, isRequired: true);
        classBuffer.writeln('      data: json.map((k, v) => MapEntry(k, $valueExpr)),');
      } else {
        classBuffer.writeln(
          '      data: (json as Map<String, dynamic>).map((k, v) => MapEntry(k, v)),',
        );
      }
      classBuffer
        ..writeln('    );')
        ..writeln('  }')
        ..writeln()
        ..writeln('  Map<String, dynamic> toJson() {')
        ..writeln('    return data ?? <String, $valueType>{};')
        ..writeln('  }')
        ..writeln('}');
      return classBuffer.toString();
    }

    // General field information
    final fieldInfos = <String, FieldInfo>{};

    properties.forEach((propName, propSchemaRaw) {
      final propSchema = <String, dynamic>{
        ...?propSchemaRaw as Map<String, dynamic>?,
      };
      final propNullable = propSchema['nullable'] as bool? ?? false;

      // Nullable / required rule:
      // - If field is present in schema, it is considered required by default.
      // - If field explicitly has nullable: true, it is generated as nullable.
      final isNonNullable = !propNullable;

      // Apply field name override if present
      final fieldName = override?.fieldNames?[propName] ?? propName;

      // Apply type mapping if present
      String dartType;
      if (override?.typeMapping != null && override!.typeMapping!.isNotEmpty) {
        final typeFromSchema = propSchema['type'] as String?;
        if (typeFromSchema != null && override.typeMapping!.containsKey(typeFromSchema)) {
          dartType = override.typeMapping![typeFromSchema]!;
          if (!isNonNullable) {
            dartType = '$dartType?';
          }
        } else {
          dartType = _dartTypeForSchema(propSchema, context, required: isNonNullable);
        }
      } else {
        dartType = _dartTypeForSchema(propSchema, context, required: isNonNullable);
      }

      fieldInfos[propName] = FieldInfo(
        name: fieldName,
        jsonKey: propName, // Original JSON key
        dartType: dartType,
        isRequired: isNonNullable,
        schema: propSchema,
      );
    });

    // Determine if @JsonKey should be used
    // Priority: override.useJsonKey > config.useJsonKey > false
    final useJsonKey = override?.useJsonKey ?? config?.useJsonKey ?? false;

    // Use strategy for class generation
    final strategy = GeneratorFactory.createStrategy(style, customStyleName: config?.customStyleName);
    return strategy.generateFullClass(
      className,
      fieldInfos,
      (jsonKey, schema) {
        // Determine if field is required based on FieldInfo
        final fieldInfo = fieldInfos[jsonKey];
        final isRequired = fieldInfo?.isRequired ?? false;
        return _fromJsonExpression('json[\'$jsonKey\']', schema, context, isRequired: isRequired);
      },
      (fieldName, schema) => _toJsonExpression(fieldName, schema, context),
      useJsonKey: useJsonKey,
    );
  }

  /// Generates class for allOf schema.
  /// 
  /// Handles nested allOf combinations and multiple inheritance cases.
  static String _generateAllOfClass(
    String name,
    Map<String, dynamic> schema,
    GenerationContext context,
    GenerationStyle? style, {
    Config? config,
    SchemaOverride? override,
  }) {
    final allOf = schema['allOf'] as List;
    Logger.verbose('Обработка allOf для схемы "$name" (${allOf.length} элементов)');

    final allProperties = <String, dynamic>{};
    final allRequired = <String>[];
    final processedRefs = <String>{}; // To prevent circular dependencies

    // Recursive function to process allOf items
    void processAllOfItem(dynamic item, String? parentName) {
      if (item is! Map<String, dynamic>) return;

      // Handle $ref
      if (item.containsKey(r'$ref')) {
        final ref = item[r'$ref'] as String;
        
        // Check for circular dependencies
        if (processedRefs.contains(ref)) {
          Logger.warning(
            'Обнаружена циклическая зависимость для $ref в схеме "$name". '
            'Пропускаем повторную обработку.',
          );
          return;
        }
        processedRefs.add(ref);

        final refSchema = context.resolveRef(ref, context: parentName ?? name);
        if (refSchema == null) {
          Logger.warning(
            'Не удалось разрешить ссылку $ref в allOf схемы "$name". '
            'Пропускаем этот элемент.',
          );
          processedRefs.remove(ref);
          return;
        }

        // Recursively process nested allOf
        if (refSchema.containsKey('allOf')) {
          final refAllOf = refSchema['allOf'] as List;
          Logger.verbose('Обнаружен вложенный allOf в $ref (${refAllOf.length} элементов)');
          for (final refItem in refAllOf) {
            processAllOfItem(refItem, ref.split('/').last);
          }
        } else {
          // Process properties from ref schema
          final props = refSchema['properties'] as Map<String, dynamic>? ?? {};
          allProperties.addAll(props);
          final req = (refSchema['required'] as List?)?.cast<String>() ?? <String>[];
          allRequired.addAll(req);
        }

        processedRefs.remove(ref);
      } else {
        // Handle regular properties
        final props = item['properties'] as Map<String, dynamic>? ?? {};
        allProperties.addAll(props);
        final req = (item['required'] as List?)?.cast<String>() ?? <String>[];
        allRequired.addAll(req);

        // If item itself contains allOf, process recursively
        if (item.containsKey('allOf')) {
          final nestedAllOf = item['allOf'] as List;
          Logger.verbose('Обнаружен вложенный allOf в элементе схемы "$name" (${nestedAllOf.length} элементов)');
          for (final nestedItem in nestedAllOf) {
            processAllOfItem(nestedItem, parentName);
          }
        }
      }
    }

    // Process all allOf items
    for (final item in allOf) {
      processAllOfItem(item, name);
    }

    if (allProperties.isEmpty) {
      Logger.warning(
        'Схема "$name" с allOf не содержит свойств после объединения. '
        'Будет сгенерирован пустой класс.',
      );
    }

    final mergedSchema = <String, dynamic>{
      'type': 'object',
      'properties': allProperties,
      if (allRequired.isNotEmpty) 'required': allRequired,
    };

    return _generateClass(name, mergedSchema, context, style, config: config, override: override);
  }

  /// Generates class for oneOf/anyOf schema.
  /// 
  /// For oneOf/anyOf a safe wrapper with dynamic value is generated.
  /// In the future, union types can be generated here, especially with discriminator.
  static String _generateOneOfClass(
    String name,
    Map<String, dynamic> schema,
    GenerationContext context, {
    List<dynamic>? oneOf,
    List<dynamic>? anyOf,
    SchemaOverride? override,
  }) {
    final className = override?.className ?? _toPascalCase(name);
    final hasOneOf = oneOf != null && oneOf.isNotEmpty;
    final hasAnyOf = anyOf != null && anyOf.isNotEmpty;
    
    // Determine types for logging
    final possibleTypes = <String>[];
    if (hasOneOf) {
      for (final item in oneOf) {
        if (item is Map<String, dynamic>) {
          final ref = item[r'$ref'] as String?;
          if (ref != null) {
            final refName = ref.split('/').last;
            possibleTypes.add(refName);
          } else {
            final type = item['type'] as String?;
            if (type != null) {
              possibleTypes.add(type);
            }
          }
        }
      }
    }
    if (hasAnyOf) {
      for (final item in anyOf) {
        if (item is Map<String, dynamic>) {
          final ref = item[r'$ref'] as String?;
          if (ref != null) {
            final refName = ref.split('/').last;
            possibleTypes.add(refName);
          } else {
            final type = item['type'] as String?;
            if (type != null) {
              possibleTypes.add(type);
            }
          }
        }
      }
    }

    // Check for discriminator (for future union type support)
    final discriminator = schema['discriminator'] as Map<String, dynamic>?;
    final hasDiscriminator = discriminator != null;
    
    if (hasDiscriminator) {
      final propertyName = discriminator['propertyName'] as String? ?? 'type';
      Logger.verbose(
        'Схема "$name" использует discriminator "$propertyName" для oneOf/anyOf. '
        'В будущих версиях будет поддержка генерации union-типов.',
      );
    }

    // Log information about possible types
    if (possibleTypes.isNotEmpty) {
      final typesStr = possibleTypes.join(', ');
      Logger.verbose(
        'Схема "$name" использует ${hasOneOf ? 'oneOf' : 'anyOf'} с возможными типами: $typesStr. '
        'Генерируется безопасная обёртка с dynamic значением.',
      );
    } else {
      Logger.warning(
        'Схема "$name" использует ${hasOneOf ? 'oneOf' : 'anyOf'}, но не удалось определить возможные типы. '
        'Генерируется обёртка с dynamic значением.',
      );
    }

    // Generate safe wrapper
    final buffer = StringBuffer()
      ..writeln('/// Класс для ${hasOneOf ? 'oneOf' : 'anyOf'} схемы "$name".')
      ..writeln('///')
      ..writeln('/// Внимание: Для ${hasOneOf ? 'oneOf' : 'anyOf'} схем генерируется обёртка с dynamic значением.')
      ..writeln('/// В будущих версиях будет поддержка генерации union-типов.');
    if (possibleTypes.isNotEmpty) {
      buffer.writeln('/// Возможные типы: ${possibleTypes.join(', ')}.');
    }
    buffer
      ..writeln('class $className {')
      ..writeln('  /// Значение (может быть одним из возможных типов).')
      ..writeln('  final dynamic value;')
      ..writeln()
      ..writeln('  const $className(this.value);')
      ..writeln()
      ..writeln('  /// Создаёт экземпляр из JSON.')
      ..writeln('  ///')
      ..writeln('  /// Внимание: Для ${hasOneOf ? 'oneOf' : 'anyOf'} схем требуется ручная валидация типа.')
      ..writeln('  factory $className.fromJson(dynamic json) {')
      ..writeln('    if (json == null) {')
      ..writeln('      throw ArgumentError(\'JSON не может быть null для $className\');')
      ..writeln('    }')
      ..writeln('    return $className(json);')
      ..writeln('  }')
      ..writeln()
      ..writeln('  /// Преобразует в JSON.')
      ..writeln('  dynamic toJson() => value;')
      ..writeln()
      ..writeln('  @override')
      ..writeln('  String toString() => \'$className(value: \$value)\';')
      ..writeln('}');

    return buffer.toString();
  }

  static String _dartTypeForSchema(
    Map<String, dynamic> schema,
    GenerationContext context, {
    required bool required,
  }) {
    // Handle $ref
    final ref = schema[r'$ref'] as String?;
    if (ref != null) {
      final refSchema = context.resolveRef(ref, context: null);
      if (refSchema != null) {
        // Check if this is an enum
        if (context.isEnum(refSchema)) {
          final enumName = context.getEnumTypeName(refSchema, ref.split('/').last);
          if (enumName != null) {
            return required ? enumName : '$enumName?';
          }
        }
        // Otherwise it's a class
        final refName = ref.split('/').last;
        final baseType = _toPascalCase(refName);
        return required ? baseType : '$baseType?';
      }
      // If failed to resolve, use name from ref
      final refName = ref.split('/').last;
      final baseType = _toPascalCase(refName);
      return required ? baseType : '$baseType?';
    }

    // Проверка на enum
    if (context.isEnum(schema)) {
      final enumName = context.getEnumTypeName(schema, null);
      if (enumName != null) {
        return required ? enumName : '$enumName?';
      }
    }

    final type = schema['type'] as String?;
    final format = schema['format'] as String?;

    String base;
    switch (type) {
      case 'integer':
        // Distinguish int and num
        if (format == 'int64' || format == 'int32') {
          base = 'int';
        } else {
          base = 'int';
        }
        break;
      case 'number':
        base = 'num';
        break;
      case 'boolean':
        base = 'bool';
        break;
      case 'array':
        final items = schema['items'];
        if (items != null && items is Map<String, dynamic>) {
          final itemType = _dartTypeForSchema(items, context, required: true);
          base = 'List<$itemType>';
        } else {
          // Array without items - generate List<dynamic>
          base = 'List<dynamic>';
        }
        break;
      case 'object':
        // Check if additionalProperties exists
        final additionalProps = schema['additionalProperties'];
        if (additionalProps != null && additionalProps != false) {
          if (additionalProps is Map<String, dynamic>) {
            final valueType = _dartTypeForSchema(additionalProps, context, required: true);
            base = 'Map<String, $valueType>';
          } else {
            base = 'Map<String, dynamic>';
          }
        } else {
          base = 'Map<String, dynamic>';
        }
        break;
      case 'string':
        if (format == 'date-time' || format == 'date') {
          base = 'DateTime';
        } else {
          base = 'String';
        }
        break;
      default:
        base = 'dynamic';
    }

    // Field non-nullable only if required=true AND nullable=false
    // required already accounts for nullable from schema, so just use required
    return required ? base : '$base?';
  }

  static String _fromJsonExpression(
    String source,
    Map<String, dynamic> schema,
    GenerationContext context, {
    bool isRequired = false,
  }) {
    final nullable = schema['nullable'] as bool? ?? false;
    final isNonNullable = isRequired && !nullable;

    // Обработка $ref
    final ref = schema[r'$ref'] as String?;
    if (ref != null) {
      final refSchema = context.resolveRef(ref, context: null);
      if (refSchema != null) {
        if (context.isEnum(refSchema)) {
          final enumName = context.getEnumTypeName(refSchema, ref.split('/').last);
          if (enumName != null) {
            if (isNonNullable) {
              return '$enumName.fromJson($source)!';
            }
            return '$enumName.fromJson($source)';
          }
        }
        final refName = ref.split('/').last;
        final type = _toPascalCase(refName);
        if (isNonNullable) {
          return '$type.fromJson($source as Map<String, dynamic>)';
        }
        return '$source == null ? null : $type.fromJson($source as Map<String, dynamic>)';
      }
      final refName = ref.split('/').last;
      final type = _toPascalCase(refName);
      if (isNonNullable) {
        return '$type.fromJson($source as Map<String, dynamic>)';
      }
      return '$source == null ? null : $type.fromJson($source as Map<String, dynamic>)';
    }

    // Проверка на enum
    if (context.isEnum(schema)) {
      final enumName = context.getEnumTypeName(schema, null);
      if (enumName != null) {
        if (isNonNullable) {
          return '$enumName.fromJson($source)!';
        }
        return '$enumName.fromJson($source)';
      }
    }

    final type = schema['type'] as String?;
    final format = schema['format'] as String?;

    switch (type) {
      case 'array':
        final items = schema['items'];
        if (items != null && items is Map<String, dynamic>) {
          final itemExpr = _fromJsonExpression('e', items, context, isRequired: true);
          if (isNonNullable) {
            return '($source as List<dynamic>).map((e) => $itemExpr).toList()';
          }
          return '$source == null ? null : ($source as List<dynamic>).map((e) => $itemExpr).toList()';
        } else {
          if (isNonNullable) {
            return '$source as List<dynamic>';
          }
          return '$source as List<dynamic>?';
        }
      case 'string':
        if (format == 'date-time' || format == 'date') {
          if (isNonNullable) {
            return 'DateTime.parse($source as String)';
          }
          return '$source == null ? null : DateTime.parse($source as String)';
        }
        if (isNonNullable) {
          return '$source as String';
        }
        return '$source as String?';
      case 'integer':
        if (isNonNullable) {
          return '($source as num).toInt()';
        }
        return '$source == null ? null : ($source as num?)?.toInt()';
      case 'number':
        if (isNonNullable) {
          return '$source as num';
        }
        return '$source as num?';
      case 'boolean':
        if (isNonNullable) {
          return '$source as bool';
        }
        return '$source as bool?';
      case 'object':
        final additionalProps = schema['additionalProperties'];
        if (additionalProps != null && additionalProps != false) {
          if (additionalProps is Map<String, dynamic>) {
            final valueExpr = _fromJsonExpression('v', additionalProps, context, isRequired: true);
            if (isNonNullable) {
              return '($source as Map<String, dynamic>).map((k, v) => MapEntry(k, $valueExpr))';
            }
            return '$source == null ? null : ($source as Map<String, dynamic>).map((k, v) => MapEntry(k, $valueExpr))';
          }
        }
        if (isNonNullable) {
          return '$source as Map<String, dynamic>';
        }
        return '$source as Map<String, dynamic>?';
      default:
        return source;
    }
  }

  static String _toJsonExpression(
    String fieldName,
    Map<String, dynamic> schema,
    GenerationContext context,
  ) {
    // Обработка $ref
    final ref = schema[r'$ref'] as String?;
    if (ref != null) {
      final refSchema = context.resolveRef(ref, context: null);
      if (refSchema != null && context.isEnum(refSchema)) {
        return '$fieldName?.toJson()';
      }
      return '$fieldName?.toJson()';
    }

    // Проверка на enum
    if (context.isEnum(schema)) {
      return '$fieldName?.toJson()';
    }

    final type = schema['type'] as String?;
    final format = schema['format'] as String?;

    switch (type) {
      case 'array':
        final items = schema['items'];
        if (items != null && items is Map<String, dynamic>) {
          final inner = _toJsonExpression('e', items, context);
          return '$fieldName?.map((e) => $inner).toList()';
        } else {
          return '$fieldName';
        }
      case 'string':
        if (format == 'date-time' || format == 'date') {
          return '$fieldName?.toIso8601String()';
        }
        return fieldName;
      case 'object':
        final additionalProps = schema['additionalProperties'];
        if (additionalProps != null && additionalProps != false) {
          if (additionalProps is Map<String, dynamic>) {
            final inner = _toJsonExpression('v', additionalProps, context);
            return '$fieldName?.map((k, v) => MapEntry(k, $inner))';
          }
        }
        return fieldName;
      default:
        return fieldName;
    }
  }

  static String _toPascalCase(String name) {
    final parts = name
        .replaceAll(RegExp(r'[^A-Za-z0-9_]'), '_')
        .split(RegExp(r'[_\s]+'))
      ..removeWhere((e) => e.isEmpty);
    if (parts.isEmpty) return 'Unknown';
    return parts.map((p) => p[0].toUpperCase() + p.substring(1)).join();
  }

  /// Checks schemas for suspicious constructs.
  static void _validateSchemas(
    Map<String, dynamic> schemas,
    GenerationContext context,
    LintConfig lintConfig,
  ) {
    schemas.forEach((schemaName, schemaRaw) {
      final schema = <String, dynamic>{
        ...?schemaRaw as Map<String, dynamic>?,
      };
      
      // Check enums (including empty ones)
      final enumValues = schema['enum'] as List?;
      if (enumValues != null) {
        _validateEnum(schema, schemaName, lintConfig);
        // If this is an enum, don't check as regular schema
        if (context.isEnum(schema)) {
          return;
        }
      }

              // Check for empty object (only for non-enum schemas and non-oneOf/anyOf/allOf)
              if (lintConfig.isEnabled(LintRuleId.emptyObject) && 
                  !context.isEnum(schema) &&
                  !schema.containsKey('oneOf') &&
                  !schema.containsKey('anyOf') &&
                  !schema.containsKey('allOf')) {
                final properties = schema['properties'] as Map<String, dynamic>? ?? {};
                final additionalProps = schema['additionalProperties'];
                if (properties.isEmpty && (additionalProps == null || additionalProps == false)) {
                  _reportLintIssue(
                    LintRuleId.emptyObject,
                    lintConfig,
                    'Схема "$schemaName" является пустым объектом (нет properties и additionalProperties).',
                  );
                }
              }

      final properties = schema['properties'] as Map<String, dynamic>? ?? <String, dynamic>{};
      properties.forEach((propName, propSchemaRaw) {
        final propSchema = <String, dynamic>{
          ...?propSchemaRaw as Map<String, dynamic>?,
        };
        
        // Check for missing type
        if (lintConfig.isEnabled(LintRuleId.missingType)) {
          if (!propSchema.containsKey('type') && !propSchema.containsKey(r'$ref')) {
            _reportLintIssue(
              LintRuleId.missingType,
              lintConfig,
              'Поле "$propName" в схеме "$schemaName" не имеет типа и не является ссылкой (\$ref). '
              'Будет сгенерирован тип dynamic.',
            );
          }
        }

        // Check for suspicious fields (e.g., id without nullable and without required)
        if (lintConfig.isEnabled(LintRuleId.suspiciousIdField)) {
          if (propName == 'id' || propName.endsWith('_id') || propName.endsWith('Id')) {
            final isNullable = propSchema['nullable'] as bool? ?? false;
            final isRequired = (schema['required'] as List?)?.contains(propName) ?? false;
            
            if (!isNullable && !isRequired) {
              _reportLintIssue(
                LintRuleId.suspiciousIdField,
                lintConfig,
                'Поле "$propName" в схеме "$schemaName" похоже на идентификатор, '
                'но не помечено как required и не nullable. '
                'Возможно, стоит добавить required: true или nullable: true.',
              );
            }
          }
        }

        // Проверка на $ref
        final propRef = propSchema[r'$ref'] as String?;
        if (propRef != null) {
          if (lintConfig.isEnabled(LintRuleId.missingRefTarget)) {
            final refSchema = context.resolveRef(propRef, context: schemaName);
            if (refSchema == null) {
              _reportLintIssue(
                LintRuleId.missingRefTarget,
                lintConfig,
                'Не найдена схема для ссылки "$propRef" в поле "$propName" схемы "$schemaName". '
                'Проверьте, что схема определена в спецификации.',
              );
            }
          }
        }

        // Проверка на несогласованность типов
        if (lintConfig.isEnabled(LintRuleId.typeInconsistency)) {
          _checkTypeInconsistency(propSchema, propName, schemaName, lintConfig);
        }

        // Проверка массива без items
        if (lintConfig.isEnabled(LintRuleId.arrayWithoutItems)) {
          final propType = propSchema['type'] as String?;
          if (propType == 'array' && !propSchema.containsKey('items')) {
            _reportLintIssue(
              LintRuleId.arrayWithoutItems,
              lintConfig,
              'Поле "$propName" в схеме "$schemaName" имеет тип array, но не содержит items. '
              'Будет сгенерирован тип List<dynamic>.',
            );
          }
        }
      });
    });
  }

  /// Проверяет enum на проблемы.
  static void _validateEnum(
    Map<String, dynamic> schema,
    String schemaName,
    LintConfig lintConfig,
  ) {
    if (lintConfig.isEnabled(LintRuleId.emptyEnum)) {
      final enumValues = schema['enum'] as List?;
      if (enumValues == null || enumValues.isEmpty) {
        _reportLintIssue(
          LintRuleId.emptyEnum,
          lintConfig,
          'Enum "$schemaName" не содержит значений.',
        );
      }
    }
  }

  /// Проверяет несогласованность типов.
  static void _checkTypeInconsistency(
    Map<String, dynamic> propSchema,
    String propName,
    String schemaName,
    LintConfig lintConfig,
  ) {
    final propType = propSchema['type'] as String?;
    final format = propSchema['format'] as String?;
    final isNullable = propSchema['nullable'] as bool? ?? false;

    // Проверка: type: string, format: date-time, но не nullable
    // Обычно date-time может быть null в некоторых случаях
    if (propType == 'string' && format == 'date-time' && !isNullable) {
      // Это не обязательно ошибка, но может быть предупреждением
      // Пропускаем, так как это нормальная практика
    }

    // Проверка: type: integer, но format указан (обычно format используется для string)
    if (propType == 'integer' && format != null) {
      _reportLintIssue(
        LintRuleId.typeInconsistency,
        lintConfig,
        'Поле "$propName" в схеме "$schemaName" имеет тип integer, но указан format "$format". '
        'Format обычно используется только для типа string.',
      );
    }

    // Проверка: type: number, но format указан (обычно format используется для string)
    if (propType == 'number' && format != null && format != 'float' && format != 'double') {
      _reportLintIssue(
        LintRuleId.typeInconsistency,
        lintConfig,
        'Поле "$propName" в схеме "$schemaName" имеет тип number, но указан format "$format". '
        'Для number допустимы только format: float или double.',
      );
    }
  }

  /// Сообщает о проблеме lint с учётом уровня серьёзности.
  static void _reportLintIssue(
    LintRuleId ruleId,
    LintConfig lintConfig,
    String message,
  ) {
    final severity = lintConfig.getSeverity(ruleId);
    switch (severity) {
      case LintSeverity.off:
        // Не сообщаем
        break;
      case LintSeverity.warning:
        Logger.warning(message);
        break;
      case LintSeverity.error:
        Logger.error(message);
        break;
    }
  }

  /// Проверяет отсутствующие $ref после генерации.
  static void _checkMissingRefs(
    Map<String, dynamic> schemas,
    GenerationContext context,
    LintConfig lintConfig,
  ) {
    if (!lintConfig.isEnabled(LintRuleId.missingRefTarget)) {
      return;
    }

    final missingRefs = <String>{};
    
    void checkSchema(Map<String, dynamic> schema, String? parentName) {
      final schemaRef = schema[r'$ref'] as String?;
      if (schemaRef != null) {
        final refSchema = context.resolveRef(schemaRef, context: parentName);
        if (refSchema == null && !missingRefs.contains(schemaRef)) {
          missingRefs.add(schemaRef);
          final contextMsg = parentName != null ? ' (в схеме "$parentName")' : '';
          _reportLintIssue(
            LintRuleId.missingRefTarget,
            lintConfig,
            'Не найдена схема для ссылки "$schemaRef"$contextMsg. '
            'Проверьте, что схема определена в спецификации.',
          );
        }
      }

      // Рекурсивно проверяем вложенные схемы
      final properties = schema['properties'] as Map<String, dynamic>? ?? {};
      properties.forEach((propName, propSchemaRaw) {
        if (propSchemaRaw is Map<String, dynamic>) {
          checkSchema(propSchemaRaw, parentName);
        }
      });

      final items = schema['items'];
      if (items is Map<String, dynamic>) {
        checkSchema(items, parentName);
      }

      final additionalProps = schema['additionalProperties'];
      if (additionalProps is Map<String, dynamic>) {
        checkSchema(additionalProps, parentName);
      }

      final allOf = schema['allOf'] as List?;
      if (allOf != null) {
        for (final item in allOf) {
          if (item is Map<String, dynamic>) {
            checkSchema(item, parentName);
          }
        }
      }
    }

    schemas.forEach((schemaName, schemaRaw) {
      final schema = <String, dynamic>{
        ...?schemaRaw as Map<String, dynamic>?,
      };
      checkSchema(schema, schemaName);
    });
  }
}
