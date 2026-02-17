import '../core/types.dart';

/// Конфигурация генератора.
class Config {
  /// Стиль генерации по умолчанию.
  final GenerationStyle? defaultStyle;

  /// Директория для выходных файлов.
  final String? outputDir;

  /// Корневая директория проекта.
  final String? projectDir;

  /// Использовать @JsonKey для полей с snake_case JSON-ключами.
  final bool? useJsonKey;

  /// Переопределения для отдельных схем.
  final Map<String, SchemaOverride> schemaOverrides;

  Config({
    this.defaultStyle,
    this.outputDir,
    this.projectDir,
    this.useJsonKey,
    Map<String, SchemaOverride>? schemaOverrides,
  }) : schemaOverrides = schemaOverrides ?? {};

  /// Создаёт пустую конфигурацию.
  factory Config.empty() => Config();

  /// Объединяет две конфигурации, где [other] имеет приоритет.
  Config merge(Config other) {
    return Config(
      defaultStyle: other.defaultStyle ?? defaultStyle,
      outputDir: other.outputDir ?? outputDir,
      projectDir: other.projectDir ?? projectDir,
      useJsonKey: other.useJsonKey ?? useJsonKey,
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
