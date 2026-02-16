/// Тип Swagger/OpenAPI-спецификации.
enum SpecVersion { swagger2, openApi3 }

/// Стиль генерации моделей.
enum GenerationStyle {
  /// Простые Dart-классы с ручной реализацией fromJson/toJson.
  plainDart,

  /// Классы с аннотацией @JsonSerializable из пакета json_serializable.
  jsonSerializable,

  /// Иммутабельные классы c использованием пакета freezed.
  freezed,
}

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

