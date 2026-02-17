import 'class_generator_strategy.dart';

/// Стратегия генерации для freezed стиля.
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
      // Генерируем @JsonKey, если нужно
      if (useJsonKey && field.needsJsonKey(true)) {
        buffer.writeln('    @JsonKey(name: \'${field.jsonKey}\')');
      }
      final prefix = field.isRequired ? 'required ' : '';
      buffer.writeln('    $prefix${field.dartType} ${field.camelCaseName},');
    });
    buffer.writeln('  }) = _$className;');
    buffer.writeln();

    // fromJson делегируем freezed/json_serializable
    buffer.writeln(
        '  factory $className.fromJson(Map<String, dynamic> json) => _\$${className}FromJson(json);');

    buffer.writeln('}');
    return buffer.toString();
  }
}
