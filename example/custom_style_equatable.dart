import 'package:dart_swagger_to_models/dart_swagger_to_models.dart';
import 'package:equatable/equatable.dart';

/// Пример кастомного генератора стиля с поддержкой Equatable.
///
/// Этот пример демонстрирует, как создать собственный стиль генерации,
/// который добавляет поддержку пакета equatable для сравнения объектов.
class EquatableGenerator extends ClassGeneratorStrategy {
  @override
  List<String> generateImportsAndParts(String fileName) {
    return [
      "import 'package:equatable/equatable.dart';",
    ];
  }

  @override
  List<String> generateClassAnnotations(String className) {
    return [];
  }

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
      ..writeln('class $className extends Equatable {');

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
    buffer.writeln();

    // Equatable props
    buffer.writeln('  @override');
    buffer.writeln('  List<Object?> get props => [');
    fields.forEach((propName, field) {
      buffer.writeln('    ${field.camelCaseName},');
    });
    buffer.writeln('  ];');

    buffer.writeln('}');
    return buffer.toString();
  }
}

/// Функция для регистрации кастомного стиля.
///
/// Эта функция должна быть вызвана перед использованием кастомного стиля.
/// Обычно это делается в main() функции или в отдельном файле инициализации.
void registerEquatableStyle() {
  StyleRegistry.register('equatable', () => EquatableGenerator());
}
