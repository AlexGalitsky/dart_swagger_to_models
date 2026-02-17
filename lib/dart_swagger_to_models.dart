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
export 'src/generators/class_generator_strategy.dart'
    show ClassGeneratorStrategy, FieldInfo;
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
    throw Exception(
        'Failed to detect specification version (swagger/openapi).');
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
    // If custom style is specified in config, use it; otherwise use defaultStyle or passed style
    final effectiveStyle = effectiveConfig.customStyleName != null
        ? null // Custom style will be used via config.customStyleName
        : (style ?? effectiveConfig.defaultStyle ?? GenerationStyle.plainDart);
    final effectiveProjectDir = projectDir ?? effectiveConfig.projectDir ?? '.';

    // Resolve outputDir relative to projectDir (like in swagger_builder.dart)
    final rawOutputDir = outputDir ?? effectiveConfig.outputDir ?? 'lib/models';
    final effectiveOutputDir = p.isAbsolute(rawOutputDir)
        ? rawOutputDir
        : p.join(effectiveProjectDir, rawOutputDir);

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
    Logger.verbose('Starting model generation');
    Logger.verbose('Style: $style');
    Logger.verbose('Output directory: $outputDir');
    if (changedOnly) {
      Logger.verbose('Incremental generation mode: only changed schemas');
    }

    final generatedFiles = <String>[];
    final outDir = Directory(outputDir);
    if (!await outDir.exists()) {
      Logger.verbose('Creating output directory: $outputDir');
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
          Logger.verbose('Schema "${entry.key}" changed, will be regenerated');
        } else {
          Logger.verbose('Schema "${entry.key}" unchanged, skipping');
        }
      }

      // Check for deleted schemas
      final currentSchemaNames = schemas.keys.toSet();
      final cachedSchemaNames = cache.cachedSchemas;
      final deletedSchemas = cachedSchemaNames.difference(currentSchemaNames);

      if (deletedSchemas.isNotEmpty) {
        Logger.verbose(
            'Deleted schemas detected: ${deletedSchemas.join(", ")}');
        for (final deletedSchema in deletedSchemas) {
          cache.removeHash(deletedSchema);
          // Delete file if it exists
          final fileName = _toSnakeCase(deletedSchema);
          final filePath = p.join(outputDir, '$fileName.dart');
          final file = File(filePath);
          if (await file.exists()) {
            await file.delete();
            Logger.verbose('Deleted file for removed schema: $fileName.dart');
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
    Logger.verbose('Scanning project for existing files...');
    final existingFiles = await _scanProjectForMarkers(
      projectDir,
      outputDir,
    );
    Logger.verbose('Found existing files: ${existingFiles.length}');

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

    Logger.verbose('Found enum schemas: ${enumSchemas.length}');

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
          Logger.verbose('Updated enum: $modelName');
        } else {
          filesCreated++;
          Logger.verbose('Created enum: $modelName');
        }

        // Update cache
        if (cache != null) {
          final hash = GenerationCache.computeSchemaHash(entry.value);
          cache.setHash(entry.key, hash);
        }
      } catch (e) {
        Logger.error('Error generating enum "${entry.key}": $e');
        rethrow;
      }
    }

    // Then generate classes into separate files
    final classSchemas = schemasToProcess.entries.where((e) {
      final schemaMap = <String, dynamic>{
        ...?e.value as Map<String, dynamic>?,
      };
      return !context.isEnum(schemaMap);
    }).length;
    Logger.verbose('Found class schemas: $classSchemas');

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
            Logger.verbose('Updated class: $modelName');
          } else {
            filesCreated++;
            Logger.verbose('Created class: $modelName');
          }

          // Update cache
          if (cache != null) {
            final hash = GenerationCache.computeSchemaHash(schemaMap);
            cache.setHash(entry.key, hash);
          }
        } catch (e) {
          Logger.error('Error generating class "${entry.key}": $e');
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
      Logger.verbose('Cache saved to ${cache.cacheFilePath}');
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
  /// Returns a map where the key is the model name and the value is file content.
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
    final strategy = GeneratorFactory.createStrategy(style,
        customStyleName: config?.customStyleName);
    final imports = strategy.generateImportsAndParts(fileName);
    imports.forEach(buffer.writeln);
    if (imports.isNotEmpty) {
      buffer.writeln();
    }

    buffer.writeln('/*SWAGGER-TO-DART: Codegen start*/');
    buffer.writeln();
    buffer.write(_generateEnum(enumName, schema, context, config: config));
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
          if (refTypeName != currentSchemaName &&
              !visited.contains(refTypeName)) {
            visited.add(refTypeName);
            // Check that this is not a built-in type
            if (refSchema.containsKey('properties') ||
                context.isEnum(refSchema)) {
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
      final importPath = relativePath.replaceAll(r'\', '/');
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
    final dependencies =
        _collectDependencies(schema, context, schemaName, outputDir);
    final modelImports = _generateImportsForDependencies(
        dependencies, outputDir, '$fileName.dart');

    // Add imports and parts depending on style
    final strategy = GeneratorFactory.createStrategy(style,
        customStyleName: config?.customStyleName);
    final styleImports = strategy.generateImportsAndParts(fileName);

    // Combine imports: first model imports, then style imports
    final allImports = <String>[...modelImports, ...styleImports];
    allImports.forEach(buffer.writeln);
    if (allImports.isNotEmpty) {
      buffer.writeln();
    }

    buffer.writeln('/*SWAGGER-TO-DART: Codegen start*/');
    buffer.writeln();
    buffer.write(_generateClass(className, schema, context, style,
        config: config, override: override));
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
    const startMarker = '/*SWAGGER-TO-DART: Codegen start*/';
    const stopMarker = '/*SWAGGER-TO-DART: Codegen stop*/';

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

    final before =
        existingContent.substring(0, startIndex + startMarker.length);
    final after = existingContent.substring(stopIndex);
    final newEnumCode = _generateEnum(enumName, schema, context, config: config);

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
    const startMarker = '/*SWAGGER-TO-DART: Codegen start*/';
    const stopMarker = '/*SWAGGER-TO-DART: Codegen stop*/';

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

    final before =
        existingContent.substring(0, startIndex + startMarker.length);
    final after = existingContent.substring(stopIndex);
    final newClassCode = _generateClass(className, schema, context, style,
        config: config, override: override);

    return '$before\n$newClassCode\n$after';
  }

  /// Converts name to snake_case for file name.
  static String _toSnakeCase(String name) {
    final pascal = _toPascalCase(name);
    if (pascal.isEmpty) {
      return '';
    }
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
    GenerationContext context, {
    Config? config,
  }) {
    final enumName = _toPascalCase(name);
    final enumValues = schema['enum'] as List?;
    if (enumValues == null || enumValues.isEmpty) {
      return '';
    }

    // Support x-enumNames / x-enum-varnames
    final enumNames =
        schema['x-enumNames'] as List? ?? schema['x-enum-varnames'] as List?;
    final hasCustomNames =
        enumNames != null && enumNames.length == enumValues.length;

    final buffer = StringBuffer();

    // Optional DartDoc for enum from schema.description / schema.example
    final generateDocs = config?.generateDocs ?? true;
    if (generateDocs) {
      final description = schema['description'] as String?;
      final example = schema['example'];
      final doc = _buildDocComment(
        description: description,
        example: example,
      );
      if (doc.isNotEmpty) {
        buffer.writeln(doc);
      }
    }

    buffer.writeln('enum $enumName {');

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
    if (cleaned.isEmpty) {
      return 'unknown';
    }
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
      return _generateAllOfClass(name, schema, context, style,
          config: config, override: override);
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

    // Optional DartDoc for class from schema.description / schema.example
    final generateDocs = config?.generateDocs ?? true;
    String? classDoc;
    if (generateDocs) {
      final description = schema['description'] as String?;
      final example = schema['example'];
      final doc = _buildDocComment(
        description: description,
        example: example,
      );
      if (doc.isNotEmpty) {
        classDoc = doc;
      }
    }
    final properties = schema['properties'] as Map<String, dynamic>? ?? {};
    final additionalProps = schema['additionalProperties'];

    // If object only has additionalProperties and no properties — generate
    // the same for all styles.
    if (properties.isEmpty &&
        additionalProps != null &&
        additionalProps != false) {
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
        final valueExpr = _fromJsonExpression('v', additionalProps, context,
            isRequired: true);
        classBuffer.writeln(
            '      data: json.map((k, v) => MapEntry(k, $valueExpr)),');
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
        if (typeFromSchema != null &&
            override.typeMapping!.containsKey(typeFromSchema)) {
          dartType = override.typeMapping![typeFromSchema]!;
          if (!isNonNullable) {
            dartType = '$dartType?';
          }
        } else {
          dartType =
              _dartTypeForSchema(propSchema, context, required: isNonNullable);
        }
      } else {
        dartType =
            _dartTypeForSchema(propSchema, context, required: isNonNullable);
      }

      fieldInfos[propName] = FieldInfo(
        name: fieldName,
        jsonKey: propName,
        // Original JSON key
        dartType: dartType,
        isRequired: isNonNullable,
        schema: propSchema,
      );
    });

    // Determine if @JsonKey should be used
    // Priority: override.useJsonKey > config.useJsonKey > false
    final useJsonKey = override?.useJsonKey ?? config?.useJsonKey ?? false;

    // Use strategy for class generation
    final strategy = GeneratorFactory.createStrategy(style,
        customStyleName: config?.customStyleName);
    var classCode = strategy.generateFullClass(
      className,
      fieldInfos,
      (jsonKey, schema) {
        // Determine if field is required based on FieldInfo
        final fieldInfo = fieldInfos[jsonKey];
        final isRequired = fieldInfo?.isRequired ?? false;
        return _fromJsonExpression('json[\'$jsonKey\']', schema, context,
            isRequired: isRequired);
      },
      (fieldName, schema) => _toJsonExpression(fieldName, schema, context),
      useJsonKey: useJsonKey,
    );

    // Optionally generate validation helpers
    final generateValidation = config?.generateValidation ?? false;
    if (generateValidation) {
      final validationExtension =
          _generateValidationExtension(className, fieldInfos, schema);
      if (validationExtension.isNotEmpty) {
        classCode = '$classCode\n\n$validationExtension';
      }
    }

    // Optionally generate test data factory
    final generateTestData = config?.generateTestData ?? false;
    if (generateTestData) {
      final testDataFactory =
          _generateTestDataFactory(className, fieldInfos);
      if (testDataFactory.isNotEmpty) {
        classCode = '$classCode\n\n$testDataFactory';
      }
    }

    if (classDoc != null) {
      return '$classDoc\n$classCode';
    }
    return classCode;
  }

  /// Generates validation extension based on schema constraints.
  ///
  /// Supports numeric (`minimum`/`maximum`), string (`minLength`/`maxLength`),
  /// and array (`minItems`/`maxItems`) constraints.
  static String _generateValidationExtension(
    String className,
    Map<String, FieldInfo> fields,
    Map<String, dynamic> schema,
  ) {
    final properties = schema['properties'] as Map<String, dynamic>? ?? {};
    if (properties.isEmpty) {
      return '';
    }

    final buffer = StringBuffer()
      ..writeln('extension ${className}Validation on $className {')
      ..writeln(
          '  /// Returns a list of validation error messages. Empty if the instance is valid.')
      ..writeln('  List<String> validate() {')
      ..writeln('    final errors = <String>[];');

    properties.forEach((propName, _) {
      final field = fields[propName];
      if (field == null) {
        return;
      }
      final fieldSchema = field.schema;
      final dartType = field.dartType;
      final isNullable = dartType.endsWith('?');
      final baseType =
          isNullable ? dartType.substring(0, dartType.length - 1) : dartType;
      final fieldName = field.camelCaseName;

      final minimum = fieldSchema['minimum'] ?? fieldSchema['min'];
      final maximum = fieldSchema['maximum'] ?? fieldSchema['max'];
      final minLength = fieldSchema['minLength'];
      final maxLength = fieldSchema['maxLength'];
      final minItems = fieldSchema['minItems'];
      final maxItems = fieldSchema['maxItems'];

      final hasNumericConstraints = (minimum is num) || (maximum is num);
      final hasStringLengthConstraints =
          (minLength is int) || (maxLength is int);
      final hasArrayLengthConstraints =
          (minItems is int) || (maxItems is int);

      // Numbers: int / num / double
      if (hasNumericConstraints &&
          (baseType == 'int' || baseType == 'num' || baseType == 'double')) {
        if (minimum is num) {
          if (isNullable) {
            buffer.writeln(
                '    final $dartType _value${className}_$fieldName = $fieldName;');
            buffer.writeln(
                '    if (_value${className}_$fieldName != null && _value${className}_$fieldName! < $minimum) {');
          } else {
            buffer
                .writeln('    if ($fieldName < $minimum) {');
          }
          buffer.writeln(
              "      errors.add('$className.$propName must be >= $minimum.');");
          buffer.writeln('    }');
        }
        if (maximum is num) {
          if (isNullable) {
            buffer.writeln(
                '    final $dartType _valueMax${className}_$fieldName = $fieldName;');
            buffer.writeln(
                '    if (_valueMax${className}_$fieldName != null && _valueMax${className}_$fieldName! > $maximum) {');
          } else {
            buffer
                .writeln('    if ($fieldName > $maximum) {');
          }
          buffer.writeln(
              "      errors.add('$className.$propName must be <= $maximum.');");
          buffer.writeln('    }');
        }
      }

      // Strings: minLength / maxLength
      if (baseType == 'String' && hasStringLengthConstraints) {
        if (minLength is int) {
          if (isNullable) {
            buffer.writeln(
                '    final $dartType _valueLenMin${className}_$fieldName = $fieldName;');
            buffer.writeln(
                '    if (_valueLenMin${className}_$fieldName != null && _valueLenMin${className}_$fieldName!.length < $minLength) {');
          } else {
            buffer.writeln(
                '    if ($fieldName.length < $minLength) {');
          }
          buffer.writeln(
              "      errors.add('$className.$propName length must be >= $minLength.');");
          buffer.writeln('    }');
        }
        if (maxLength is int) {
          if (isNullable) {
            buffer.writeln(
                '    final $dartType _valueLenMax${className}_$fieldName = $fieldName;');
            buffer.writeln(
                '    if (_valueLenMax${className}_$fieldName != null && _valueLenMax${className}_$fieldName!.length > $maxLength) {');
          } else {
            buffer.writeln(
                '    if ($fieldName.length > $maxLength) {');
          }
          buffer.writeln(
              "      errors.add('$className.$propName length must be <= $maxLength.');");
          buffer.writeln('    }');
        }
      }

      // Arrays: minItems / maxItems
      if (baseType.startsWith('List<') && hasArrayLengthConstraints) {
        if (minItems is int) {
          if (isNullable) {
            buffer.writeln(
                '    final $dartType _valueItemsMin${className}_$fieldName = $fieldName;');
            buffer.writeln(
                '    if (_valueItemsMin${className}_$fieldName != null && _valueItemsMin${className}_$fieldName!.length < $minItems) {');
          } else {
            buffer.writeln(
                '    if ($fieldName.length < $minItems) {');
          }
          buffer.writeln(
              "      errors.add('$className.$propName items count must be >= $minItems.');");
          buffer.writeln('    }');
        }
        if (maxItems is int) {
          if (isNullable) {
            buffer.writeln(
                '    final $dartType _valueItemsMax${className}_$fieldName = $fieldName;');
            buffer.writeln(
                '    if (_valueItemsMax${className}_$fieldName != null && _valueItemsMax${className}_$fieldName!.length > $maxItems) {');
          } else {
            buffer.writeln(
                '    if ($fieldName.length > $maxItems) {');
          }
          buffer.writeln(
              "      errors.add('$className.$propName items count must be <= $maxItems.');");
          buffer.writeln('    }');
        }
      }
    });

    buffer
      ..writeln('    return errors;')
      ..writeln('  }')
      ..writeln('}');

    return buffer.toString();
  }

  /// Generates simple test data factory function for a class.
  ///
  /// The factory provides sensible defaults for primitive fields and
  /// requires explicit parameters only for unsupported/custom types.
  static String _generateTestDataFactory(
    String className,
    Map<String, FieldInfo> fields,
  ) {
    if (fields.isEmpty) {
      return '';
    }

    final requiredFields =
        fields.values.where((f) => f.isRequired).toList();
    if (requiredFields.isEmpty) {
      return '';
    }

    // Determine which required fields need to be passed in as parameters
    final fieldsNeedingParams = <FieldInfo>[];
    final defaultValues = <String, String?>{};

    for (final field in requiredFields) {
      final defaultExpr = _testDataDefaultForType(field.dartType);
      if (defaultExpr == null) {
        fieldsNeedingParams.add(field);
      } else {
        defaultValues[field.name] = defaultExpr;
      }
    }

    final funcName = 'create${className}TestData';
    final buffer = StringBuffer()
      ..writeln('$className $funcName({');

    for (final field in fieldsNeedingParams) {
      buffer.writeln(
          '  required ${field.dartType} ${field.camelCaseName},');
    }

    buffer
      ..writeln('}) {')
      ..writeln('  return $className(');

    for (final field in requiredFields) {
      final paramName = field.camelCaseName;
      final jsonKey = field.name;
      final defaultExpr = defaultValues[jsonKey];
      if (defaultExpr != null) {
        buffer.writeln('    $paramName: $defaultExpr,');
      } else {
        buffer.writeln('    $paramName: $paramName,');
      }
    }

    buffer
      ..writeln('  );')
      ..writeln('}');

    return buffer.toString();
  }

  /// Returns a simple test value expression for a given Dart type,
  /// or null if the type is not supported and should be passed in.
  static String? _testDataDefaultForType(String dartType) {
    var base = dartType.trim();
    final isNullable = base.endsWith('?');
    if (isNullable) {
      base = base.substring(0, base.length - 1);
    }

    switch (base) {
      case 'int':
        return '1';
      case 'num':
        return '1';
      case 'double':
        return '1.0';
      case 'bool':
        return 'true';
      case 'String':
        return "'example'";
      case 'DateTime':
        return "DateTime.parse('2020-01-01T00:00:00Z')";
    }

    if (base.startsWith('List<') && base.endsWith('>')) {
      final inner = base.substring(5, base.length - 1).trim();
      if (inner.isEmpty) {
        return 'const []';
      }
      return '<$inner>[]';
    }

    if (base.startsWith('Map<String,') && base.endsWith('>')) {
      final valueType =
          base.substring('Map<String,'.length, base.length - 1).trim();
      if (valueType.isEmpty) {
        return '<String, dynamic>{}';
      }
      return '<String, $valueType>{}';
    }

    // Unknown/custom type
    return null;
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
    Logger.verbose(
        'Processing allOf for schema "$name" (${allOf.length} items)');

    final allProperties = <String, dynamic>{};
    final allRequired = <String>[];
    final processedRefs = <String>{}; // To prevent circular dependencies

    // Recursive function to process allOf items
    void processAllOfItem(dynamic item, String? parentName) {
      if (item is! Map<String, dynamic>) {
        return;
      }

      // Handle $ref
      if (item.containsKey(r'$ref')) {
        final ref = item[r'$ref'] as String;

        // Check for circular dependencies
        if (processedRefs.contains(ref)) {
          Logger.warning(
            'Circular dependency detected for $ref in schema "$name". '
            'Skipping duplicate processing.',
          );
          return;
        }
        processedRefs.add(ref);

        final refSchema = context.resolveRef(ref, context: parentName ?? name);
        if (refSchema == null) {
          Logger.warning(
            'Failed to resolve reference $ref in allOf schema "$name". '
            'Skipping this item.',
          );
          processedRefs.remove(ref);
          return;
        }

        // Recursively process nested allOf
        if (refSchema.containsKey('allOf')) {
          final refAllOf = refSchema['allOf'] as List;
          Logger.verbose(
              'Nested allOf detected in $ref (${refAllOf.length} items)');
          for (final refItem in refAllOf) {
            processAllOfItem(refItem, ref.split('/').last);
          }
        } else {
          // Process properties from ref schema
          final props = refSchema['properties'] as Map<String, dynamic>? ?? {};
          allProperties.addAll(props);
          final req =
              (refSchema['required'] as List?)?.cast<String>() ?? <String>[];
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
          Logger.verbose(
              'Nested allOf detected in schema item "$name" (${nestedAllOf.length} items)');
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
        'Schema "$name" with allOf contains no properties after merging. '
        'An empty class will be generated.',
      );
    }

    final mergedSchema = <String, dynamic>{
      'type': 'object',
      'properties': allProperties,
      if (allRequired.isNotEmpty) 'required': allRequired,
    };

    return _generateClass(name, mergedSchema, context, style,
        config: config, override: override);
  }

  /// Generates class for oneOf/anyOf schema.
  ///
  /// - For oneOf/anyOf **with discriminator.mapping** a type-safe union class is generated.
  /// - For other oneOf/anyOf schemas a safe wrapper with `dynamic` value is generated.
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

    // Determine possible types (for logging and discriminator mapping)
    final possibleTypes = <String>[];
    void collectPossibleTypes(List<dynamic>? items) {
      if (items == null) return;
      for (final item in items) {
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
    if (hasOneOf) collectPossibleTypes(oneOf);
    if (hasAnyOf) collectPossibleTypes(anyOf);

    // Check for discriminator (required for union generation)
    final discriminator = schema['discriminator'] as Map<String, dynamic>?;
    final discriminatorProperty =
        discriminator != null ? discriminator['propertyName'] as String? : null;
    final discriminatorMappingRaw =
        discriminator != null ? discriminator['mapping'] : null;
    final discriminatorMapping =
        discriminatorMappingRaw is Map<String, dynamic>
            ? discriminatorMappingRaw
            : null;

    // Build potential union variants when discriminator is present.
    // We support two cases:
    // - Explicit discriminator.mapping (token -> ref)
    // - No mapping, but each referenced schema has a discriminator property with single-valued enum.
    final variants = <Map<String, String>>[]; // {token, ref, typeName}

    if (discriminatorProperty != null) {
      if (discriminatorMapping != null) {
        discriminatorMapping.forEach((token, refValue) {
          if (refValue is String) {
            final refName = refValue.split('/').last;
            final typeName = _toPascalCase(refName);
            variants.add({
              'token': token,
              'ref': refValue,
              'typeName': typeName,
            });
          }
        });
      } else {
        // Infer mapping from referenced schemas using enum on discriminator property.
        final items = hasOneOf
            ? oneOf
            : hasAnyOf
                ? anyOf
                : null;
        if (items != null) {
          for (final item in items) {
            if (item is! Map<String, dynamic>) continue;
            final ref = item[r'$ref'] as String?;
            if (ref == null) continue;

            final refSchema = context.resolveRef(ref, context: name);
            if (refSchema is! Map<String, dynamic>) continue;

            final props =
                refSchema['properties'] as Map<String, dynamic>? ?? {};
            final discProp = props[discriminatorProperty];
            if (discProp is! Map<String, dynamic>) continue;

            final enumValues = discProp['enum'] as List?;
            if (enumValues == null ||
                enumValues.length != 1 ||
                enumValues.first is! String) {
              continue;
            }

            final token = enumValues.first as String;
            final refName = ref.split('/').last;
            final typeName = _toPascalCase(refName);
            variants.add({
              'token': token,
              'ref': ref,
              'typeName': typeName,
            });
          }
        }
      }
    }

    final hasDiscriminatorUnion =
        discriminatorProperty != null && variants.isNotEmpty;

    if (hasDiscriminatorUnion) {
      Logger.verbose(
        'Schema "$name" uses discriminator "$discriminatorProperty" for oneOf/anyOf. '
        'Generating union type with ${variants.length} variants.',
      );

      if (variants.isEmpty) {
        Logger.warning(
          'Schema "$name" has discriminator.mapping but no usable variants were detected. '
          'Falling back to dynamic wrapper.',
        );
      } else {
        // Generate union class
        final buffer = StringBuffer()
          ..writeln(
              '/// Union type for ${hasOneOf ? 'oneOf' : 'anyOf'} schema "$name" with discriminator.')
          ..writeln('class $className {')
          ..writeln(
              '  /// Discriminator value that identifies the concrete type.') // non-nullable
          ..writeln('  final String $discriminatorProperty;')
          ..writeln();

        // Variant fields
        for (final v in variants) {
          final typeName = v['typeName']!;
          final fieldName =
              _toCamelCase(typeName); // helper: Cat -> cat, MyPet -> myPet
          buffer
            ..writeln('  /// Value when this union holds `$typeName`.')
            ..writeln('  final $typeName? $fieldName;')
            ..writeln();
        }

        // Private constructor
        buffer.writeln('  const $className._({');
        buffer.writeln('    required this.$discriminatorProperty,');
        for (final v in variants) {
          final typeName = v['typeName']!;
          final fieldName = _toCamelCase(typeName);
          buffer.writeln('    this.$fieldName,');
        }
        buffer.writeln('  })');
        buffer.writeln('      : ');
        for (var i = 0; i < variants.length; i++) {
          final v = variants[i];
          final typeName = v['typeName']!;
          final fieldName = _toCamelCase(typeName);
          final isLast = i == variants.length - 1;
          buffer.writeln('          $fieldName = $fieldName${isLast ? ';' : ','}');
        }
        buffer.writeln();

        // Named constructors for each variant
        for (final v in variants) {
          final token = v['token']!;
          final typeName = v['typeName']!;
          final fieldName = _toCamelCase(typeName);
          buffer
            ..writeln('  factory $className.from$typeName($typeName value) {')
            ..writeln('    return $className._(')
            ..writeln("      $discriminatorProperty: '$token',")
            ..writeln('      ${fieldName}: value,')
            ..writeln('    );')
            ..writeln('  }')
            ..writeln();
        }

        // fromJson using discriminator
        buffer
          ..writeln(
              '  /// Creates [$className] from JSON using discriminator `$discriminatorProperty`.')
          ..writeln(
              '  factory $className.fromJson(Map<String, dynamic> json) {')
          ..writeln(
              "    final disc = json['$discriminatorProperty'] as String?;")
          ..writeln('    if (disc == null) {')
          ..writeln(
              "      throw ArgumentError('Missing discriminator \"$discriminatorProperty\" for $className');")
          ..writeln('    }')
          ..writeln('    switch (disc) {');

        for (final v in variants) {
          final token = v['token']!;
          final typeName = v['typeName']!;
          buffer
            ..writeln("      case '$token':")
            ..writeln(
                '        return $className.from$typeName($typeName.fromJson(json));');
        }

        buffer
          ..writeln('      default:')
          ..writeln(
              "        throw ArgumentError('Unknown discriminator value \"\$disc\" for $className');")
          ..writeln('    }')
          ..writeln('  }')
          ..writeln();

        // toJson delegates to active variant
        buffer
          ..writeln('  /// Serializes this union back to JSON.')
          ..writeln('  Map<String, dynamic> toJson() {')
          ..writeln('    switch ($discriminatorProperty) {');
        for (final v in variants) {
          final token = v['token']!;
          final typeName = v['typeName']!;
          final fieldName = _toCamelCase(typeName);
          buffer
            ..writeln("      case '$token':")
            ..writeln('        return $fieldName!.toJson();');
        }
        buffer
          ..writeln('      default:')
          ..writeln(
              "        throw StateError('Unknown discriminator value \"\$$discriminatorProperty\" for $className');")
          ..writeln('    }')
          ..writeln('  }')
          ..writeln();

        // when helper for pattern matching
        buffer
          ..writeln('  /// Pattern matching helper for union values.')
          ..writeln('  T when<T>({')
          ..writeln(
              variants.map((v) => '    required T Function(${v['typeName']} value) ${_toCamelCase(v['typeName']!)}').join(',\n'))
          ..writeln('  }) {')
          ..writeln('    switch ($discriminatorProperty) {');
        for (final v in variants) {
          final token = v['token']!;
          final typeName = v['typeName']!;
          final fieldName = _toCamelCase(typeName);
          buffer
            ..writeln("      case '$token':")
            ..writeln('        return ${fieldName}(${fieldName}!);');
        }
        buffer
          ..writeln('      default:')
          ..writeln(
              "        throw StateError('Unknown discriminator value \"\$$discriminatorProperty\" for $className');")
          ..writeln('    }')
          ..writeln('  }')
          ..writeln();

        // maybeWhen helper
        buffer
          ..writeln('  /// Nullable pattern matching helper for union values.')
          ..writeln('  T? maybeWhen<T>({')
          ..writeln(
              variants.map((v) => '    T Function(${v['typeName']} value)? ${_toCamelCase(v['typeName']!)}').join(',\n'))
          ..writeln('    T Function()? orElse,')
          ..writeln('  }) {')
          ..writeln('    switch ($discriminatorProperty) {');
        for (final v in variants) {
          final token = v['token']!;
          final typeName = v['typeName']!;
          final fieldName = _toCamelCase(typeName);
          buffer
            ..writeln("      case '$token':")
            ..writeln('        final handler = ${fieldName};')
            ..writeln('        if (handler != null) {')
            ..writeln('          return handler(${fieldName}!);')
            ..writeln('        }')
            ..writeln('        break;');
        }
        buffer
          ..writeln('      default:')
          ..writeln('        break;')
          ..writeln('    }')
          ..writeln('    return orElse != null ? orElse() : null;')
          ..writeln('  }')
          ..writeln();

        buffer
          ..writeln('  @override')
          ..writeln(
              "  String toString() => '$className(\$discriminatorProperty: \$$discriminatorProperty)';")
          ..writeln('}');

        return buffer.toString();
      }
    }

    // If we get here, either there is no discriminator mapping or it was unusable.
    // Fallback to dynamic wrapper.
    if (possibleTypes.isNotEmpty) {
      final typesStr = possibleTypes.join(', ');
      Logger.verbose(
        'Schema "$name" uses ${hasOneOf ? 'oneOf' : 'anyOf'} with possible types: $typesStr. '
        'Generating safe wrapper with dynamic value.',
      );
    } else {
      Logger.warning(
        'Schema "$name" uses ${hasOneOf ? 'oneOf' : 'anyOf'}, but failed to determine possible types. '
        'Generating wrapper with dynamic value.',
      );
    }

    final buffer = StringBuffer()
      ..writeln('/// Class for ${hasOneOf ? 'oneOf' : 'anyOf'} schema "$name".')
      ..writeln('///')
      ..writeln(
          '/// Note: For this schema, a wrapper with dynamic value is generated.');
    if (possibleTypes.isNotEmpty) {
      buffer.writeln('/// Possible types: ${possibleTypes.join(', ')}.');
    }
    buffer
      ..writeln('class $className {')
      ..writeln('  /// Value (can be one of the possible types).')
      ..writeln('  final dynamic value;')
      ..writeln()
      ..writeln('  const $className(this.value);')
      ..writeln()
      ..writeln('  /// Creates instance from JSON.')
      ..writeln('  ///')
      ..writeln(
          '  /// Note: For this schema, manual type validation is required.')
      ..writeln('  factory $className.fromJson(dynamic json) {')
      ..writeln('    if (json == null) {')
      ..writeln(
          '      throw ArgumentError(\'JSON cannot be null for $className\');')
      ..writeln('    }')
      ..writeln('    return $className(json);')
      ..writeln('  }')
      ..writeln()
      ..writeln('  /// Converts to JSON.')
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
          final enumName =
              context.getEnumTypeName(refSchema, ref.split('/').last);
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

    // Check for enum
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
            final valueType =
                _dartTypeForSchema(additionalProps, context, required: true);
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

    // Handle $ref
    final ref = schema[r'$ref'] as String?;
    if (ref != null) {
      final refSchema = context.resolveRef(ref, context: null);
      if (refSchema != null) {
        if (context.isEnum(refSchema)) {
          final enumName =
              context.getEnumTypeName(refSchema, ref.split('/').last);
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

    // Check for enum
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
          final itemExpr =
              _fromJsonExpression('e', items, context, isRequired: true);
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
            final valueExpr = _fromJsonExpression('v', additionalProps, context,
                isRequired: true);
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
    // Handle $ref
    final ref = schema[r'$ref'] as String?;
    if (ref != null) {
      final refSchema = context.resolveRef(ref, context: null);
      if (refSchema != null && context.isEnum(refSchema)) {
        return '$fieldName?.toJson()';
      }
      return '$fieldName?.toJson()';
    }

    // Check for enum
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
          return fieldName;
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
    if (parts.isEmpty) {
      return 'Unknown';
    }
    return parts.map((p) => p[0].toUpperCase() + p.substring(1)).join();
  }

  /// Builds a DartDoc comment block from description and example.
  ///
  /// Returns a string with lines starting with `///`, or an empty string
  /// if there is nothing to document.
  static String _buildDocComment({
    String? description,
    dynamic example,
  }) {
    final lines = <String>[];

    if (description != null && description.trim().isNotEmpty) {
      final descLines = description.trim().split('\n');
      for (final line in descLines) {
        final trimmed = line.trimRight();
        if (trimmed.isEmpty) {
          lines.add('///');
        } else {
          lines.add('/// $trimmed');
        }
      }
    }

    if (example != null) {
      if (lines.isNotEmpty) {
        lines.add('///');
      }
      final exampleString = example is String ? example : jsonEncode(example);
      lines.add('/// Example: $exampleString');
    }

    return lines.isEmpty ? '' : lines.join('\n');
  }

  /// Converts type name to lowerCamelCase for field/parameter names.
  static String _toCamelCase(String name) {
    if (name.isEmpty) return name;
    if (name.length == 1) return name.toLowerCase();
    return name[0].toLowerCase() + name.substring(1);
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
        if (properties.isEmpty &&
            (additionalProps == null || additionalProps == false)) {
          _reportLintIssue(
            LintRuleId.emptyObject,
            lintConfig,
            'Schema "$schemaName" is an empty object (no properties and additionalProperties).',
          );
        }
      }

      final properties =
          schema['properties'] as Map<String, dynamic>? ?? <String, dynamic>{};
      properties.forEach((propName, propSchemaRaw) {
        final propSchema = <String, dynamic>{
          ...?propSchemaRaw as Map<String, dynamic>?,
        };

        // Check for missing type
        if (lintConfig.isEnabled(LintRuleId.missingType)) {
          if (!propSchema.containsKey('type') &&
              !propSchema.containsKey(r'$ref')) {
            _reportLintIssue(
              LintRuleId.missingType,
              lintConfig,
              'Field "$propName" in schema "$schemaName" has no type and is not a reference (\$ref). '
              'Type dynamic will be generated.',
            );
          }
        }

        // Check for suspicious fields (e.g., id without nullable and without required)
        if (lintConfig.isEnabled(LintRuleId.suspiciousIdField)) {
          if (propName == 'id' ||
              propName.endsWith('_id') ||
              propName.endsWith('Id')) {
            final isNullable = propSchema['nullable'] as bool? ?? false;
            final isRequired =
                (schema['required'] as List?)?.contains(propName) ?? false;

            if (!isNullable && !isRequired) {
              _reportLintIssue(
                LintRuleId.suspiciousIdField,
                lintConfig,
                'Field "$propName" in schema "$schemaName" looks like an identifier, '
                'but is not marked as required and not nullable. '
                'Consider adding required: true or nullable: true.',
              );
            }
          }
        }

        // Check for $ref
        final propRef = propSchema[r'$ref'] as String?;
        if (propRef != null) {
          if (lintConfig.isEnabled(LintRuleId.missingRefTarget)) {
            final refSchema = context.resolveRef(propRef, context: schemaName);
            if (refSchema == null) {
              _reportLintIssue(
                LintRuleId.missingRefTarget,
                lintConfig,
                'Schema not found for reference "$propRef" in field "$propName" of schema "$schemaName". '
                'Check that the schema is defined in the specification.',
              );
            }
          }
        }

        // Check for type inconsistency
        if (lintConfig.isEnabled(LintRuleId.typeInconsistency)) {
          _checkTypeInconsistency(propSchema, propName, schemaName, lintConfig);
        }

        // Check for array without items
        if (lintConfig.isEnabled(LintRuleId.arrayWithoutItems)) {
          final propType = propSchema['type'] as String?;
          if (propType == 'array' && !propSchema.containsKey('items')) {
            _reportLintIssue(
              LintRuleId.arrayWithoutItems,
              lintConfig,
              'Field "$propName" in schema "$schemaName" has type array but contains no items. '
              'Type List<dynamic> will be generated.',
            );
          }
        }
      });
    });
  }

  /// Checks enum for issues.
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
          'Enum "$schemaName" contains no values.',
        );
      }
    }
  }

  /// Checks type inconsistency.
  static void _checkTypeInconsistency(
    Map<String, dynamic> propSchema,
    String propName,
    String schemaName,
    LintConfig lintConfig,
  ) {
    final propType = propSchema['type'] as String?;
    final format = propSchema['format'] as String?;
    final isNullable = propSchema['nullable'] as bool? ?? false;

    // Check: type: string, format: date-time, but not nullable
    // Usually date-time may be nullable in some cases
    if (propType == 'string' && format == 'date-time' && !isNullable) {
      // This is not necessarily an error, but might be a warning
      // Skip, as this is a common practice
    }

    // Check: type: integer, but format is specified (format is usually used for string)
    if (propType == 'integer' && format != null) {
      _reportLintIssue(
        LintRuleId.typeInconsistency,
        lintConfig,
        'Field "$propName" in schema "$schemaName" has type integer but format "$format" is specified. '
        'Format is usually used only for string type.',
      );
    }

    // Check: type: number, but format is specified (format is usually used for string)
    if (propType == 'number' &&
        format != null &&
        format != 'float' &&
        format != 'double') {
      _reportLintIssue(
        LintRuleId.typeInconsistency,
        lintConfig,
        'Field "$propName" in schema "$schemaName" has type number but format "$format" is specified. '
        'For number only format: float or double are allowed.',
      );
    }
  }

  /// Reports lint issue with severity level.
  static void _reportLintIssue(
    LintRuleId ruleId,
    LintConfig lintConfig,
    String message,
  ) {
    final severity = lintConfig.getSeverity(ruleId);
    switch (severity) {
      case LintSeverity.off:
        // Do not report
        break;
      case LintSeverity.warning:
        Logger.warning(message);
        break;
      case LintSeverity.error:
        Logger.error(message);
        break;
    }
  }

  /// Checks for missing $ref targets after generation.
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
          final contextMsg =
              parentName != null ? ' (in schema "$parentName")' : '';
          _reportLintIssue(
            LintRuleId.missingRefTarget,
            lintConfig,
            'Schema not found for reference "$schemaRef"$contextMsg. '
            'Check that the schema is defined in the specification.',
          );
        }
      }

      // Recursively check nested schemas
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
