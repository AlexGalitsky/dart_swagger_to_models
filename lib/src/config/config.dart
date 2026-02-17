import '../core/lint_rules.dart';
import '../core/types.dart';

/// Конфигурация генератора.
class Config {
  /// Стиль генерации по умолчанию (встроенный стиль).
  final GenerationStyle? defaultStyle;

  /// Имя кастомного стиля генерации (если используется вместо defaultStyle).
  final String? customStyleName;

  /// Директория для выходных файлов.
  final String? outputDir;

  /// Корневая директория проекта.
  final String? projectDir;

  /// Использовать @JsonKey для полей с snake_case JSON-ключами.
  final bool? useJsonKey;

  /// Конфигурация lint правил.
  final LintConfig? lint;

  /// Переопределения для отдельных схем.
  final Map<String, SchemaOverride> schemaOverrides;

  Config({
    this.defaultStyle,
    this.customStyleName,
    this.outputDir,
    this.projectDir,
    this.useJsonKey,
    this.lint,
    Map<String, SchemaOverride>? schemaOverrides,
  }) : schemaOverrides = schemaOverrides ?? {};

  /// Создаёт пустую конфигурацию.
  factory Config.empty() => Config();

  /// Объединяет две конфигурации, где [other] имеет приоритет.
  Config merge(Config other) {
    return Config(
      defaultStyle: other.defaultStyle ?? defaultStyle,
      customStyleName: other.customStyleName ?? customStyleName,
      outputDir: other.outputDir ?? outputDir,
      projectDir: other.projectDir ?? projectDir,
      useJsonKey: other.useJsonKey ?? useJsonKey,
      lint: other.lint ?? lint,
      schemaOverrides: {
        ...schemaOverrides,
        ...other.schemaOverrides,
      },
    );
  }
}

/// Переопределения для отдельной схемы.
class SchemaOverride {
  /// Кастомное имя класса (вместо автоматически сгенерированного).
  final String? className;

  /// Маппинг имён полей (JSON ключ -> Dart имя поля).
  final Map<String, String>? fieldNames;

  /// Маппинг типов (JSON тип -> Dart тип).
  final Map<String, String>? typeMapping;

  /// Использовать @JsonKey для полей с snake_case JSON-ключами (переопределяет глобальную опцию).
  final bool? useJsonKey;

  SchemaOverride({
    this.className,
    Map<String, String>? fieldNames,
    Map<String, String>? typeMapping,
    this.useJsonKey,
  })  : fieldNames = fieldNames ?? {},
        typeMapping = typeMapping ?? {};

  /// Создаёт пустое переопределение.
  factory SchemaOverride.empty() => SchemaOverride();
}
