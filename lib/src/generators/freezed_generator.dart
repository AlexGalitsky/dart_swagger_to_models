import 'class_generator_strategy.dart';

/// Generation strategy for the `freezed` style.
class FreezedGenerator extends ClassGeneratorStrategy {
  @override
  List<String> generateImportsAndParts(String fileName) => [
        "import 'package:freezed_annotation/freezed_annotation.dart';",
        "part '$fileName.freezed.dart';",
        "part '$fileName.g.dart';",
      ];

  @override
  List<String> generateClassAnnotations(String className) => ['@freezed'];

  @override
  String generateFullClass(
    String className,
    Map<String, FieldInfo> fields,
    String Function(String jsonKey, Map<String, dynamic> schema)
        fromJsonExpression,
    String Function(String fieldName, Map<String, dynamic> schema)
        toJsonExpression, {
    bool useJsonKey = false,
  }) {
    final buffer = StringBuffer()
      ..writeln('@freezed')
      ..writeln('class $className with _\$$className {');

    // const factory
    buffer.writeln('  const factory $className({');
    fields.forEach((propName, field) {
      // Field-level DartDoc (placed above parameter)
      final docLines = _buildFieldDocLines(field);
      for (final line in docLines) {
        buffer.writeln('    $line');
      }
      // Generate @JsonKey if needed
      if (useJsonKey && field.needsJsonKey(true)) {
        buffer.writeln('    @JsonKey(name: \'${field.jsonKey}\')');
      }
      final prefix = field.isRequired ? 'required ' : '';
      buffer.writeln('    $prefix${field.dartType} ${field.camelCaseName},');
    });
    buffer.writeln('  }) = _$className;');
    buffer.writeln();

    // fromJson is delegated to freezed/json_serializable
    buffer.writeln(
        '  factory $className.fromJson(Map<String, dynamic> json) => _\$${className}FromJson(json);');

    buffer.writeln('}');
    return buffer.toString();
  }
}

List<String> _buildFieldDocLines(FieldInfo field) {
  final schema = field.schema;
  final description = schema['description'] as String?;
  final example = schema['example'];
  final lines = <String>[];

  if (description != null && description.trim().isNotEmpty) {
    final descLines = description.trim().split('\n');
    for (final line in descLines) {
      final trimmed = line.trimRight();
      if (trimmed.isEmpty) {
        lines.add('///');
      } else {
        lines.add('/// $trimmed');
      }
    }
  }

  if (example != null) {
    if (lines.isNotEmpty) {
      lines.add('///');
    }
    lines.add('/// Example: $example');
  }

  return lines;
}
