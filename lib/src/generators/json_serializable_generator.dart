import 'class_generator_strategy.dart';

/// Generation strategy for the `json_serializable` style.
class JsonSerializableGenerator extends ClassGeneratorStrategy {
  @override
  List<String> generateImportsAndParts(String fileName) => [
        "import 'package:json_annotation/json_annotation.dart';",
        "part '$fileName.g.dart';",
      ];

  @override
  List<String> generateClassAnnotations(String className) =>
      ['@JsonSerializable()'];

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
      ..writeln('@JsonSerializable()')
      ..writeln('class $className {');

    // Fields
    fields.forEach((propName, field) {
      // Generate @JsonKey if needed
      if (useJsonKey && field.needsJsonKey(true)) {
        buffer.writeln('  @JsonKey(name: \'${field.jsonKey}\')');
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

    // fromJson/toJson are delegated to json_serializable
    buffer.writeln(
        '  factory $className.fromJson(Map<String, dynamic> json) => _\$${className}FromJson(json);');
    buffer.writeln();
    buffer.writeln(
        '  Map<String, dynamic> toJson() => _\$${className}ToJson(this);');

    buffer.writeln('}');
    return buffer.toString();
  }
}
