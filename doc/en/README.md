## dart_swagger_to_models

CLI tool for generating **null-safe Dart models** from **Swagger / OpenAPI** specifications (JSON/YAML).

This document gives a high-level overview. For a full usage guide see `USAGE.md`.

### Key features

- **Null-safe models** for Swagger 2.0 and OpenAPI 3.x
- **Per-file mode**: one schema → one Dart file
- **Multiple styles**:
  - `plain_dart` — manual `fromJson` / `toJson`
  - `json_serializable` — `@JsonSerializable()` with generated helpers
  - `freezed` — immutable models with `@freezed`
- **Config file** (`dart_swagger_to_models.yaml`) with global and per-schema overrides
- **Incremental generation** via `--changed-only` and a schema hash cache
- **Spec linting** (configurable rules for Swagger/OpenAPI quality)
- **Pluggable styles** via `StyleRegistry`
- **build_runner integration** for automatic generation

#### Advanced OpenAPI composition

- `allOf`:
  - Merge properties from multiple schemas (including nested `allOf` and multiple inheritance).
  - Detect and log circular dependencies.
- `oneOf` / `anyOf`:
  - Safe `dynamic` wrappers for generic unions.
  - Discriminator-aware union-style classes when a discriminator+enum pattern is detected (see `doc/en/USAGE.md#9-openapi-composition-schemas-allof-oneof-anyof` and `doc/en/UNION_TYPES_NOTES.md` for details).

---

### Quick CLI examples

Basic generation (plain Dart, one model = one file):

```bash
dart run dart_swagger_to_models:dart_swagger_to_models --input api.yaml
```

Custom output directory and style:

```bash
dart run dart_swagger_to_models:dart_swagger_to_models \
  --input api.yaml \
  --output-dir lib/api_models \
  --style json_serializable
```

Using `freezed` style:

```bash
dart run dart_swagger_to_models:dart_swagger_to_models \
  --input openapi.yaml \
  --output-dir lib/models \
  --style freezed
```

---

### Per-file mode and markers

The generator **always** works in per-file mode:

- Each schema becomes its own Dart file (e.g. `user.dart`, `order.dart`)
- Files are identified by the marker comment:
  - `/*SWAGGER-TO-DART*/`
- Only the region between:
  - `/*SWAGGER-TO-DART: Codegen start*/`
  - `/*SWAGGER-TO-DART: Codegen stop*/`
  is regenerated; all other code is preserved.

Example of an existing file:

```dart
/*SWAGGER-TO-DART*/

import 'package:some_package/some_package.dart';

// Custom code before markers
void customFunction() {
  print('Custom code');
}

/*SWAGGER-TO-DART: Codegen start*/
// Generated class will be placed here
/*SWAGGER-TO-DART: Codegen stop*/

// Custom code after markers
extension UserExtension on User {
  String get displayName => name;
}
```

On regeneration, only the code between the markers is replaced.

---

### Configuration file (dart_swagger_to_models.yaml)

Example:

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
```

**Priority order**: CLI arguments > config file > defaults.

---

### Where to go next

- **USAGE (EN)**: `doc/en/USAGE.md` — detailed usage guide (CLI options, config, linting, incremental generation, build_runner integration)
- **Custom styles (EN)**: `doc/en/CUSTOM_STYLES.md` — how to implement your own generation style
- **Russian docs (RU)**:
  - `doc/ru/README.md` — краткий обзор на русском
  - `doc/ru/USAGE.md` — подробное руководство на русском

