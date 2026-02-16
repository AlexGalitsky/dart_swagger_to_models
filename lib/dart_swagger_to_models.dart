import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// Тип Swagger/OpenAPI-спецификации.
enum SpecVersion { swagger2, openApi3 }

/// Результат генерации моделей.
class GenerationResult {
  final String outputDirectory;
  final List<String> generatedFiles;

  GenerationResult({
    required this.outputDirectory,
    required this.generatedFiles,
  });
}

/// Контекст генерации для хранения всех схем и enum'ов.
class GenerationContext {
  final Map<String, dynamic> allSchemas;
  final SpecVersion version;
  final Map<String, String> enumTypes = {};
  final Set<String> generatedEnums = {};
  final Set<String> generatedClasses = {};

  GenerationContext({
    required this.allSchemas,
    required this.version,
  });

  /// Получить схему по $ref.
  Map<String, dynamic>? resolveRef(String ref) {
    final parts = ref.split('/');
    if (parts.isEmpty) return null;

    // Убираем # если есть
    final cleanParts = parts.where((p) => p.isNotEmpty && p != '#').toList();

    Map<String, dynamic> current = allSchemas;
    for (var i = 0; i < cleanParts.length; i++) {
      final key = cleanParts[i];
      if (i == cleanParts.length - 1) {
        final result = current[key];
        if (result is Map<String, dynamic>) {
          return result;
        }
      } else {
        final next = current[key];
        if (next is Map<String, dynamic>) {
          current = next;
        } else {
          return null;
        }
      }
    }
    return null;
  }

  /// Проверить, является ли схема enum'ом.
  bool isEnum(Map<String, dynamic> schema) {
    final enumValues = schema['enum'] as List?;
    return enumValues != null && enumValues.isNotEmpty;
  }

  /// Получить имя enum типа для схемы.
  String? getEnumTypeName(Map<String, dynamic> schema, String? suggestedName) {
    if (!isEnum(schema)) return null;
    final enumValues = schema['enum'] as List?;
    if (enumValues == null || enumValues.isEmpty) return null;

    if (suggestedName != null && enumTypes.containsKey(suggestedName)) {
      return enumTypes[suggestedName];
    }

    // Генерируем уникальное имя для enum
    String baseName = suggestedName ?? 'Enum';
    int counter = 1;
    String enumName = baseName;
    while (enumTypes.containsKey(enumName) || generatedEnums.contains(enumName)) {
      enumName = '$baseName$counter';
      counter++;
    }

    enumTypes[enumName] = enumName;
    return enumName;
  }
}

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

  /// Генерирует Dart-модели в указанную директорию.
  ///
  /// [input] — путь к файлу или URL спецификации.
  /// [outputDir] — директория, куда будут записаны модели (по умолчанию `lib/models`).
  /// [libraryName] — имя библиотеки/файла (по умолчанию `models.dart`).
  static Future<GenerationResult> generateModels({
    required String input,
    String outputDir = 'lib/models',
    String libraryName = 'models.dart',
  }) async {
    final spec = await loadSpec(input);
    final version = detectVersion(spec);
    final schemas = _extractSchemas(spec, version);

    if (schemas.isEmpty) {
      throw Exception(
        'В спецификации не найдены схемы (definitions/components.schemas).',
      );
    }

    final context = GenerationContext(
      allSchemas: _getAllSchemas(spec, version),
      version: version,
    );

    final buffer = StringBuffer()
      ..writeln('// GENERATED CODE - DO NOT MODIFY BY HAND')
      ..writeln('// ignore_for_file: public_member_api_docs')
      ..writeln()
      ..writeln('library $libraryName;')
      ..writeln();

    // Сначала генерируем все enum'ы
    final enumSchemas = <String, Map<String, dynamic>>{};
    schemas.forEach((name, schema) {
      final schemaMap = (schema ?? {}) as Map<String, dynamic>;
      if (context.isEnum(schemaMap)) {
        enumSchemas[name] = schemaMap;
      }
    });

    // Генерируем enum'ы
    enumSchemas.forEach((name, schema) {
      final enumCode = _generateEnum(name, schema, context);
      if (enumCode.isNotEmpty) {
        buffer.writeln(enumCode);
        buffer.writeln();
        context.generatedEnums.add(_toPascalCase(name));
      }
    });

    // Затем генерируем классы
    schemas.forEach((name, schema) {
      final schemaMap = (schema ?? {}) as Map<String, dynamic>;
      if (!context.isEnum(schemaMap)) {
        final classCode = _generateClass(name, schemaMap, context);
        if (classCode.isNotEmpty) {
          buffer.writeln(classCode);
          buffer.writeln();
          context.generatedClasses.add(_toPascalCase(name));
        }
      }
    });

    final outDir = Directory(outputDir);
    if (!await outDir.exists()) {
      await outDir.create(recursive: true);
    }

    final filePath = p.join(outputDir, '$libraryName.dart');
    final outFile = File(filePath);
    await outFile.writeAsString(buffer.toString());

    return GenerationResult(
      outputDirectory: outputDir,
      generatedFiles: [filePath],
    );
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

    final buffer = StringBuffer()
      ..writeln('enum $enumName {');

    for (var i = 0; i < enumValues.length; i++) {
      final value = enumValues[i];
      String enumValue;
      if (value is String) {
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
  ) {
    // Обработка allOf (OpenAPI 3)
    if (schema.containsKey('allOf') && schema['allOf'] is List) {
      return _generateAllOfClass(name, schema, context);
    }

    // Обработка oneOf/anyOf (OpenAPI 3) - пока генерируем как dynamic
    if (schema.containsKey('oneOf') || schema.containsKey('anyOf')) {
      return _generateOneOfClass(name, schema, context);
    }

    final className = _toPascalCase(name);
    final properties = schema['properties'] as Map<String, dynamic>? ?? {};
    final requiredProps = (schema['required'] as List?)?.cast<String>() ?? const <String>[];
    final nullable = schema['nullable'] as bool? ?? false;
    final additionalProps = schema['additionalProperties'];

    // Если объект только с additionalProperties и без properties
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
        final valueExpr = _fromJsonExpression('v', additionalProps, context);
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

    final classBuffer = StringBuffer()
      ..writeln('class $className {');

    // Поля
    properties.forEach((propName, propSchemaRaw) {
      final propSchema = (propSchemaRaw ?? {}) as Map<String, dynamic>;
      final isRequired = requiredProps.contains(propName);
      final propNullable = propSchema['nullable'] as bool? ?? false;
      final isActuallyRequired = isRequired && !propNullable && !nullable;
      
      final type = _dartTypeForSchema(propSchema, context, required: isActuallyRequired);
      final fieldName = _toCamelCase(propName);
      classBuffer.writeln('  final $type $fieldName;');
    });

    classBuffer.writeln();

    // Конструктор
    classBuffer.writeln('  const $className({');
    properties.forEach((propName, propSchemaRaw) {
      final propSchema = (propSchemaRaw ?? {}) as Map<String, dynamic>;
      final isRequired = requiredProps.contains(propName);
      final propNullable = propSchema['nullable'] as bool? ?? false;
      final isActuallyRequired = isRequired && !propNullable && !nullable;
      
      final type = _dartTypeForSchema(propSchema, context, required: isActuallyRequired);
      final fieldName = _toCamelCase(propName);
      final prefix = isActuallyRequired ? 'required ' : '';
      classBuffer.writeln('    $prefix this.$fieldName,');
    });
    classBuffer.writeln('  });');
    classBuffer.writeln();

    // fromJson
    classBuffer.writeln('  factory $className.fromJson(Map<String, dynamic> json) {');
    classBuffer.writeln('    return $className(');
    properties.forEach((propName, propSchemaRaw) {
      final propSchema = (propSchemaRaw ?? {}) as Map<String, dynamic>;
      final fieldName = _toCamelCase(propName);
      final jsonKey = propName;
      final assign = _fromJsonExpression('json[\'$jsonKey\']', propSchema, context);
      classBuffer.writeln('      $fieldName: $assign,');
    });
    classBuffer.writeln('    );');
    classBuffer.writeln('  }');
    classBuffer.writeln();

    // toJson
    classBuffer.writeln('  Map<String, dynamic> toJson() {');
    classBuffer.writeln('    return <String, dynamic>{');
    properties.forEach((propName, propSchemaRaw) {
      final propSchema = (propSchemaRaw ?? {}) as Map<String, dynamic>;
      final fieldName = _toCamelCase(propName);
      final jsonKey = propName;
      final assign = _toJsonExpression(fieldName, propSchema, context);
      classBuffer.writeln('      \'$jsonKey\': $assign,');
    });
    classBuffer.writeln('    };');
    classBuffer.writeln('  }');

    classBuffer.writeln('}');

    return classBuffer.toString();
  }

  static String _generateAllOfClass(
    String name,
    Map<String, dynamic> schema,
    GenerationContext context,
  ) {
    final className = _toPascalCase(name);
    final allOf = schema['allOf'] as List;
    final allProperties = <String, dynamic>{};
    final allRequired = <String>[];

    for (final item in allOf) {
      if (item is Map<String, dynamic>) {
        // Обработка $ref
        if (item.containsKey(r'$ref')) {
          final ref = item[r'$ref'] as String;
          final refSchema = context.resolveRef(ref);
          if (refSchema != null) {
            // Рекурсивно обрабатываем allOf в ref
            if (refSchema.containsKey('allOf')) {
              final refAllOf = refSchema['allOf'] as List;
              for (final refItem in refAllOf) {
                if (refItem is Map<String, dynamic>) {
                  if (refItem.containsKey(r'$ref')) {
                    final nestedRef = refItem[r'$ref'] as String;
                    final nestedSchema = context.resolveRef(nestedRef);
                    if (nestedSchema != null) {
                      final props = nestedSchema['properties'] as Map<String, dynamic>? ?? {};
                      allProperties.addAll(props);
                      final req = (nestedSchema['required'] as List?)?.cast<String>() ?? <String>[];
                      allRequired.addAll(req);
                    }
                  } else {
                    final props = refItem['properties'] as Map<String, dynamic>? ?? {};
                    allProperties.addAll(props);
                    final req = (refItem['required'] as List?)?.cast<String>() ?? <String>[];
                    allRequired.addAll(req);
                  }
                }
              }
            } else {
              final props = refSchema['properties'] as Map<String, dynamic>? ?? {};
              allProperties.addAll(props);
              final req = (refSchema['required'] as List?)?.cast<String>() ?? <String>[];
              allRequired.addAll(req);
            }
          }
        } else {
          // Обработка обычных свойств
          final props = item['properties'] as Map<String, dynamic>? ?? {};
          allProperties.addAll(props);
          final req = (item['required'] as List?)?.cast<String>() ?? <String>[];
          allRequired.addAll(req);
        }
      }
    }

    final classBuffer = StringBuffer()
      ..writeln('class $className {');

    // Поля
    allProperties.forEach((propName, propSchemaRaw) {
      final propSchema = (propSchemaRaw ?? {}) as Map<String, dynamic>;
      final isRequired = allRequired.contains(propName);
      final propNullable = propSchema['nullable'] as bool? ?? false;
      final isActuallyRequired = isRequired && !propNullable;
      
      final type = _dartTypeForSchema(propSchema, context, required: isActuallyRequired);
      final fieldName = _toCamelCase(propName);
      classBuffer.writeln('  final $type $fieldName;');
    });

    classBuffer.writeln();

    // Конструктор
    classBuffer.writeln('  const $className({');
    allProperties.forEach((propName, propSchemaRaw) {
      final propSchema = (propSchemaRaw ?? {}) as Map<String, dynamic>;
      final isRequired = allRequired.contains(propName);
      final propNullable = propSchema['nullable'] as bool? ?? false;
      final isActuallyRequired = isRequired && !propNullable;
      
      final type = _dartTypeForSchema(propSchema, context, required: isActuallyRequired);
      final fieldName = _toCamelCase(propName);
      final prefix = isActuallyRequired ? 'required ' : '';
      classBuffer.writeln('    $prefix this.$fieldName,');
    });
    classBuffer.writeln('  });');
    classBuffer.writeln();

    // fromJson
    classBuffer.writeln('  factory $className.fromJson(Map<String, dynamic> json) {');
    classBuffer.writeln('    return $className(');
    allProperties.forEach((propName, propSchemaRaw) {
      final propSchema = (propSchemaRaw ?? {}) as Map<String, dynamic>;
      final fieldName = _toCamelCase(propName);
      final jsonKey = propName;
      final assign = _fromJsonExpression('json[\'$jsonKey\']', propSchema, context);
      classBuffer.writeln('      $fieldName: $assign,');
    });
    classBuffer.writeln('    );');
    classBuffer.writeln('  }');
    classBuffer.writeln();

    // toJson
    classBuffer.writeln('  Map<String, dynamic> toJson() {');
    classBuffer.writeln('    return <String, dynamic>{');
    allProperties.forEach((propName, propSchemaRaw) {
      final propSchema = (propSchemaRaw ?? {}) as Map<String, dynamic>;
      final fieldName = _toCamelCase(propName);
      final jsonKey = propName;
      final assign = _toJsonExpression(fieldName, propSchema, context);
      classBuffer.writeln('      \'$jsonKey\': $assign,');
    });
    classBuffer.writeln('    };');
    classBuffer.writeln('  }');

    classBuffer.writeln('}');

    return classBuffer.toString();
  }

  static String _generateOneOfClass(
    String name,
    Map<String, dynamic> schema,
    GenerationContext context,
  ) {
    final className = _toPascalCase(name);
    // Для oneOf/anyOf пока генерируем простой класс с dynamic
    return '''
class $className {
  final dynamic value;

  const $className(this.value);

  factory $className.fromJson(dynamic json) {
    return $className(json);
  }

  dynamic toJson() => value;
}
''';
  }

  static String _dartTypeForSchema(
    Map<String, dynamic> schema,
    GenerationContext context, {
    required bool required,
  }) {
    // Обработка $ref
    final ref = schema[r'$ref'] as String?;
    if (ref != null) {
      final refSchema = context.resolveRef(ref);
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
    final nullable = schema['nullable'] as bool? ?? false;

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
        final items = (schema['items'] ?? {}) as Map<String, dynamic>;
        final itemType = _dartTypeForSchema(items, context, required: true);
        base = 'List<$itemType>';
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

    final isActuallyRequired = required && !nullable;
    return isActuallyRequired ? base : '$base?';
  }

  static String _fromJsonExpression(
    String source,
    Map<String, dynamic> schema,
    GenerationContext context,
  ) {
    // Обработка $ref
    final ref = schema[r'$ref'] as String?;
    if (ref != null) {
      final refSchema = context.resolveRef(ref);
      if (refSchema != null) {
        if (context.isEnum(refSchema)) {
          final enumName = context.getEnumTypeName(refSchema, ref.split('/').last);
          if (enumName != null) {
            return '$enumName.fromJson($source)';
          }
        }
        final refName = ref.split('/').last;
        final type = _toPascalCase(refName);
        return '$source == null ? null : $type.fromJson($source as Map<String, dynamic>)';
      }
      final refName = ref.split('/').last;
      final type = _toPascalCase(refName);
      return '$source == null ? null : $type.fromJson($source as Map<String, dynamic>)';
    }

    // Проверка на enum
    if (context.isEnum(schema)) {
      final enumName = context.getEnumTypeName(schema, null);
      if (enumName != null) {
        return '$enumName.fromJson($source)';
      }
    }

    final type = schema['type'] as String?;
    final format = schema['format'] as String?;
    final nullable = schema['nullable'] as bool? ?? false;

    switch (type) {
      case 'array':
        final items = (schema['items'] ?? {}) as Map<String, dynamic>;
        final itemExpr = _fromJsonExpression('e', items, context);
        if (nullable) {
          return '$source == null ? null : ($source as List<dynamic>).map((e) => $itemExpr).toList()';
        } else {
          return '($source as List<dynamic>?)?.map((e) => $itemExpr).toList() ?? []';
        }
      case 'string':
        if (format == 'date-time' || format == 'date') {
          return nullable
              ? '$source == null ? null : DateTime.parse($source as String)'
              : '$source == null ? null : DateTime.parse($source as String)';
        }
        return '$source as String?';
      case 'integer':
        return nullable
            ? '$source == null ? null : ($source as num?)?.toInt()'
            : '($source as num?)?.toInt()';
      case 'number':
        return '$source as num?';
      case 'boolean':
        return '$source as bool?';
      case 'object':
        final additionalProps = schema['additionalProperties'];
        if (additionalProps != null && additionalProps != false) {
          if (additionalProps is Map<String, dynamic>) {
            final valueType = _dartTypeForSchema(additionalProps, context, required: true);
            final valueExpr = _fromJsonExpression('v', additionalProps, context);
            return nullable
                ? '$source == null ? null : ($source as Map<String, dynamic>).map((k, v) => MapEntry(k, $valueExpr))'
                : '($source as Map<String, dynamic>?)?.map((k, v) => MapEntry(k, $valueExpr)) ?? <String, $valueType>{}';
          }
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
      final refSchema = context.resolveRef(ref);
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
        final items = (schema['items'] ?? {}) as Map<String, dynamic>;
        final inner = _toJsonExpression('e', items, context);
        return '$fieldName?.map((e) => $inner).toList()';
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

  static String _toCamelCase(String name) {
    final pascal = _toPascalCase(name);
    if (pascal.isEmpty) return '';
    return pascal[0].toLowerCase() + pascal.substring(1);
  }
}
