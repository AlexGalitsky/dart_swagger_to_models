<div align="center">
  <img src="images/logo.png" alt="dart_swagger_to_models" width="200"/>
</div>

# dart_swagger_to_models

[![Pub Version](https://img.shields.io/pub/v/dart_swagger_to_models)](https://pub.dev/packages/dart_swagger_to_models)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
![GitHub Stars](https://img.shields.io/github/stars/AlexGalitsky/dart_swagger_to_models.svg?style=flat-square&label=stars)
[![Dart SDK](https://img.shields.io/badge/Dart-3.3%2B-blue.svg)](https://dart.dev/)

> **CLI tool for generating null-safe Dart models from Swagger/OpenAPI specifications**

Generate type-safe, null-safe Dart models from your OpenAPI/Swagger specifications with support for multiple code generation styles, per-file mode, and seamless integration with your existing codebase.

## ✨ Features

- 🎯 **Null-safe by default** - All generated models are fully null-safe
- 📁 **Per-file mode** - One schema = one Dart file for better organization
- 🎨 **Multiple styles** - Support for `plain_dart`, `json_serializable`, and `freezed`
- 🔧 **Customizable** - Extensive configuration options via YAML file
- 🔄 **Incremental generation** - Only regenerate changed schemas for faster builds
- 🏗️ **build_runner integration** - Automatic generation as part of your build pipeline
- 🔍 **Spec linting** - Validate your OpenAPI/Swagger specifications
- 🧩 **Pluggable styles** - Register custom generation styles via `StyleRegistry`
- 📦 **OpenAPI 3.0 & Swagger 2.0** - Full support for both specification formats, including `allOf` inheritance and `oneOf`/`anyOf` union wrappers (with discriminator-aware unions)

## 🚀 Quick Start

### Installation

Add `dart_swagger_to_models` to your `pubspec.yaml`:

```yaml
dev_dependencies:
  dart_swagger_to_models: ^0.5.2
```

### Basic Usage

Generate models from your OpenAPI/Swagger specification:

```bash
dart run dart_swagger_to_models:dart_swagger_to_models --input api.yaml
```

This will generate Dart models in `lib/models/` directory using the default `plain_dart` style.

### Example Output

For a schema like this:

```yaml
definitions:
  User:
    type: object
    properties:
      id:
        type: integer
      name:
        type: string
      email:
        type: string
        nullable: true
```

The generator produces:

```dart
/*SWAGGER-TO-DART*/

class User {
  final int id;
  final String name;
  final String? email;

  const User({
    required this.id,
    required this.name,
    this.email,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as int,
      name: json['name'] as String,
      email: json['email'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'email': email,
    };
  }
}
```

## 📖 Documentation

- **[Usage Guide](doc/en/USAGE.md)** - Detailed usage instructions
- **[Custom Styles](doc/en/CUSTOM_STYLES.md)** - How to create custom generation styles
- **[LLM Context](doc/en/LLM_CONTEXT.md)** - Quick project overview for AI assistants

## 🎯 Generation Styles

### Plain Dart (Default)

Simple Dart classes with manual `fromJson`/`toJson` methods. No external dependencies.

```bash
--style plain_dart
```

### JSON Serializable

Uses `json_annotation` package with code generation support.

```bash
--style json_serializable
```

**Generated code:**
```dart
@JsonSerializable()
class User {
  final int id;
  final String name;

  const User({required this.id, required this.name});

  factory User.fromJson(Map<String, dynamic> json) => _$UserFromJson(json);
  Map<String, dynamic> toJson() => _$UserToJson(this);
}
```

### Freezed

Immutable classes using `freezed` package.

```bash
--style freezed
```

**Generated code:**
```dart
@freezed
class User with _$User {
  const factory User({
    required int id,
    required String name,
  }) = _User;

  factory User.fromJson(Map<String, dynamic> json) => _$UserFromJson(json);
}
```

## ⚙️ Configuration

Create a `dart_swagger_to_models.yaml` file in your project root:

```yaml
# Global options
defaultStyle: json_serializable
outputDir: lib/generated/models
projectDir: .
useJsonKey: true  # Generate @JsonKey for snake_case JSON keys

# Schema-specific overrides
schemas:
  User:
    className: CustomUser
    fieldNames:
      user_id: userId
      user_name: userName
    typeMapping:
      string: MyString
      integer: MyInt
    useJsonKey: true  # Override global useJsonKey for this schema

# Spec linting
lint:
  enabled: true
  rules:
    missing_type: error
    suspicious_id_field: warning
    missing_ref_target: error
    type_inconsistency: warning
    empty_object: warning
    array_without_items: warning
    empty_enum: warning
```

**Priority order**: CLI arguments > config file > defaults

## 🔧 CLI Options

| Option | Short | Description |
|--------|-------|-------------|
| `--input` | `-i` | Path to Swagger/OpenAPI specification (file or URL) — **required** |
| `--output-dir` | `-o` | Directory where models will be written (default: `lib/models`) |
| `--style` | `-s` | Generation style: `plain_dart`, `json_serializable`, `freezed`, or custom style name |
| `--project-dir` | | Project root directory for scanning Dart files (default: `.`) |
| `--config` | `-c` | Path to configuration file (default: `dart_swagger_to_models.yaml`) |
| `--verbose` | `-v` | Detailed output (includes debug information) |
| `--quiet` | `-q` | Minimal output (only errors and critical messages) |
| `--changed-only` | | Incremental generation - regenerate only changed schemas |
| `--help` | `-h` | Show help message |

## 📁 Per-File Mode

The generator **always** works in "one model = one file" mode. Each schema becomes its own Dart file (e.g., `user.dart`, `order.dart`).

### Key Features

- **Automatic file management** - Creates new files or updates existing ones
- **Marker-based identification** - Files are identified by `/*SWAGGER-TO-DART*/` marker
- **Code preservation** - Custom code outside markers is preserved
- **Smart updates** - Only content between `/*SWAGGER-TO-DART: Codegen start*/` and `/*SWAGGER-TO-DART: Codegen stop*/` is replaced

### Example: Existing File with Custom Code

```dart
/*SWAGGER-TO-DART*/

import 'package:some_package/some_package.dart';

// Custom code before markers
void customFunction() {
  print('Custom code');
}

/*SWAGGER-TO-DART: Codegen start*/
// Generated class will be placed here
class User {
  final int id;
  final String name;
}
/*SWAGGER-TO-DART: Codegen stop*/

// Custom code after markers
extension UserExtension on User {
  String get displayName => name;
}
```

On regeneration, only the content between markers is updated, preserving all your custom code.

## 🏗️ Build Runner Integration

Automatically generate models as part of your build pipeline. See [Usage Guide - Build Runner Integration](doc/en/USAGE.md#build-runner-integration) for details.

**Quick setup:**

1. Add to `build.yaml`:
```yaml
targets:
  $default:
    builders:
      dart_swagger_to_models|swaggerBuilder:
        enabled: true
        generate_for:
          - swagger/**
          - openapi/**
          - api/**
```

2. Run build:
```bash
dart run build_runner build
```

## 🔍 Spec Linting

Validate your OpenAPI/Swagger specifications and catch issues early:

```yaml
lint:
  enabled: true
  rules:
    missing_type: error          # Field without type and without $ref
    suspicious_id_field: warning # ID field without required and nullable
    missing_ref_target: error    # Missing $ref target
    type_inconsistency: warning  # Type inconsistency
    empty_object: warning        # Empty object
    array_without_items: warning # Array without items
    empty_enum: warning          # Enum without values
```

Each rule can be set to `off`, `warning`, or `error`.

## 🧩 Custom Generation Styles

Register your own generation styles using `StyleRegistry`:

```dart
import 'package:dart_swagger_to_models/dart_swagger_to_models.dart';

// Register custom style
StyleRegistry.register('my_style', () => MyCustomGenerator());

// Use in config file or CLI
// dart_swagger_to_models.yaml:
// defaultStyle: my_style
```

See [Custom Styles Guide](doc/en/CUSTOM_STYLES.md) for detailed instructions.

## 📋 Nullability Rules

The generator follows these nullability rules:

- **Required by default**: If a field is present in schema `properties`, it is **required** by default
- **Nullable fields**: If a field has `nullable: true`, it is generated as nullable (`Type?`)
- **Missing fields**: Fields not in `required` array and without `nullable: true` are still required (by default)

## 🚦 Incremental Generation

Speed up generation for large specifications by only regenerating changed schemas:

```bash
dart run dart_swagger_to_models:dart_swagger_to_models \
  --input api.yaml \
  --changed-only
```

The generator uses a cache file (`.dart_swagger_to_models.cache`) to track schema changes.

## 📚 Examples

Check out the example projects:

- **[Dart Example](example/dart_example/)** - Pure Dart project with build_runner integration
- **[Flutter Example](example/flutter_example/)** - Flutter project with HTTP client integration
- **[Custom Style Example](example/custom_style_equatable.dart)** - Example of a custom Equatable style

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🔗 Links

- **Pub.dev**: https://pub.dev/packages/dart_swagger_to_models
- **GitHub**: https://github.com/AlexGalitsky/dart_swagger_to_models
- **Issues**: https://github.com/AlexGalitsky/dart_swagger_to_models/issues

---

**Made with ❤️ for the Dart community**
