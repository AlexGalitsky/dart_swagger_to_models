import 'package:dart_swagger_to_models/dart_swagger_to_models.dart';
import 'package:equatable/equatable.dart';

/// Example of a custom generation style with Equatable support.
///
/// This example shows how to create your own generation style
/// that adds support for the `equatable` package to compare objects.
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

    // Fields
    fields.forEach((propName, field) {
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

/// Helper function to register the custom style.
///
/// This function must be called before using the custom style.
/// Typically this is done in main() or in a separate initialization file.
void registerEquatableStyle() {
  StyleRegistry.register('equatable', () => EquatableGenerator());
}
