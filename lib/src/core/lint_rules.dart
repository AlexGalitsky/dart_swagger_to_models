/// Уровень серьёзности lint правила.
enum LintSeverity {
  /// Отключено (не проверяется).
  off,

  /// Предупреждение (warning).
  warning,

  /// Ошибка (error).
  error,
}

/// Идентификаторы lint правил.
enum LintRuleId {
  /// Поле без типа и без $ref.
  missingType,

  /// Подозрительное id поле (без required и без nullable).
  suspiciousIdField,

  /// Отсутствующая цель для $ref.
  missingRefTarget,

  /// Несогласованность типов (например, type: string, но format: date-time без nullable).
  typeInconsistency,

  /// Пустой объект (properties пустой и нет additionalProperties).
  emptyObject,

  /// Массив без items.
  arrayWithoutItems,

  /// Enum без значений.
  emptyEnum,
}

/// Конфигурация lint правила.
class LintRuleConfig {
  /// Идентификатор правила.
  final LintRuleId id;

  /// Уровень серьёзности.
  final LintSeverity severity;

  /// Включено ли правило.
  bool get enabled => severity != LintSeverity.off;

  LintRuleConfig({
    required this.id,
    required this.severity,
  });

  /// Создаёт правило с уровнем по умолчанию.
  factory LintRuleConfig.defaultFor(LintRuleId id) {
    // По умолчанию все правила включены как warning, кроме критичных
    final defaultSeverity = switch (id) {
      LintRuleId.missingRefTarget => LintSeverity.error, // Критичная ошибка
      LintRuleId.missingType => LintSeverity.warning,
      LintRuleId.suspiciousIdField => LintSeverity.warning,
      LintRuleId.typeInconsistency => LintSeverity.warning,
      LintRuleId.emptyObject => LintSeverity.warning,
      LintRuleId.arrayWithoutItems => LintSeverity.warning,
      LintRuleId.emptyEnum => LintSeverity.warning,
    };
    return LintRuleConfig(id: id, severity: defaultSeverity);
  }

  /// Создаёт правило из строки (для парсинга конфига).
  factory LintRuleConfig.fromString(String idStr, String severityStr) {
    final id = _parseRuleId(idStr);
    final severity = parseSeverity(severityStr);
    return LintRuleConfig(id: id, severity: severity);
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

  /// Парсит уровень серьёзности из строки (публичный метод для использования в ConfigLoader).
  static LintSeverity parseSeverity(String str) {
    switch (str.toLowerCase()) {
      case 'off':
        return LintSeverity.off;
      case 'warning':
      case 'warn':
        return LintSeverity.warning;
      case 'error':
        return LintSeverity.error;
      default:
        throw Exception('Неизвестный уровень серьёзности: $str (ожидается: off, warning, error)');
    }
  }
}

/// Конфигурация всех lint правил.
class LintConfig {
  /// Правила с их конфигурацией.
  final Map<LintRuleId, LintRuleConfig> rules;

  LintConfig({Map<LintRuleId, LintRuleConfig>? rules})
      : rules = rules ??
            {
              // По умолчанию все правила включены
              for (final id in LintRuleId.values)
                id: LintRuleConfig.defaultFor(id),
            };

  /// Создаёт конфигурацию по умолчанию (все правила включены).
  factory LintConfig.defaultConfig() => LintConfig();

  /// Создаёт конфигурацию с отключёнными правилами.
  factory LintConfig.disabled() => LintConfig(
        rules: {
          for (final id in LintRuleId.values)
            id: LintRuleConfig(id: id, severity: LintSeverity.off),
        },
      );

  /// Получить конфигурацию правила.
  LintRuleConfig getRule(LintRuleId id) {
    return rules[id] ?? LintRuleConfig.defaultFor(id);
  }

  /// Проверить, включено ли правило.
  bool isEnabled(LintRuleId id) {
    return getRule(id).enabled;
  }

  /// Получить уровень серьёзности правила.
  LintSeverity getSeverity(LintRuleId id) {
    return getRule(id).severity;
  }

  /// Объединить с другой конфигурацией (other имеет приоритет).
  LintConfig merge(LintConfig other) {
    return LintConfig(
      rules: {
        ...rules,
        ...other.rules,
      },
    );
  }
}
