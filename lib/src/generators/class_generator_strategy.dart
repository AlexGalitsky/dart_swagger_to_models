/// Abstract strategy for generating Dart classes from Swagger/OpenAPI schemas.
abstract class ClassGeneratorStrategy {
  /// Generates imports and part directives for a file.
  List<String> generateImportsAndParts(String fileName);

  /// Generates class-level annotations (e.g., @JsonSerializable(), @freezed).
  List<String> generateClassAnnotations(String className);

  /// Generates the full class code.
  ///
  /// [className] - class name in PascalCase.
  /// [fields] - information about class fields.
  /// [fromJsonExpression] - function that generates a fromJson expression for a field.
  /// [toJsonExpression] - function that generates a toJson expression for a field.
  /// [useJsonKey] - whether to use @JsonKey for fields with snake_case JSON keys.
  String generateFullClass(
    String className,
    Map<String, FieldInfo> fields,
    String Function(String jsonKey, Map<String, dynamic> schema)
        fromJsonExpression,
    String Function(String fieldName, Map<String, dynamic> schema)
        toJsonExpression, {
    bool useJsonKey = false,
  });
}

/// Information about a class field.
class FieldInfo {
  /// Field name in Dart (can be renamed via config).
  final String name;

  /// Original JSON key from the schema.
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

  /// Checks whether @JsonKey should be generated (when JSON key differs from Dart field name).
  bool needsJsonKey(bool useJsonKeyEnabled) {
    if (!useJsonKeyEnabled) return false;
    // Generate @JsonKey when JSON key is different from Dart field name
    return jsonKey != camelCaseName;
  }
}
