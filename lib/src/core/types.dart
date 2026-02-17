/// Swagger/OpenAPI specification type.
enum SpecVersion { swagger2, openApi3 }

/// Model generation style.
enum GenerationStyle {
  /// Simple Dart classes with manual fromJson/toJson implementation.
  plainDart,

  /// Classes with @JsonSerializable annotation from json_serializable package.
  jsonSerializable,

  /// Immutable classes using freezed package.
  freezed,
}

/// Model generation result.
class GenerationResult {
  final String outputDirectory;
  final List<String> generatedFiles;
  final int schemasProcessed;
  final int enumsProcessed;
  final int filesCreated;
  final int filesUpdated;

  GenerationResult({
    required this.outputDirectory,
    required this.generatedFiles,
    this.schemasProcessed = 0,
    this.enumsProcessed = 0,
    this.filesCreated = 0,
    this.filesUpdated = 0,
  });
}

/// Generation context for storing all schemas and enums.
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

  /// Get schema by $ref.
  Map<String, dynamic>? resolveRef(String ref, {String? context}) {
    final parts = ref.split('/');
    if (parts.isEmpty) return null;

    // Remove # if present
    final cleanParts = parts.where((p) => p.isNotEmpty && p != '#').toList();

    Map<String, dynamic> current = allSchemas;
    for (var i = 0; i < cleanParts.length; i++) {
      final key = cleanParts[i];
      if (i == cleanParts.length - 1) {
        final result = current[key];
        if (result is Map<String, dynamic>) {
          return result;
        } else {
          // Schema not found - log warning
          // Import Logger only here to avoid circular dependencies
          // Use dynamic import via string
          return null;
        }
      } else {
        final next = current[key];
        if (next is Map<String, dynamic>) {
          current = next;
        } else {
          // Intermediate path not found
          return null;
        }
      }
    }
    return null;
  }

  /// Check if schema is an enum.
  bool isEnum(Map<String, dynamic> schema) {
    final enumValues = schema['enum'] as List?;
    return enumValues != null && enumValues.isNotEmpty;
  }

  /// Get enum type name for schema.
  String? getEnumTypeName(Map<String, dynamic> schema, String? suggestedName) {
    if (!isEnum(schema)) return null;
    final enumValues = schema['enum'] as List?;
    if (enumValues == null || enumValues.isEmpty) return null;

    if (suggestedName != null && enumTypes.containsKey(suggestedName)) {
      return enumTypes[suggestedName];
    }

    // Generate unique name for enum
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

