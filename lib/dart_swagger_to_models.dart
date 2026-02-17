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

export 'src/core/types.dart'
    show SpecVersion, GenerationStyle, GenerationResult, GenerationContext;
export 'src/config/config.dart' show Config, SchemaOverride;

/// Основной фасад библиотеки.
class SwaggerToDartGenerator {
  /// Загружает спецификацию из локального файла или по URL.
  static Future<Map<String, dynamic>> loadSpec(String source) async {
    if (source.startsWith('http://') || source.startsWith('https://')) {
      final response = await http.get(Uri.parse(source));
      if (response.statusCode >= 400) {
        throw Exception(
          'Не удалось загрузить спецификацию по URL $source '
          '(status: ${response.statusCode})',
        );
      }
      return _decodeSpec(response.body, sourceHint: source);
    }

    final file = File(source);
    if (!await file.exists()) {
      throw Exception('Файл спецификации не найден: $source');
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

  /// Определяет версию спецификации.
  static SpecVersion detectVersion(Map<String, dynamic> spec) {
    if (spec.containsKey('swagger')) {
      return SpecVersion.swagger2;
    }
    if (spec.containsKey('openapi')) {
      return SpecVersion.openApi3;
    }
    throw Exception('Не удалось определить версию спецификации (swagger/openapi).');
  }

  /// Генерирует Dart-модели: одна модель = один файл.
  ///
  /// [input] — путь к файлу или URL спецификации.
  /// [outputDir] — директория, куда будут записаны модели (по умолчанию `lib/models`).
  /// [libraryName] — исторический параметр (в per-file режиме практически не используется).
  /// [style] — стиль генерации моделей (plain_dart/json_serializable/freezed).
  /// [projectDir] — корневая директория проекта для сканирования Dart файлов
  ///                (поиск существующих файлов моделей с маркерами).
  /// [config] — конфигурация генератора (опционально).
  /// [changedOnly] — если true, генерирует только изменённые схемы (инкрементальная генерация).
  static Future<GenerationResult> generateModels({
    required String input,
    String? outputDir,
    String libraryName = 'models',
    GenerationStyle? style,
    String? projectDir,
    Config? config,
    bool changedOnly = false,
  }) async {
    // Применяем конфигурацию с приоритетом: параметры > config > значения по умолчанию
    final effectiveConfig = config ?? Config.empty();
    final effectiveOutputDir = outputDir ?? effectiveConfig.outputDir ?? 'lib/models';
    final effectiveStyle = style ?? effectiveConfig.defaultStyle ?? GenerationStyle.plainDart;
    final effectiveProjectDir = projectDir ?? effectiveConfig.projectDir ?? '.';

    final spec = await loadSpec(input);
    final version = detectVersion(spec);
    final schemas = _extractSchemas(spec, version);

    if (schemas.isEmpty) {
      throw Exception(
        'В спецификации не найдены схемы (definitions/components.schemas).',
      );
    }

    // Для правильной работы resolveRef нужно передать все схемы
    // Для Swagger 2.0 это definitions, для OpenAPI 3 это components.schemas
    final allSchemasMap = _getAllSchemas(spec, version);
    // Для resolveRef нужно структурировать схемы правильно
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

  /// Генерирует модели в режиме per-file (одна модель = один файл).
  static Future<GenerationResult> _generateModelsPerFile({
    required Map<String, dynamic> schemas,
    required GenerationContext context,
    required GenerationStyle style,
    required String outputDir,
    required String projectDir,
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

    // Загружаем кэш для инкрементальной генерации
    final cache = await GenerationCache.load(projectDir);
    final schemasToProcess = <String, Map<String, dynamic>>{};

    if (changedOnly && cache != null) {
      // Определяем, какие схемы изменились
      for (final entry in schemas.entries) {
        final schemaMap = (entry.value ?? {}) as Map<String, dynamic>;
        if (cache.hasChanged(entry.key, schemaMap)) {
          schemasToProcess[entry.key] = schemaMap;
          Logger.verbose('Схема "${entry.key}" изменилась, будет перегенерирована');
        } else {
          Logger.verbose('Схема "${entry.key}" не изменилась, пропускаем');
        }
      }

      // Проверяем удалённые схемы
      final currentSchemaNames = schemas.keys.toSet();
      final cachedSchemaNames = cache.cachedSchemas;
      final deletedSchemas = cachedSchemaNames.difference(currentSchemaNames);
      
      if (deletedSchemas.isNotEmpty) {
        Logger.verbose('Обнаружены удалённые схемы: ${deletedSchemas.join(", ")}');
        for (final deletedSchema in deletedSchemas) {
          cache.removeHash(deletedSchema);
          // Удаляем файл, если он существует
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
      // Режим полной генерации
      schemasToProcess.addAll(schemas.map((k, v) => MapEntry(k, (v ?? {}) as Map<String, dynamic>)));
    }

    // Сканируем проект для поиска существующих файлов с маркерами
    Logger.verbose('Сканирование проекта для поиска существующих файлов...');
    final existingFiles = await _scanProjectForMarkers(
      projectDir,
      outputDir,
    );
    Logger.verbose('Найдено существующих файлов: ${existingFiles.length}');

    // Проверяем схемы на подозрительные конструкции (только для обрабатываемых схем)
    final lintConfig = config?.lint ?? LintConfig.defaultConfig();
    _validateSchemas(schemasToProcess, context, lintConfig);

    // Сначала генерируем enum'ы
    final enumSchemas = <String, Map<String, dynamic>>{};
    schemasToProcess.forEach((name, schema) {
      final schemaMap = (schema ?? {}) as Map<String, dynamic>;
      if (context.isEnum(schemaMap)) {
        enumSchemas[name] = schemaMap;
      }
    });

    Logger.verbose('Найдено enum схем: ${enumSchemas.length}');

    int filesCreated = 0;
    int filesUpdated = 0;

    // Генерируем enum'ы в отдельные файлы
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
              )
            : _createNewFileWithEnum(
                entry.key,
                entry.value,
                context,
                style,
                fileName,
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

        // Обновляем кэш
        if (cache != null) {
          final hash = GenerationCache.computeSchemaHash(entry.value);
          cache.setHash(entry.key, hash);
        }
      } catch (e) {
        Logger.error('Ошибка при генерации enum "${entry.key}": $e');
        rethrow;
      }
    }

    // Затем генерируем классы в отдельные файлы
    final classSchemas = schemasToProcess.entries
        .where((e) => !context.isEnum((e.value ?? {}) as Map<String, dynamic>))
        .length;
    Logger.verbose('Найдено схем классов: $classSchemas');

    for (final entry in schemasToProcess.entries) {
      final schemaMap = (entry.value ?? {}) as Map<String, dynamic>;
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

          // Обновляем кэш
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

    // Обновляем кэш для всех схем (даже не изменённых, если changedOnly = false)
    if (cache != null && !changedOnly) {
      for (final entry in schemas.entries) {
        final schemaMap = (entry.value ?? {}) as Map<String, dynamic>;
        final hash = GenerationCache.computeSchemaHash(schemaMap);
        cache.setHash(entry.key, hash);
      }
    }

    // Сохраняем кэш
    if (cache != null) {
      await cache.save();
      Logger.verbose('Кэш сохранён в ${cache.cacheFilePath}');
    }

    // Проверяем отсутствующие $ref после генерации
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

  /// Сканирует проект для поиска Dart файлов с маркерами.
  /// Возвращает Map<ИмяМодели, СодержимоеФайла>.
  static Future<Map<String, String>> _scanProjectForMarkers(
    String projectDir,
    String outputDir,
  ) async {
    final result = <String, String>{};
    // Поддерживаем оба формата: /*SWAGGER-TO-DART*/ и /*SWAGGER-TO-DART:...*/ для обратной совместимости
    final markerPattern = RegExp(r'/\*SWAGGER-TO-DART(:[^*]*)?\*/');

    // Сначала сканируем outputDir
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
            // Игнорируем ошибки чтения файлов
          }
        }
      }
    }

    // Затем сканируем projectDir (рекурсивно)
    final projectDirectory = Directory(projectDir);
    if (await projectDirectory.exists()) {
      await for (final entity in projectDirectory.list(recursive: true)) {
        if (entity is File && entity.path.endsWith('.dart')) {
          // Пропускаем файлы из outputDir, так как мы их уже проверили
          if (p.isWithin(outputDir, entity.path)) {
            continue;
          }
          try {
            final content = await entity.readAsString();
            final match = markerPattern.firstMatch(content);
            if (match != null) {
              final fileName = p.basenameWithoutExtension(entity.path);
              final modelName = _toPascalCase(fileName);
              // Не перезаписываем, если уже есть в outputDir
              result.putIfAbsent(modelName, () => content);
            }
          } catch (_) {
            // Игнорируем ошибки чтения файлов
          }
        }
      }
    }

    return result;
  }

  /// Создаёт новый файл с enum.
  static String _createNewFileWithEnum(
    String enumName,
    Map<String, dynamic> schema,
    GenerationContext context,
    GenerationStyle style,
    String fileName,
  ) {
    final buffer = StringBuffer();
    buffer.writeln('/*SWAGGER-TO-DART*/');
    buffer.writeln();

    // Добавляем импорты и part'ы в зависимости от стиля
    // Для enum'ов импорты не нужны, но оставляем для консистентности
    final strategy = GeneratorFactory.createStrategy(style);
    final imports = strategy.generateImportsAndParts(fileName);
    for (final import in imports) {
      buffer.writeln(import);
    }
    if (imports.isNotEmpty) {
      buffer.writeln();
    }

    buffer.writeln('/*SWAGGER-TO-DART: Fields start*/');
    buffer.writeln();
    buffer.write(_generateEnum(enumName, schema, context));
    buffer.writeln();
    buffer.writeln('/*SWAGGER-TO-DART: Fields stop*/');

    return buffer.toString();
  }

  /// Собирает зависимости (типы, используемые в схеме) для генерации импортов.
  static Set<String> _collectDependencies(
    Map<String, dynamic> schema,
    GenerationContext context,
    String currentSchemaName,
    String outputDir,
  ) {
    final dependencies = <String>{};
    final visited = <String>{};

    void collectFromSchema(Map<String, dynamic> schemaMap, String? parentName) {
      // Обработка $ref
      final ref = schemaMap[r'$ref'] as String?;
      if (ref != null) {
        final refSchema = context.resolveRef(ref, context: parentName);
        if (refSchema != null) {
          final refName = ref.split('/').last;
          final refTypeName = _toPascalCase(refName);
          
          // Не добавляем зависимость на самого себя
          if (refTypeName != currentSchemaName && !visited.contains(refTypeName)) {
            visited.add(refTypeName);
            // Проверяем, что это не встроенный тип
            if (refSchema.containsKey('properties') || context.isEnum(refSchema)) {
              dependencies.add(refTypeName);
            }
            // Рекурсивно собираем зависимости из ref схемы
            collectFromSchema(refSchema, refTypeName);
          }
        }
      }

      // Обработка properties
      final properties = schemaMap['properties'] as Map<String, dynamic>?;
      if (properties != null) {
        properties.forEach((_, propSchema) {
          if (propSchema is Map<String, dynamic>) {
            collectFromSchema(propSchema, parentName);
          }
        });
      }

      // Обработка items (для массивов)
      final items = schemaMap['items'] as Map<String, dynamic>?;
      if (items != null) {
        collectFromSchema(items, parentName);
      }

      // Обработка additionalProperties
      final additionalProps = schemaMap['additionalProperties'];
      if (additionalProps is Map<String, dynamic>) {
        collectFromSchema(additionalProps, parentName);
      }

      // Обработка allOf
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

  /// Генерирует импорты для зависимостей.
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
      // Нормализуем путь для импорта (используем / вместо \)
      var importPath = relativePath.replaceAll(r'\', '/');
      // Убираем расширение .dart
      if (importPath.endsWith('.dart')) {
        importPath = importPath.substring(0, importPath.length - 5);
      }
      imports.add("import '$importPath';");
    }

    return imports..sort();
  }

  /// Создаёт новый файл с классом.
  static String _createNewFileWithClass(
    String className,
    Map<String, dynamic> schema,
    GenerationContext context,
    GenerationStyle style,
    String fileName,
    String outputDir, {
    Config? config,
    SchemaOverride? override,
  }) {
    final buffer = StringBuffer();
    buffer.writeln('/*SWAGGER-TO-DART*/');
    buffer.writeln();

    // Собираем зависимости для импортов
    final schemaName = override?.className ?? _toPascalCase(className);
    final dependencies = _collectDependencies(schema, context, schemaName, outputDir);
    final modelImports = _generateImportsForDependencies(dependencies, outputDir, '$fileName.dart');

    // Добавляем импорты и part'ы в зависимости от стиля
    final strategy = GeneratorFactory.createStrategy(style);
    final styleImports = strategy.generateImportsAndParts(fileName);
    
    // Объединяем импорты: сначала импорты моделей, потом стилевые
    final allImports = <String>[...modelImports, ...styleImports];
    for (final import in allImports) {
      buffer.writeln(import);
    }
    if (allImports.isNotEmpty) {
      buffer.writeln();
    }

    buffer.writeln('/*SWAGGER-TO-DART: Fields start*/');
    buffer.writeln();
    buffer.write(_generateClass(className, schema, context, style, config: config, override: override));
    buffer.writeln();
    buffer.writeln('/*SWAGGER-TO-DART: Fields stop*/');

    return buffer.toString();
  }

  /// Обновляет существующий файл с enum, заменяя содержимое между маркерами.
  static String _updateExistingFileWithEnum(
    String existingContent,
    String enumName,
    Map<String, dynamic> schema,
    GenerationContext context,
    GenerationStyle style,
  ) {
    final startMarker = '/*SWAGGER-TO-DART: Fields start*/';
    final stopMarker = '/*SWAGGER-TO-DART: Fields stop*/';

    final startIndex = existingContent.indexOf(startMarker);
    final stopIndex = existingContent.indexOf(stopMarker);

    if (startIndex == -1 || stopIndex == -1 || startIndex >= stopIndex) {
      // Маркеры не найдены, создаём новый файл
      return _createNewFileWithEnum(
        enumName,
        schema,
        context,
        style,
        _toSnakeCase(enumName),
      );
    }

    final before = existingContent.substring(0, startIndex + startMarker.length);
    final after = existingContent.substring(stopIndex);
    final newEnumCode = _generateEnum(enumName, schema, context);

    return '$before\n$newEnumCode\n$after';
  }

  /// Обновляет существующий файл с классом, заменяя содержимое между маркерами.
  static String _updateExistingFileWithClass(
    String existingContent,
    String className,
    Map<String, dynamic> schema,
    GenerationContext context,
    GenerationStyle style,
    String outputDir, {
    Config? config,
    SchemaOverride? override,
  }) {
    final startMarker = '/*SWAGGER-TO-DART: Fields start*/';
    final stopMarker = '/*SWAGGER-TO-DART: Fields stop*/';

    final startIndex = existingContent.indexOf(startMarker);
    final stopIndex = existingContent.indexOf(stopMarker);

    if (startIndex == -1 || stopIndex == -1 || startIndex >= stopIndex) {
      // Маркеры не найдены, создаём новый файл
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

  /// Преобразует имя в snake_case для имени файла.
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

    // Для OpenAPI 3 также добавляем components
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

    // Поддержка x-enumNames / x-enum-varnames
    final enumNames = schema['x-enumNames'] as List? ?? schema['x-enum-varnames'] as List?;
    final hasCustomNames = enumNames != null && enumNames.length == enumValues.length;

    final buffer = StringBuffer()
      ..writeln('enum $enumName {');

    for (var i = 0; i < enumValues.length; i++) {
      final value = enumValues[i];
      String enumValue;
      
      if (hasCustomNames && enumNames![i] is String) {
        // Используем кастомное имя из x-enumNames / x-enum-varnames
        enumValue = _toEnumValueName(enumNames[i] as String);
      } else if (value is String) {
        // Преобразуем строку в валидное имя enum значения
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
    // Преобразуем строку в валидное имя enum значения
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
    GenerationStyle style, {
    Config? config,
    SchemaOverride? override,
  }) {
    // Обработка allOf (OpenAPI 3)
    if (schema.containsKey('allOf') && schema['allOf'] is List) {
      return _generateAllOfClass(name, schema, context, style, config: config, override: override);
    }

    // Обработка oneOf/anyOf (OpenAPI 3)
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

    // Если объект только с additionalProperties и без properties — генерируем
    // одинаково для всех стилей.
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
        classBuffer.writeln('      data: json.map((k, v) => MapEntry(k, v)),');
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

    // Общая информация по полям
    final fieldInfos = <String, FieldInfo>{};

    properties.forEach((propName, propSchemaRaw) {
      final propSchema = (propSchemaRaw ?? {}) as Map<String, dynamic>;
      final propNullable = propSchema['nullable'] as bool? ?? false;

      // Правило nullable / required:
      // - Если поле присутствует в схеме, оно считается required по умолчанию.
      // - Если у поля явно указано nullable: true, оно генерируется как nullable.
      final isNonNullable = !propNullable;

      // Применяем переопределение имени поля, если есть
      final fieldName = override?.fieldNames?[propName] ?? propName;

      // Применяем маппинг типов, если есть
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
        jsonKey: propName, // Оригинальный JSON ключ
        dartType: dartType,
        isRequired: isNonNullable,
        schema: propSchema,
      );
    });

    // Определяем, нужно ли использовать @JsonKey
    // Приоритет: override.useJsonKey > config.useJsonKey > false
    final useJsonKey = override?.useJsonKey ?? config?.useJsonKey ?? false;

    // Используем стратегию для генерации класса
    final strategy = GeneratorFactory.createStrategy(style);
    return strategy.generateFullClass(
      className,
      fieldInfos,
      (jsonKey, schema) {
        // Определяем, является ли поле required на основе FieldInfo
        final fieldInfo = fieldInfos[jsonKey];
        final isRequired = fieldInfo?.isRequired ?? false;
        return _fromJsonExpression('json[\'$jsonKey\']', schema, context, isRequired: isRequired);
      },
      (fieldName, schema) => _toJsonExpression(fieldName, schema, context),
      useJsonKey: useJsonKey,
    );
  }

  /// Генерирует класс для allOf схемы.
  /// 
  /// Обрабатывает вложенные комбинации allOf и случаи множественного наследования.
  static String _generateAllOfClass(
    String name,
    Map<String, dynamic> schema,
    GenerationContext context,
    GenerationStyle style, {
    Config? config,
    SchemaOverride? override,
  }) {
    final allOf = schema['allOf'] as List;
    Logger.verbose('Обработка allOf для схемы "$name" (${allOf.length} элементов)');

    final allProperties = <String, dynamic>{};
    final allRequired = <String>[];
    final processedRefs = <String>{}; // Для предотвращения циклических зависимостей

    // Рекурсивная функция для обработки элементов allOf
    void processAllOfItem(dynamic item, String? parentName) {
      if (item is! Map<String, dynamic>) return;

      // Обработка $ref
      if (item.containsKey(r'$ref')) {
        final ref = item[r'$ref'] as String;
        
        // Проверка на циклические зависимости
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

        // Рекурсивно обрабатываем вложенные allOf
        if (refSchema.containsKey('allOf')) {
          final refAllOf = refSchema['allOf'] as List;
          Logger.verbose('Обнаружен вложенный allOf в $ref (${refAllOf.length} элементов)');
          for (final refItem in refAllOf) {
            processAllOfItem(refItem, ref.split('/').last);
          }
        } else {
          // Обрабатываем свойства из ref схемы
          final props = refSchema['properties'] as Map<String, dynamic>? ?? {};
          allProperties.addAll(props);
          final req = (refSchema['required'] as List?)?.cast<String>() ?? <String>[];
          allRequired.addAll(req);
        }

        processedRefs.remove(ref);
      } else {
        // Обработка обычных свойств
        final props = item['properties'] as Map<String, dynamic>? ?? {};
        allProperties.addAll(props);
        final req = (item['required'] as List?)?.cast<String>() ?? <String>[];
        allRequired.addAll(req);

        // Если элемент сам содержит allOf, обрабатываем рекурсивно
        if (item.containsKey('allOf')) {
          final nestedAllOf = item['allOf'] as List;
          Logger.verbose('Обнаружен вложенный allOf в элементе схемы "$name" (${nestedAllOf.length} элементов)');
          for (final nestedItem in nestedAllOf) {
            processAllOfItem(nestedItem, parentName);
          }
        }
      }
    }

    // Обрабатываем все элементы allOf
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

  /// Генерирует класс для oneOf/anyOf схем.
  /// 
  /// Для oneOf/anyOf генерируется безопасная обёртка с dynamic значением.
  /// В будущем здесь можно будет генерировать union-типы, особенно с discriminator.
  static String _generateOneOfClass(
    String name,
    Map<String, dynamic> schema,
    GenerationContext context, {
    List? oneOf,
    List? anyOf,
    SchemaOverride? override,
  }) {
    final className = override?.className ?? _toPascalCase(name);
    final hasOneOf = oneOf != null && oneOf.isNotEmpty;
    final hasAnyOf = anyOf != null && anyOf.isNotEmpty;
    
    // Определяем типы для логирования
    final possibleTypes = <String>[];
    if (hasOneOf) {
      for (final item in oneOf!) {
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
      for (final item in anyOf!) {
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

    // Проверяем наличие discriminator (для будущей поддержки union-типов)
    final discriminator = schema['discriminator'] as Map<String, dynamic>?;
    final hasDiscriminator = discriminator != null;
    
    if (hasDiscriminator) {
      final propertyName = discriminator['propertyName'] as String? ?? 'type';
      Logger.verbose(
        'Схема "$name" использует discriminator "$propertyName" для oneOf/anyOf. '
        'В будущих версиях будет поддержка генерации union-типов.',
      );
    }

    // Логируем информацию о возможных типах
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

    // Генерируем безопасную обёртку
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
    // Обработка $ref
    final ref = schema[r'$ref'] as String?;
    if (ref != null) {
      final refSchema = context.resolveRef(ref, context: null);
      if (refSchema != null) {
        // Проверяем, является ли это enum'ом
        if (context.isEnum(refSchema)) {
          final enumName = context.getEnumTypeName(refSchema, ref.split('/').last);
          if (enumName != null) {
            return required ? enumName : '$enumName?';
          }
        }
        // Иначе это класс
        final refName = ref.split('/').last;
        final baseType = _toPascalCase(refName);
        return required ? baseType : '$baseType?';
      }
      // Если не удалось разрешить, используем имя из ref
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
        // Различаем int и num
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
          // Массив без items - генерируем List<dynamic>
          base = 'List<dynamic>';
        }
        break;
      case 'object':
        // Проверяем, есть ли additionalProperties
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

    // Поле non-nullable только если required=true И nullable=false
    // required уже учитывает nullable из схемы, поэтому просто используем required
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

  /// Проверяет схемы на подозрительные конструкции.
  static void _validateSchemas(
    Map<String, dynamic> schemas,
    GenerationContext context,
    LintConfig lintConfig,
  ) {
    schemas.forEach((schemaName, schemaRaw) {
      final schema = (schemaRaw ?? {}) as Map<String, dynamic>;
      
      // Проверка enum'ов (включая пустые)
      final enumValues = schema['enum'] as List?;
      if (enumValues != null) {
        _validateEnum(schema, schemaName, lintConfig);
        // Если это enum, не проверяем как обычную схему
        if (context.isEnum(schema)) {
          return;
        }
      }

              // Проверка пустого объекта (только для не-enum схем и не-oneOf/anyOf/allOf)
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

      final properties = schema['properties'] as Map<String, dynamic>? ?? {};
      properties.forEach((propName, propSchemaRaw) {
        final propSchema = (propSchemaRaw ?? {}) as Map<String, dynamic>;
        
        // Проверка на отсутствие type
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

        // Проверка на подозрительные поля (например, id без nullable и без required)
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
      final schema = (schemaRaw ?? {}) as Map<String, dynamic>;
      checkSchema(schema, schemaName);
    });
  }
}
