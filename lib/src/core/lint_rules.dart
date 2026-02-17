/// Severity level of a lint rule.
enum LintSeverity {
  /// Rule is disabled (not checked).
  off,

  /// Warning.
  warning,

  /// Error.
  error,
}

/// Identifiers of lint rules.
enum LintRuleId {
  /// Field without type and without $ref.
  missingType,

  /// Suspicious id field (without required and without nullable).
  suspiciousIdField,

  /// Missing target for $ref.
  missingRefTarget,

  /// Type inconsistency (for example, type: string but format: date-time without nullable).
  typeInconsistency,

  /// Empty object (no properties and no additionalProperties).
  emptyObject,

  /// Array without items.
  arrayWithoutItems,

  /// Enum without values.
  emptyEnum,
}

/// Configuration for a single lint rule.
class LintRuleConfig {
  /// Rule identifier.
  final LintRuleId id;

  /// Severity level.
  final LintSeverity severity;

  /// Whether the rule is enabled.
  bool get enabled => severity != LintSeverity.off;

  LintRuleConfig({
    required this.id,
    required this.severity,
  });

  /// Creates a rule with a default severity.
  factory LintRuleConfig.defaultFor(LintRuleId id) {
    // By default all rules are enabled as warning, except critical ones
    final defaultSeverity = switch (id) {
      LintRuleId.missingRefTarget => LintSeverity.error, // Critical error
      LintRuleId.missingType => LintSeverity.warning,
      LintRuleId.suspiciousIdField => LintSeverity.warning,
      LintRuleId.typeInconsistency => LintSeverity.warning,
      LintRuleId.emptyObject => LintSeverity.warning,
      LintRuleId.arrayWithoutItems => LintSeverity.warning,
      LintRuleId.emptyEnum => LintSeverity.warning,
    };
    return LintRuleConfig(id: id, severity: defaultSeverity);
  }

  /// Creates a rule from strings (for config parsing).
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
        throw Exception('Unknown lint rule: $str');
    }
  }

  /// Parses severity level from string (public method used by ConfigLoader).
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
        throw Exception(
            'Unknown severity level: $str (expected: off, warning, error)');
    }
  }
}

/// Configuration for all lint rules.
class LintConfig {
  /// Rules with their configurations.
  final Map<LintRuleId, LintRuleConfig> rules;

  LintConfig({Map<LintRuleId, LintRuleConfig>? rules})
      : rules = rules ??
            {
              // By default all rules are enabled
              for (final id in LintRuleId.values)
                id: LintRuleConfig.defaultFor(id),
            };

  /// Creates default configuration (all rules are enabled).
  factory LintConfig.defaultConfig() => LintConfig();

  /// Creates configuration with all rules disabled.
  factory LintConfig.disabled() => LintConfig(
        rules: {
          for (final id in LintRuleId.values)
            id: LintRuleConfig(id: id, severity: LintSeverity.off),
        },
      );

  /// Get configuration for a rule.
  LintRuleConfig getRule(LintRuleId id) {
    return rules[id] ?? LintRuleConfig.defaultFor(id);
  }

  /// Check if a rule is enabled.
  bool isEnabled(LintRuleId id) {
    return getRule(id).enabled;
  }

  /// Get severity level for a rule.
  LintSeverity getSeverity(LintRuleId id) {
    return getRule(id).severity;
  }

  /// Merge with another configuration (other has priority).
  LintConfig merge(LintConfig other) {
    return LintConfig(
      rules: {
        ...rules,
        ...other.rules,
      },
    );
  }
}
