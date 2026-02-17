import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../core/lint_rules.dart';
import '../core/types.dart';
import 'config.dart';

/// Загрузчик конфигурации из YAML файла.
class ConfigLoader {
  /// Загружает конфигурацию из файла.
  ///
  /// [configPath] - путь к конфигурационному файлу.
  /// Если [configPath] равен null, ищет `dart_swagger_to_models.yaml` в корне проекта.
  static Future<Config> loadConfig(String? configPath, String projectDir) async {
    String? actualPath = configPath;

    // Если путь не указан, ищем файл в корне проекта
    if (actualPath == null) {
      final defaultPath = p.join(projectDir, 'dart_swagger_to_models.yaml');
      final file = File(defaultPath);
      if (await file.exists()) {
        actualPath = defaultPath;
      } else {
        return Config.empty();
      }
    }

    final file = File(actualPath);
    if (!await file.exists()) {
      throw Exception('Конфигурационный файл не найден: $actualPath');
    }

    final content = await file.readAsString();
    return _parseConfig(content);
  }

  /// Парсит YAML конфигурацию.
  static Config _parseConfig(String yamlContent) {
    try {
      final yaml = loadYaml(yamlContent) as Map?;
      if (yaml == null) {
        return Config.empty();
      }

      // Парсим глобальные опции
      GenerationStyle? defaultStyle;
      String? customStyleName;
      if (yaml['defaultStyle'] != null) {
        final styleStr = yaml['defaultStyle'] as String;
        // Пытаемся распарсить как встроенный стиль
        try {
          defaultStyle = _parseStyle(styleStr);
        } catch (e) {
          // Если не встроенный стиль, считаем кастомным
          customStyleName = styleStr;
        }
      }

      final outputDir = yaml['outputDir'] as String?;
      final projectDir = yaml['projectDir'] as String?;
      final useJsonKey = yaml['useJsonKey'] as bool?;

      // Парсим lint конфигурацию
      LintConfig? lintConfig;
      final lint = yaml['lint'] as Map?;
      if (lint != null) {
        lintConfig = _parseLintConfig(lint);
      }

      // Парсим переопределения для схем
      final schemaOverrides = <String, SchemaOverride>{};
      final schemas = yaml['schemas'] as Map?;
      if (schemas != null) {
        schemas.forEach((schemaName, overrideData) {
          if (overrideData is Map) {
            schemaOverrides[schemaName.toString()] = _parseSchemaOverride(overrideData);
          }
        });
      }

      return Config(
        defaultStyle: defaultStyle,
        customStyleName: customStyleName,
        outputDir: outputDir,
        projectDir: projectDir,
        useJsonKey: useJsonKey,
        lint: lintConfig,
        schemaOverrides: schemaOverrides,
      );
    } catch (e) {
      throw Exception('Ошибка парсинга конфигурационного файла: $e');
    }
  }

  /// Парсит стиль генерации из строки.
  static GenerationStyle? _parseStyle(String styleStr) {
    switch (styleStr.toLowerCase()) {
      case 'plain_dart':
        return GenerationStyle.plainDart;
      case 'json_serializable':
        return GenerationStyle.jsonSerializable;
      case 'freezed':
        return GenerationStyle.freezed;
      default:
        throw Exception('Неизвестный стиль генерации: $styleStr');
    }
  }

  /// Парсит переопределение для схемы.
  static SchemaOverride _parseSchemaOverride(Map overrideData) {
    final className = overrideData['className'] as String?;
    final fieldNames = overrideData['fieldNames'] as Map?;
    final typeMapping = overrideData['typeMapping'] as Map?;
    final useJsonKey = overrideData['useJsonKey'] as bool?;

    final fieldNamesMap = <String, String>{};
    if (fieldNames != null) {
      fieldNames.forEach((key, value) {
        fieldNamesMap[key.toString()] = value.toString();
      });
    }

    final typeMappingMap = <String, String>{};
    if (typeMapping != null) {
      typeMapping.forEach((key, value) {
        typeMappingMap[key.toString()] = value.toString();
      });
    }

    return SchemaOverride(
      className: className,
      fieldNames: fieldNamesMap.isNotEmpty ? fieldNamesMap : null,
      typeMapping: typeMappingMap.isNotEmpty ? typeMappingMap : null,
      useJsonKey: useJsonKey,
    );
  }

  /// Парсит конфигурацию lint правил.
  static LintConfig _parseLintConfig(Map lintData) {
    final rules = <LintRuleId, LintRuleConfig>{};

    // Если указан 'enabled: false', отключаем все правила
    final enabled = lintData['enabled'] as bool? ?? true;
    if (!enabled) {
      return LintConfig.disabled();
    }

    // Парсим правила
    final rulesData = lintData['rules'] as Map?;
    if (rulesData != null) {
      rulesData.forEach((ruleIdStr, ruleConfig) {
        if (ruleConfig is String) {
          // Простой формат: "missing_type: warning"
          final ruleId = _parseRuleId(ruleIdStr.toString());
          final severity = LintRuleConfig.parseSeverity(ruleConfig);
          rules[ruleId] = LintRuleConfig(id: ruleId, severity: severity);
        } else if (ruleConfig is Map) {
          // Расширенный формат: "missing_type: { severity: warning }"
          final ruleId = _parseRuleId(ruleIdStr.toString());
          final severityStr = ruleConfig['severity'] as String? ?? 'warning';
          final severity = LintRuleConfig.parseSeverity(severityStr);
          rules[ruleId] = LintRuleConfig(id: ruleId, severity: severity);
        }
      });
    }

    // Создаём конфигурацию по умолчанию и применяем переопределения
    final defaultConfig = LintConfig.defaultConfig();
    if (rules.isEmpty) {
      return defaultConfig;
    }

    return LintConfig(
      rules: {
        ...defaultConfig.rules,
        ...rules,
      },
    );
  }

  static LintRuleId _parseRuleId(String str) {
    switch (str.toLowerCase()) {
      case 'missing_type':
      case 'missing-type':
        return LintRuleId.missingType;
      case 'suspicious_id_field':
      case 'suspicious-id-field':
        return LintRuleId.suspiciousIdField;
      case 'missing_ref_target':
      case 'missing-ref-target':
        return LintRuleId.missingRefTarget;
      case 'type_inconsistency':
      case 'type-inconsistency':
        return LintRuleId.typeInconsistency;
      case 'empty_object':
      case 'empty-object':
        return LintRuleId.emptyObject;
      case 'array_without_items':
      case 'array-without-items':
        return LintRuleId.arrayWithoutItems;
      case 'empty_enum':
      case 'empty-enum':
        return LintRuleId.emptyEnum;
      default:
        throw Exception('Неизвестное lint правило: $str');
    }
  }
}
