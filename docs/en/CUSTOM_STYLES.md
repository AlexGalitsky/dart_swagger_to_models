# How to create your own generation style

This guide explains how to create and register custom generation styles for `dart_swagger_to_models`.

## Overview

The generator uses a strategy pattern for code generation. Each style (like `plain_dart`, `json_serializable`, `freezed`) is implemented as a `ClassGeneratorStrategy`. You can create your own strategy and register it to use with the generator.

## Step 1: Create your strategy class

Create a class that extends `ClassGeneratorStrategy`:

```dart
import 'package:dart_swagger_to_models/dart_swagger_to_models.dart';

class MyCustomGenerator extends ClassGeneratorStrategy {
  @override
  List<String> generateImportsAndParts(String fileName) {
    // Return imports and part directives needed for this style
    return [
      "import 'package:my_package/my_package.dart';",
    ];
  }

  @override
  List<String> generateClassAnnotations(String className) {
    // Return class-level annotations (e.g., @JsonSerializable(), @freezed)
    return [];
  }

  @override
  String generateFullClass(
    String className,
    Map<String, FieldInfo> fields,
    String Function(String jsonKey, Map<String, dynamic> schema) fromJsonExpression,
    String Function(String fieldName, Map<String, dynamic> schema) toJsonExpression, {
    bool useJsonKey = false,
  }) {
    // Generate the full class code
    final buffer = StringBuffer()
      ..writeln('class $className {');
    
    // Add fields
    fields.forEach((propName, field) {
      buffer.writeln('  final ${field.dartType} ${field.camelCaseName};');
    });
    
    // Add constructor, fromJson, toJson, etc.
    // ...
    
    buffer.writeln('}');
    return buffer.toString();
  }
}
```

## Step 2: Register your style

Register your custom style using `StyleRegistry`:

```dart
import 'package:dart_swagger_to_models/dart_swagger_to_models.dart';

void main() {
  // Register your custom style
  StyleRegistry.register('my_custom_style', () => MyCustomGenerator());
  
  // Now you can use 'my_custom_style' in your config or CLI
}
```

## Step 3: Use your custom style

### Option 1: Via configuration file

Create a `dart_swagger_to_models.yaml` file:

```yaml
defaultStyle: my_custom_style
```

### Option 2: Via CLI

```bash
dart run dart_swagger_to_models:dart_swagger_to_models \
  --input api.yaml \
  --style my_custom_style
```

**Note:** You need to register the style in your Dart code before running the generator. This is typically done in a build script or initialization file.

## Example: Equatable style

Here's a complete example that adds `Equatable` support:

```dart
import 'package:dart_swagger_to_models/dart_swagger_to_models.dart';
import 'package:equatable/equatable.dart';

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
    String Function(String jsonKey, Map<String, dynamic> schema) fromJsonExpression,
    String Function(String fieldName, Map<String, dynamic> schema) toJsonExpression, {
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

// Register the style
void registerEquatableStyle() {
  StyleRegistry.register('equatable', () => EquatableGenerator());
}
```

## FieldInfo API

The `FieldInfo` class provides useful information about each field:

- `name` - Dart field name (may be renamed via config)
- `jsonKey` - Original JSON key from schema
- `dartType` - Dart type (e.g., `int`, `String?`, `List<String>`)
- `isRequired` - Whether the field is required (non-nullable)
- `schema` - Original schema definition
- `camelCaseName` - CamelCase version of the field name
- `needsJsonKey(bool useJsonKeyEnabled)` - Whether to generate `@JsonKey` annotation

## Best practices

1. **Reuse existing logic**: Look at `PlainDartGenerator`, `JsonSerializableGenerator`, or `FreezedGenerator` for reference implementations.

2. **Handle nullable types**: Use `field.isRequired` to determine if a field should be nullable.

3. **Support `useJsonKey`**: When `useJsonKey` is enabled and `field.needsJsonKey(true)` returns true, generate `@JsonKey(name: '...')` annotations.

4. **Generate proper imports**: Include all necessary imports in `generateImportsAndParts`.

5. **Test your style**: Create tests to ensure your custom style generates correct code.

## Limitations

- Custom styles are registered at runtime, so they must be registered before the generator runs.
- Custom styles work best when used programmatically (via the Dart API) rather than via CLI, unless you create a wrapper script.

## See also

- `example/custom_style_equatable.dart` - Complete example of an Equatable style generator
- `lib/src/generators/` - Reference implementations of built-in styles
