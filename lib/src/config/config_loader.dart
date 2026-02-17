import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../core/lint_rules.dart';
import '../core/types.dart';
import 'config.dart';

/// Loader for generator configuration from YAML file.
class ConfigLoader {
  /// Loads configuration from a file.
  ///
  /// [configPath] - path to the configuration file.
  /// If [configPath] is null, tries to find `dart_swagger_to_models.yaml` in project root.
  static Future<Config> loadConfig(
      String? configPath, String projectDir) async {
    String? actualPath = configPath;

    // If path is not provided, search file in project root
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
      throw Exception('Configuration file not found: $actualPath');
    }

    final content = await file.readAsString();
    return _parseConfig(content);
  }

  /// Parses YAML configuration.
  static Config _parseConfig(String yamlContent) {
    try {
      final yaml = loadYaml(yamlContent) as Map?;
      if (yaml == null) {
        return Config.empty();
      }

      // Parse global options
      GenerationStyle? defaultStyle;
      String? customStyleName;
      if (yaml['defaultStyle'] != null) {
        final styleStr = yaml['defaultStyle'] as String;
        // Try to parse as built-in style
        try {
          defaultStyle = _parseStyle(styleStr);
        } catch (e) {
          // If not a built-in style, treat as custom style
          customStyleName = styleStr;
        }
      }

      final outputDir = yaml['outputDir'] as String?;
      final projectDir = yaml['projectDir'] as String?;
      final useJsonKey = yaml['useJsonKey'] as bool?;
      final generateDocs = yaml['generateDocs'] as bool?;
      final generateValidation = yaml['generateValidation'] as bool?;
      final generateTestData = yaml['generateTestData'] as bool?;

      // Parse lint configuration
      LintConfig? lintConfig;
      final lint = yaml['lint'] as Map?;
      if (lint != null) {
        lintConfig = _parseLintConfig(lint);
      }

      // Parse schema overrides
      final schemaOverrides = <String, SchemaOverride>{};
      final schemas = yaml['schemas'] as Map?;
      if (schemas != null) {
        schemas.forEach((schemaName, overrideData) {
          if (overrideData is Map) {
            schemaOverrides[schemaName.toString()] =
                _parseSchemaOverride(overrideData);
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
        generateDocs: generateDocs,
        generateValidation: generateValidation,
        generateTestData: generateTestData,
        schemaOverrides: schemaOverrides,
      );
    } catch (e) {
      throw Exception('Error parsing configuration file: $e');
    }
  }

  /// Parses generation style from string.
  static GenerationStyle? _parseStyle(String styleStr) {
    switch (styleStr.toLowerCase()) {
      case 'plain_dart':
        return GenerationStyle.plainDart;
      case 'json_serializable':
        return GenerationStyle.jsonSerializable;
      case 'freezed':
        return GenerationStyle.freezed;
      default:
        throw Exception('Unknown generation style: $styleStr');
    }
  }

  /// Parses overrides for a single schema.
  static SchemaOverride _parseSchemaOverride(
      Map<dynamic, dynamic> overrideData) {
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

  /// Parses lint rules configuration.
  static LintConfig _parseLintConfig(Map<dynamic, dynamic> lintData) {
    final rules = <LintRuleId, LintRuleConfig>{};

    // If 'enabled: false' is specified, disable all rules
    final enabled = lintData['enabled'] as bool? ?? true;
    if (!enabled) {
      return LintConfig.disabled();
    }

    // Parse individual rules
    final rulesData = lintData['rules'] as Map?;
    if (rulesData != null) {
      rulesData.forEach((ruleIdStr, ruleConfig) {
        if (ruleConfig is String) {
          // Simple format: "missing_type: warning"
          final ruleId = _parseRuleId(ruleIdStr.toString());
          final severity = LintRuleConfig.parseSeverity(ruleConfig);
          rules[ruleId] = LintRuleConfig(id: ruleId, severity: severity);
        } else if (ruleConfig is Map) {
          // Extended format: "missing_type: { severity: warning }"
          final ruleId = _parseRuleId(ruleIdStr.toString());
          final severityStr = ruleConfig['severity'] as String? ?? 'warning';
          final severity = LintRuleConfig.parseSeverity(severityStr);
          rules[ruleId] = LintRuleConfig(id: ruleId, severity: severity);
        }
      });
    }

    // Create default configuration and apply overrides
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
        throw Exception('Unknown lint rule: $str');
    }
  }
}
