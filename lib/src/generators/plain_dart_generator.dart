import 'class_generator_strategy.dart';

/// Стратегия генерации для plain_dart стиля.
class PlainDartGenerator extends ClassGeneratorStrategy {
  @override
  List<String> generateImportsAndParts(String fileName) => [];

  @override
  List<String> generateClassAnnotations(String className) => [];

  @override
  String generateFullClass(
    String className,
    Map<String, FieldInfo> fields,
    String Function(String jsonKey, Map<String, dynamic> schema) fromJsonExpression,
    String Function(String fieldName, Map<String, dynamic> schema) toJsonExpression, {
    bool useJsonKey = false,
  }) {
    final buffer = StringBuffer()
      ..writeln('class $className {');

    // Поля
    fields.forEach((propName, field) {
      buffer.writeln('  final ${field.dartType} ${field.camelCaseName};');
    });

    buffer.writeln();

    // Конструктор
    buffer.writeln('  const $className({');
    fields.forEach((propName, field) {
      final prefix = field.isRequired ? 'required ' : '';
      buffer.writeln('    $prefix this.${field.camelCaseName},');
    });
    buffer.writeln('  });');
    buffer.writeln();

    // fromJson
    buffer.writeln('  factory $className.fromJson(Map<String, dynamic> json) {');
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
