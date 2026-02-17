import '../core/lint_rules.dart';
import '../core/types.dart';

/// Generator configuration.
class Config {
  /// Default generation style (built-in style).
  final GenerationStyle? defaultStyle;

  /// Name of custom generation style (if used instead of defaultStyle).
  final String? customStyleName;

  /// Output directory for generated files.
  final String? outputDir;

  /// Project root directory.
  final String? projectDir;

  /// Whether to use @JsonKey for fields with snake_case JSON keys.
  final bool? useJsonKey;

  /// Lint rules configuration.
  final LintConfig? lint;

  /// Whether to generate DartDoc comments from Swagger/OpenAPI descriptions.
  ///
  /// If null, documentation generation is enabled by default.
  final bool? generateDocs;

  /// Whether to generate validation helpers from Swagger/OpenAPI constraints.
  ///
  /// If null, validation generation is disabled by default.
  final bool? generateValidation;

  /// Overrides for individual schemas.
  final Map<String, SchemaOverride> schemaOverrides;

  Config({
    this.defaultStyle,
    this.customStyleName,
    this.outputDir,
    this.projectDir,
    this.useJsonKey,
    this.lint,
    this.generateDocs,
    this.generateValidation,
    Map<String, SchemaOverride>? schemaOverrides,
  }) : schemaOverrides = schemaOverrides ?? {};

  /// Creates an empty configuration.
  factory Config.empty() => Config();

  /// Merges two configs where [other] has priority.
  Config merge(Config other) {
    return Config(
      defaultStyle: other.defaultStyle ?? defaultStyle,
      customStyleName: other.customStyleName ?? customStyleName,
      outputDir: other.outputDir ?? outputDir,
      projectDir: other.projectDir ?? projectDir,
      useJsonKey: other.useJsonKey ?? useJsonKey,
      lint: other.lint ?? lint,
      generateDocs: other.generateDocs ?? generateDocs,
      generateValidation: other.generateValidation ?? generateValidation,
      schemaOverrides: {
        ...schemaOverrides,
        ...other.schemaOverrides,
      },
    );
  }
}

/// Overrides for a single schema.
class SchemaOverride {
  /// Custom class name (instead of automatically generated).
  final String? className;

  /// Mapping of field names (JSON key -> Dart field name).
  final Map<String, String>? fieldNames;

  /// Mapping of types (JSON type -> Dart type).
  final Map<String, String>? typeMapping;

  /// Whether to use @JsonKey for fields with snake_case JSON keys (overrides global option).
  final bool? useJsonKey;

  SchemaOverride({
    this.className,
    Map<String, String>? fieldNames,
    Map<String, String>? typeMapping,
    this.useJsonKey,
  })  : fieldNames = fieldNames ?? {},
        typeMapping = typeMapping ?? {};

  /// Creates an empty override.
  factory SchemaOverride.empty() => SchemaOverride();
}
