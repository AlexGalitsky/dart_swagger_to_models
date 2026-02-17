dart_swagger_to_models
======================

CLI tool for generating **null-safe Dart models** from **Swagger / OpenAPI** specifications (JSON/YAML).

### Installation

- **Local in a project** (as a dev dependency, example):

```yaml
dev_dependencies:
  dart_swagger_to_models:
    path: ./tools/dart_swagger_to_models
```

### Usage

- **Basic example (`plain_dart`)**:

```bash
dart run dart_swagger_to_models:dart_swagger_to_models --input api.yaml
```

- **With custom output directory, library name and style**:

```bash
dart run dart_swagger_to_models:dart_swagger_to_models \
  --input api.yaml \
  --output-dir lib/generated_models \
  --library-name api_models \
  --style json_serializable
```

The tool supports **Swagger 2.0** (`swagger`) and **OpenAPI 3** (`openapi`).
Models are generated from `definitions` / `components.schemas` with
`fromJson` / `toJson` and full **null-safety**.

### CLI arguments

- **`--input`, `-i`**: path to Swagger/OpenAPI specification (file or URL) — **required**.
- **`--output-dir`, `-o`**: directory where models will be written (default: `lib/models`).
- **`--library-name`, `-l`**: library/file name without extension (default: `models`, historical parameter).
- **`--style`, `-s`**: model generation style:
  - `plain_dart` — plain Dart classes with manual `fromJson`/`toJson` (default),
  - `json_serializable` — classes with `@JsonSerializable()` and delegation to `_$ClassFromJson` / `_$ClassToJson`,
  - `freezed` — immutable `@freezed` classes with `const factory` and `fromJson`.
- **`--project-dir`**: project root directory for scanning Dart files (searching for existing model files, default: `.`).
- **`--config`, `-c`**: path to configuration file (default: searches for `dart_swagger_to_models.yaml` in project root).
- **`--verbose`, `-v`**: detailed output (includes debug information).
- **`--quiet`, `-q`**: minimal output (only errors and critical messages).
- **`--changed-only`**: incremental generation - regenerate only changed schemas (uses cache in `.dart_swagger_to_models.cache`).
- **`--help`, `-h`**: show help.

### Configuration file

You can create a `dart_swagger_to_models.yaml` file in your project root to configure the generator:

**Spec linting:**

The generator can validate your Swagger/OpenAPI specifications and report issues:

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

```yaml
# Global options
defaultStyle: json_serializable
outputDir: lib/generated
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

**Priority order**: CLI arguments > config file > defaults

**Configuration options:**
- `defaultStyle`: default generation style (`plain_dart`, `json_serializable`, `freezed`)
- `outputDir`: default output directory
- `projectDir`: default project directory
- `useJsonKey`: generate `@JsonKey(name: '...')` for fields where JSON key differs from Dart field name (default: `false`)
- `schemas`: per-schema overrides:
  - `className`: custom class name
  - `fieldNames`: mapping from JSON keys to Dart field names
  - `typeMapping`: mapping from schema types to Dart types
  - `useJsonKey`: override global `useJsonKey` setting for this schema

### Example

For the schema:

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
```

the generator will produce a Dart class `User` with **required** fields `id`, `name`
and **nullable** field `email`, plus `fromJson` and `toJson` methods.

> Nullability rule used by the generator:
> - If a field is present in the schema `properties`, it is **required by default**.
> - If a field has `nullable: true`, it is generated as nullable (`Type?`).

### Per-file mode (one model = one file)

The generator **always** works in "one model = one file" mode.
For each schema from Swagger/OpenAPI a separate Dart file is created
(for example, `user.dart`, `order.dart`).

```bash
dart run dart_swagger_to_models:dart_swagger_to_models \
  --input api.yaml \
  --output-dir lib/models \
  --style plain_dart \
  --project-dir .
```

**Key points:**

- **One model = one file**: each schema becomes its own Dart file
  (e.g. `user.dart`, `order.dart`).
- **Markers for identification**: each file starts with a marker
  `/*SWAGGER-TO-DART*/` for identification.
- **Integration with existing code**: the generator scans the project
  (`--project-dir`) and updates existing files that contain such markers.
- **Preserving custom code**: only the contents between markers
  `/*SWAGGER-TO-DART: Fields start*/` and
  `/*SWAGGER-TO-DART: Fields stop*/` are replaced;
  everything else (imports, methods, extensions, etc.) is preserved.

**Example of an existing file:**

```dart
/*SWAGGER-TO-DART*/

import 'package:some_package/some_package.dart';

// Custom code before markers
void customFunction() {
  print('Custom code');
}

/*SWAGGER-TO-DART: Fields start*/
// Generated class will be placed here
class User {
  final int id;
  final String name;
  // ...
}
/*SWAGGER-TO-DART: Fields stop*/

// Custom code after markers
extension UserExtension on User {
  String get displayName => name;
}
```

On regeneration, the contents between markers will be updated, and
all custom code will remain intact.

### Limitations and simplifications

- Only top-level schemas from `definitions` / `components.schemas` are processed.
- `$ref` to other schemas are resolved into Dart class types.
- Per-file mode supports all three generation styles
  (`plain_dart`, `json_serializable`, `freezed`).

---

For more detailed documentation, see [`docs/`](docs/).