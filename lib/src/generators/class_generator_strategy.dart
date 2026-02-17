/// Абстрактная стратегия генерации Dart-классов из Swagger/OpenAPI схем.
abstract class ClassGeneratorStrategy {
  /// Генерирует импорты и part'ы для файла.
  List<String> generateImportsAndParts(String fileName);

  /// Генерирует аннотации класса (например, @JsonSerializable(), @freezed).
  List<String> generateClassAnnotations(String className);

  /// Генерирует полный класс.
  ///
  /// [className] - имя класса в PascalCase.
  /// [fields] - информация о полях класса.
  /// [fromJsonExpression] - функция для генерации выражения fromJson для поля.
  /// [toJsonExpression] - функция для генерации выражения toJson для поля.
  /// [useJsonKey] - использовать @JsonKey для полей с snake_case JSON-ключами.
  String generateFullClass(
    String className,
    Map<String, FieldInfo> fields,
    String Function(String jsonKey, Map<String, dynamic> schema) fromJsonExpression,
    String Function(String fieldName, Map<String, dynamic> schema) toJsonExpression, {
    bool useJsonKey = false,
  });
}

/// Информация о поле класса.
class FieldInfo {
  /// Имя поля в Dart (может быть переименовано через конфиг).
  final String name;
  
  /// Оригинальный JSON ключ из схемы.
  final String jsonKey;
  
  final String dartType;
  final bool isRequired;
  final Map<String, dynamic> schema;

  FieldInfo({
    required this.name,
    required this.jsonKey,
    required this.dartType,
    required this.isRequired,
    required this.schema,
  });

  String get camelCaseName {
    final parts = name
        .replaceAll(RegExp(r'[^A-Za-z0-9_]'), '_')
        .split(RegExp(r'[_\s]+'))
      ..removeWhere((e) => e.isEmpty);
    if (parts.isEmpty) return '';
    final pascal = parts.map((p) => p[0].toUpperCase() + p.substring(1)).join();
    return pascal.isEmpty ? '' : pascal[0].toLowerCase() + pascal.substring(1);
  }

  /// Проверяет, нужно ли генерировать @JsonKey (когда JSON ключ отличается от Dart имени).
  bool needsJsonKey(bool useJsonKeyEnabled) {
    if (!useJsonKeyEnabled) return false;
    // Генерируем @JsonKey, если JSON ключ отличается от Dart имени поля
    return jsonKey != camelCaseName;
  }
}
