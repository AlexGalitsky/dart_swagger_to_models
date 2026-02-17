import 'class_generator_strategy.dart';

/// Generation strategy for plain_dart style.
class PlainDartGenerator extends ClassGeneratorStrategy {
  @override
  List<String> generateImportsAndParts(String fileName) => [];

  @override
  List<String> generateClassAnnotations(String className) => [];

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
    final buffer = StringBuffer()..writeln('class $className {');

    // Fields with optional DartDoc from field.schema.description/example
    fields.forEach((propName, field) {
      final docLines = _buildFieldDocLines(field);
      for (final line in docLines) {
        buffer.writeln('  $line');
      }
      buffer.writeln('  final ${field.dartType} ${field.camelCaseName};');
    });

    buffer.writeln();

    // Constructor
    buffer.writeln('  const $className({');
    fields.forEach((propName, field) {
      final prefix = field.isRequired ? 'required ' : '';
      buffer.writeln('    $prefix this.${field.camelCaseName},');
    });
    buffer.writeln('  });');
    buffer.writeln();

    // fromJson
    buffer
        .writeln('  factory $className.fromJson(Map<String, dynamic> json) {');
    buffer.writeln('    return $className(');
    fields.forEach((propName, field) {
      final jsonKey = propName;
      final assign = fromJsonExpression(jsonKey, field.schema);
      buffer.writeln('      ${field.camelCaseName}: $assign,');
    });
    buffer.writeln('    );');
    buffer.writeln('  }');
    buffer.writeln();

    // toJson
    buffer.writeln('  Map<String, dynamic> toJson() {');
    buffer.writeln('    return <String, dynamic>{');
    fields.forEach((propName, field) {
      final jsonKey = propName;
      final assign = toJsonExpression(field.camelCaseName, field.schema);
      buffer.writeln('      \'$jsonKey\': $assign,');
    });
    buffer.writeln('    };');
    buffer.writeln('  }');

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
