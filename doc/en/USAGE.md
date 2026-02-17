## Using dart_swagger_to_models (EN)

This document describes typical usage scenarios for `dart_swagger_to_models`.

### Table of Contents

1. [Basic generation](#1-basic-generation)  
2. [Custom output directory and style](#2-custom-output-directory-and-style)  
3. [Using the `freezed` style](#3-using-the-freed-style)  
4. [Regenerating existing files](#4-regenerating-existing-files)  
5. [Configuration file](#5-configuration-file)  
6. [Lint configuration](#6-lint-configuration)  
7. [Null-safety rules](#7-null-safety-rules)  
8. [Logging and output control](#8-logging-and-output-control)  
9. [OpenAPI composition schemas (allOf, oneOf, anyOf)](#9-openapi-composition-schemas-allof-oneof-anyof)  
10. [Incremental generation](#10-incremental-generation)  
11. [Custom generation styles (pluggable styles)](#11-custom-generation-styles-pluggable-styles)  
12. [build_runner integration](#12-build_runner-integration)  
13. [FAQ / Troubleshooting](#13-faq--troubleshooting)

### 1. Basic generation

Generate models from a local `api.yaml` file (`plain_dart` style, one model = one file):

```bash
dart run dart_swagger_to_models:dart_swagger_to_models --input api.yaml
```

Models will be written to `lib/models` (default).

---

### 2. Custom output directory and style

```bash
dart run dart_swagger_to_models:dart_swagger_to_models \
  --input api.yaml \
  --output-dir lib/api_models \
  --style json_serializable
```

In this case:

- files will be written to `lib/api_models`
- models will use the `json_serializable` style with
  `@JsonSerializable()` and `part '*.g.dart';`.

---

### 3. Using the `freezed` style

```bash
dart run dart_swagger_to_models:dart_swagger_to_models \
  --input openapi.yaml \
  --output-dir lib/models \
  --style freezed
```

Each model will look roughly like:

```dart
@freezed
class User with _$User {
  const factory User({
    required int id,
    required String name,
    String? email,
  }) = _User;

  factory User.fromJson(Map<String, dynamic> json) => _$UserFromJson(json);
}
```

---

### 4. Regenerating existing files

If a model is already integrated into your project and contains the marker:

```dart
/*SWAGGER-TO-DART*/
```

you can regenerate files by running:

```bash
dart run dart_swagger_to_models:dart_swagger_to_models \
  --input api.yaml \
  --output-dir lib/models \
  --project-dir .
```

All Dart files containing the marker `/*SWAGGER-TO-DART*/` will be updated.

Only the content between
`/*SWAGGER-TO-DART: Codegen start*/` and
`/*SWAGGER-TO-DART: Codegen stop*/`
will be replaced; all other code is preserved.

---

### 5. Configuration file

You can create a `dart_swagger_to_models.yaml` file in your project root to configure the generator:

```yaml
# Global options
defaultStyle: json_serializable
outputDir: lib/generated
projectDir: .

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
```

**Priority**: CLI arguments > configuration file > default values.

#### Configuration options:

- `defaultStyle`: default generation style (`plain_dart`, `json_serializable`, `freezed`)
- `outputDir`: default output directory for generated files
- `projectDir`: default project root directory
- `useJsonKey`: generate `@JsonKey(name: '...')` for fields where the JSON key differs from the Dart field name (default: `false`)
- `lint`: configuration of lint rules for validating specs (see below)
- `schemas`: per-schema overrides:
  - `className`: custom class name (overrides the automatically generated name)
  - `fieldNames`: mapping from JSON keys to Dart field names
  - `typeMapping`: mapping from schema types to Dart types
  - `useJsonKey`: override the global `useJsonKey` option for this schema

---

### 6. Lint configuration

You can configure lint rules for validating your Swagger/OpenAPI specifications:

```yaml
lint:
  enabled: true  # Enable/disable all lint rules (default: true)
  rules:
    missing_type: error          # Field without type and without $ref
    suspicious_id_field: warning # ID field without required and nullable
    missing_ref_target: error    # Missing $ref target
    type_inconsistency: warning  # Type inconsistency (e.g., integer with format)
    empty_object: warning        # Empty object (no properties and no additionalProperties)
    array_without_items: warning # Array without items
    empty_enum: warning          # Enum without values
```

Each rule can be set to:

- `off` - rule disabled
- `warning` - rule produces a warning
- `error` - rule produces an error

**Example with lint configuration:**

```yaml
defaultStyle: json_serializable
lint:
  rules:
    missing_type: error
    suspicious_id_field: off
    missing_ref_target: error
schemas:
  User:
    className: CustomUser
```

**Example with `useJsonKey`:**

When `useJsonKey: true` is set, fields with snake_case JSON keys automatically get `@JsonKey` annotations:

```yaml
# dart_swagger_to_models.yaml
useJsonKey: true
```

For a schema with fields `user_id` and `user_name`, the generator will produce:

```dart
@JsonSerializable()
class User {
  @JsonKey(name: 'user_id')
  final int userId;
  
  @JsonKey(name: 'user_name')
  final String userName;
  
  // ...
}
```

This works for both `json_serializable` and `freezed` styles.

**Example with custom config file:**

```bash
dart run dart_swagger_to_models:dart_swagger_to_models \
  --input api.yaml \
  --config custom_config.yaml
```

---

### 7. Null-safety rules

The generator uses a simple rule:

- If a field is present in the schema `properties` — it is **required by default**.
- If a field has `nullable: true` — it is generated as nullable (`Type?`).

This rule is applied consistently across all three styles:

- `plain_dart`
- `json_serializable`
- `freezed`

---

### 8. Logging and output control

The generator provides flexible logging options:

**Verbose mode (`--verbose` / `-v`):**

- Shows detailed debug information
- Displays progress for each processed schema
- Useful for debugging and understanding the generation process

```bash
dart run dart_swagger_to_models:dart_swagger_to_models \
  --input api.yaml \
  --verbose
```

**Quiet mode (`--quiet` / `-q`):**

- Minimal output (only errors and critical messages)
- Useful in CI/CD pipelines or scripts

```bash
dart run dart_swagger_to_models:dart_swagger_to_models \
  --input api.yaml \
  --quiet
```

**Default mode:**

- Shows informational messages, warnings, and errors
- Displays a summary after generation

**Generation summary includes:**

- Number of processed schemas
- Number of processed enums
- Number of created files
- Number of updated files
- Total number of generated files
- Output directory

**Error messages:**

The generator provides clear error messages for:

- Missing `$ref` targets (with context about where the reference was used)
- Unsupported or ambiguous schema constructs
- Suspicious specifications (e.g., `id` fields without `nullable: true` and without `required`)

---

### 9. OpenAPI composition schemas (allOf, oneOf, anyOf)

The generator supports OpenAPI 3.0 composition schemas:

#### `allOf` (multiple inheritance)

The generator merges all properties from all `allOf` elements into a single class:

```yaml
components:
  schemas:
    BaseEntity:
      type: object
      required: [id]
      properties:
        id:
          type: integer
        createdAt:
          type: string
          format: date-time
    
    User:
      allOf:
        - $ref: '#/components/schemas/BaseEntity'
        - type: object
          properties:
            name:
              type: string
            email:
              type: string
```

The generated `User` class will contain all properties from `BaseEntity` plus its own properties.

**Capabilities:**

- Recursive handling of nested `allOf` combinations
- Support for multiple inheritance (multiple `$ref` entries in `allOf`)
- Detection and prevention of circular dependencies
- Detailed logging of nested `allOf` processing (use `--verbose`)

#### `oneOf` / `anyOf` (union-like types)

The generator supports `oneOf` / `anyOf` in two modes:

- **Without discriminator** — safe wrapper with `dynamic` value.
- **With discriminator and per-variant enums** — union-style class with discriminator and typed variants.

##### 9.1 oneOf/anyOf without discriminator (dynamic wrapper)

```yaml
components:
  schemas:
    StringValue:
      type: object
      properties:
        value:
          type: string
    
    NumberValue:
      type: object
      properties:
        value:
          type: number
    
    Value:
      oneOf:
        - $ref: '#/components/schemas/StringValue'
        - $ref: '#/components/schemas/NumberValue'
```

The generated `Value` class will be:

```dart
/// Class for oneOf schema "Value".
///
/// Note: For oneOf schemas a wrapper with dynamic is generated.
/// Possible types: StringValue, NumberValue.
class Value {
  /// Value (can be one of the possible types).
  final dynamic value;

  const Value(this.value);

  /// Creates an instance from JSON.
  ///
  /// Note: For oneOf schemas manual type validation is required.
  factory Value.fromJson(dynamic json) {
    if (json == null) {
      throw ArgumentError('JSON cannot be null for Value');
    }
    return Value(json);
  }

  /// Converts to JSON.
  dynamic toJson() => value;

  @override
  String toString() => 'Value(value: $value)';
}
```

**Capabilities:**

- Safe `dynamic` wrappers with clear error messages.
- Detection and logging of possible types in `oneOf`/`anyOf` schemas (use `--verbose`).

##### 9.2 oneOf/anyOf with discriminator (union-style class)

If a schema uses `discriminator` and each referenced variant schema defines that discriminator property
as an enum with a single literal (e.g. `'cat'`, `'dog'`), the generator creates a union-style class:

```yaml
components:
  schemas:
    Cat:
      type: object
      properties:
        type:
          type: string
          enum: ['cat']
        meow:
          type: boolean

    Dog:
      type: object
      properties:
        type:
          type: string
          enum: ['dog']
        bark:
          type: boolean

    Pet:
      oneOf:
        - $ref: '#/components/schemas/Cat'
        - $ref: '#/components/schemas/Dog'
      discriminator:
        propertyName: type
```

The generated `Pet` union class will look roughly like:

```dart
class Pet {
  final String type;

  /// Value when this union holds `Cat`.
  final Cat? cat;

  /// Value when this union holds `Dog`.
  final Dog? dog;

  const Pet._({
    required this.type,
    this.cat,
    this.dog,
  })  : cat = cat,
        dog = dog;

  factory Pet.fromCat(Cat value) {
    return Pet._(
      type: 'cat',
      cat: value,
    );
  }

  factory Pet.fromDog(Dog value) {
    return Pet._(
      type: 'dog',
      dog: value,
    );
  }

  factory Pet.fromJson(Map<String, dynamic> json) {
    final disc = json['type'] as String?;
    if (disc == null) {
      throw ArgumentError('Missing discriminator "type" for Pet');
    }
    switch (disc) {
      case 'cat':
        return Pet.fromCat(Cat.fromJson(json));
      case 'dog':
        return Pet.fromDog(Dog.fromJson(json));
      default:
        throw ArgumentError('Unknown discriminator value "$disc" for Pet');
    }
  }

  Map<String, dynamic> toJson() {
    switch (type) {
      case 'cat':
        return cat!.toJson();
      case 'dog':
        return dog!.toJson();
      default:
        throw StateError('Unknown discriminator value "$type" for Pet');
    }
  }

  /// Pattern matching helper for union values.
  T when<T>({
    required T Function(Cat value) cat,
    required T Function(Dog value) dog,
  }) {
    switch (type) {
      case 'cat':
        return cat(this.cat!);
      case 'dog':
        return dog(this.dog!);
      default:
        throw StateError('Unknown discriminator value "$type" for Pet');
    }
  }
}
```

**Capabilities (with discriminator):**

- Type-safe JSON deserialization based on discriminator.
- Union-style class with one nullable field per variant.
- `when`/`maybeWhen` helpers for ergonomic pattern matching.

For more details and design trade-offs, see `doc/en/UNION_TYPES_NOTES.md`.

---

### 10. Incremental generation

The generator supports incremental generation to improve performance for large specs.

**Flag `--changed-only`:**

When enabled, the generator regenerates only those schemas that have changed since the last run:

```bash
dart run dart_swagger_to_models:dart_swagger_to_models \
  --input api.yaml \
  --changed-only
```

**How it works:**

- The generator caches schema hashes in `.dart_swagger_to_models.cache` in the project root
- On each run it compares current schema hashes with cached ones
- Only changed, new, or removed schemas are processed
- Files for removed schemas are automatically deleted

**Benefits:**

- Much faster generation for large specifications
- Only truly changed models are regenerated
- Fewer unnecessary file writes

**Example:**

```bash
# First run - generates all schemas and creates the cache
dart run dart_swagger_to_models:dart_swagger_to_models \
  --input api.yaml \
  --output-dir lib/models \
  --changed-only

# Change just a single schema in api.yaml

# Second run - regenerates only the changed schema
dart run dart_swagger_to_models:dart_swagger_to_models \
  --input api.yaml \
  --output-dir lib/models \
  --changed-only
```

**Cache file:**

- Location: `.dart_swagger_to_models.cache` in the project root (controlled by `--project-dir`)
- Format: JSON file containing schema hashes
- Lifecycle: created, updated, and maintained automatically
- VCS: safe to commit, but typically added to `.gitignore`

> **Note:** To force a full regeneration, simply omit `--changed-only` or delete the cache file.

---

### 11. Custom generation styles (pluggable styles)

The generator supports custom generation styles that you can create and register.

**Creating a custom style:**

1. Create a class that extends `ClassGeneratorStrategy`
2. Register it using `StyleRegistry.register()`
3. Use it via config file or CLI

**Example:**

```dart
import 'package:dart_swagger_to_models/dart_swagger_to_models.dart';

class MyCustomGenerator extends ClassGeneratorStrategy {
  // Implement required methods...
}

// Register style
StyleRegistry.register('my_style', () => MyCustomGenerator());
```

**Using a custom style:**

Via configuration file (`dart_swagger_to_models.yaml`):

```yaml
defaultStyle: my_style
```

Via CLI:

```bash
dart run dart_swagger_to_models:dart_swagger_to_models \
  --input api.yaml \
  --style my_style
```

> **Important:** Custom styles must be registered in your Dart code before running the generator. Typically this is done in a build script or initialization file.

For a full, step-by-step guide (including an Equatable example), see `doc/en/CUSTOM_STYLES.md`.

---

### 12. build_runner integration

The generator can be integrated with `build_runner` to automatically generate models as part of your build pipeline.

#### Setup

> **Important:** The builder is not exported from the main library to avoid loading `dart:mirrors` in normal usage (which is not supported in Flutter). `build_runner` discovers it automatically.

1. **Add dependencies** to your `pubspec.yaml`:

```yaml
dependencies:
  dart_swagger_to_models: ^0.5.2
  json_annotation: ^4.10.0  # If you use json_serializable style

dev_dependencies:
  build_runner: ^2.11.1
  json_serializable: ^6.8.0 # If you use json_serializable style
```

2. **Create `build.yaml`** in the project root:

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

3. **Place your OpenAPI/Swagger specs** into one of these directories:

- `swagger/`
- `openapi/`
- `api/`

4. **Create `dart_swagger_to_models.yaml`** (optional):

```yaml
defaultStyle: json_serializable
outputDir: lib/generated/models
useJsonKey: true
```

#### Usage

Run build_runner to generate models:

```bash
# Dart projects
dart run build_runner build

# Flutter projects
flutter pub run build_runner build
```

The generator will:

- Find all OpenAPI/Swagger specs in the configured directories
- Generate Dart models according to your configuration
- Write generated files to the configured output directory

#### Generated files

Models are generated in the directory specified by `outputDir` in your config (default: `lib/generated/models`). Each schema becomes its own Dart file.

#### Examples

See:

- `example/dart_example/` — pure Dart project with build_runner
- `example/flutter_example/` — Flutter project with HTTP client integration

#### Benefits

- **Automatic generation**: models regenerate automatically when specs change
- **Build integration**: works seamlessly with other code generators (e.g. `json_serializable`)
- **Incremental builds**: only changed models are regenerated when using `--changed-only` via CLI
- **IDE-friendly**: generated files are part of the project structure

#### Limitations

- The builder processes each spec file individually; each spec generates its own set of models
- For multiple specs, consider merging them or using separate output directories
- Custom styles must be registered before running build_runner (typically in a build script)

---

### 13. FAQ / Troubleshooting

**Q: I get “No schemas found in specification (definitions/components.schemas)”. What does it mean?**  
A: The generator could not find any schemas under `definitions` (Swagger 2.0) or `components.schemas` (OpenAPI 3.x).  
Check that:

- your spec actually defines schemas in one of these sections,
- `$ref` targets point to those sections (e.g. `#/components/schemas/User`),
- you are passing the correct file via `--input`.

---

**Q: My existing Dart file is not updated by the generator.**  
A: Make sure that:

- the file contains the marker `/*SWAGGER-TO-DART*/` near the top,
- the schema name matches the Dart file name (e.g. `User` → `user.dart`) or the `className` override in config,
- you pass the correct `--project-dir` (project root) so the scanner can find the file,
- the code you expect to be updated is between `/*SWAGGER-TO-DART: Codegen start*/` and `/*SWAGGER-TO-DART: Codegen stop*/`.

---

**Q: I see warnings from spec linting. How strict should I treat them?**  
A: By default, lint rules are conservative and can be tuned via `lint.rules` in `dart_swagger_to_models.yaml`.  
You can:

- change severity to `warning` or `off` for rules that are too noisy,
- keep `missing_type` and `missing_ref_target` as `error` in CI for better spec quality.

---

**Q: How do I regenerate only changed models in CI?**  
A: Use incremental generation:

```bash
dart run dart_swagger_to_models:dart_swagger_to_models \
  --input api.yaml \
  --output-dir lib/models \
  --changed-only
```

Commit `.dart_swagger_to_models.cache` if you want stable behavior between runs, or let it be recreated each time.

---

**Q: build_runner does not seem to run the generator.**  
A: Check that:

- `build.yaml` contains the `dart_swagger_to_models|swaggerBuilder` configuration,
- your specs are in `swagger/`, `openapi/`, or `api/`,
- `dart_swagger_to_models` and `build_runner` are added to `pubspec.yaml`,
- you run `dart run build_runner build` (or `flutter pub run build_runner build` for Flutter).


