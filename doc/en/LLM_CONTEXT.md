## dart_swagger_to_models — LLM context (EN)

This file is optimized for neural network / LLM tools to quickly restore
the project context.

### What this project does

- CLI tool that **generates Dart model classes** from **Swagger / OpenAPI (2.0 / 3.x)** specs.
- Input: JSON/YAML spec (file path or URL).
- Output: **one Dart file per schema** (per-file mode, always enabled).
- Supports three generation styles:
  - `plain_dart` — manual `fromJson` / `toJson`,
  - `json_serializable` — `@JsonSerializable()` + `part '*.g.dart';`,
  - `freezed` — `@freezed` + `part '*.freezed.dart';` + `part '*.g.dart';`.

### Core files

- **`lib/dart_swagger_to_models.dart`**
  - Public API: `SwaggerToDartGenerator.generateModels({ ... })`.
  - Parses spec (`loadSpec`, `detectVersion`, `_extractSchemas` / `_getAllSchemas`).
  - Applies **nullability rule** (see below).
  - Implements per-file generation:
    - `_generateModelsPerFile` — main loop over schemas.
    - `_scanProjectForMarkers` — finds existing Dart files with
      `/*SWAGGER-TO-DART*/` marker.
    - `_createNewFileWithEnum` / `_createNewFileWithClass` — create new files with markers and style-specific imports.
    - `_updateExistingFileWithEnum` / `_updateExistingFileWithClass` — replace code **only** between
      `/*SWAGGER-TO-DART: Codegen start*/` and `/*SWAGGER-TO-DART: Codegen stop*/`.
  - Uses strategy pattern for class body generation via `GeneratorFactory`.
  - Validates schemas (`_validateSchemas`) and checks for missing `$ref` targets (`_checkMissingRefs`).
  - Collects dependencies for import generation (`_collectDependencies`, `_generateImportsForDependencies`).
  - Handles OpenAPI composition schemas:
    - `_generateAllOfClass` — recursive handling of nested `allOf` combinations, multiple inheritance, circular dependency detection.
    - `_generateOneOfClass` — 
      - safe `dynamic` wrappers for plain `oneOf`/`anyOf` (without discriminator),
      - discriminator-aware union-style classes (single class with discriminator field, nullable variant fields, `when`/`maybeWhen` helpers) when discriminator+enum pattern is detected.
  - Supports incremental generation:
    - `GenerationCache` class for caching schema hashes in `.dart_swagger_to_models.cache`
    - `--changed-only` CLI flag to regenerate only changed schemas
    - Automatic detection of new, modified, and deleted schemas
    - Automatic cleanup of files for deleted schemas
  - Logs progress and errors via `Logger` class.

- **`lib/src/generators/*.dart`**
  - `class_generator_strategy.dart`:
    - `ClassGeneratorStrategy` interface with `generateFullClass(...)`.
    - `FieldInfo` (name, `dartType`, `isRequired`, `schema`, `camelCaseName`).
  - `plain_dart_generator.dart`:
    - Builds normal Dart class with fields, `const` ctor, manual `fromJson`/`toJson`.
  - `json_serializable_generator.dart`:
    - Adds `@JsonSerializable()` and delegates JSON methods to generated functions.
  - `freezed_generator.dart`:
    - Adds `@freezed`, `const factory`, and `fromJson`.
  - `generator_factory.dart`:
    - Maps `GenerationStyle` → corresponding strategy implementation.
    - Supports custom styles via `StyleRegistry`.
  - `style_registry.dart`:
    - `StyleRegistry` class for registering custom generation styles.
    - `register()` method to register custom styles.
    - `createCustomStrategy()` to create strategy instances.

- **CLI entrypoint**: `bin/dart_swagger_to_models.dart`
  - Parses options (`--input`, `--output-dir`, `--library-name`, `--style`,
    `--project-dir`, `--config`, `--verbose`, `--quiet`, `--format`).
  - Loads configuration from `dart_swagger_to_models.yaml` (if exists).
  - Sets up logging level via `Logger.setLevel()` based on `--verbose`/`--quiet` flags.
  - Calls `SwaggerToDartGenerator.generateModels` with config.
  - Displays generation summary and accumulated warnings/errors.

- **build_runner integration**: `lib/src/build/swagger_builder.dart`
  - `SwaggerBuilder` class implements `Builder` interface for build_runner.
  - Automatically detects OpenAPI/Swagger specification files in `swagger/`, `openapi/`, or `api/` directories.
  - Generates models as part of build pipeline.
  - Supports all configuration options via `dart_swagger_to_models.yaml`.
  - Example projects in `example/dart_example/` and `example/flutter_example/`.

- **Configuration**: `lib/src/config/*.dart`
  - `config.dart`: `Config` and `SchemaOverride` classes.
  - `config_loader.dart`: `ConfigLoader` for parsing YAML config files.
  - Supports global options (`defaultStyle`, `outputDir`, `projectDir`, `useJsonKey`, `generateDocs`, `generateValidation`, `generateTestData`).
  - Supports per-schema overrides (`className`, `fieldNames`, `typeMapping`, `useJsonKey`).
  - Priority: CLI arguments > config file > defaults.

- **Logging**: `lib/src/core/logger.dart`
  - `Logger` class with log levels: `quiet`, `normal`, `verbose`.
  - Methods: `verbose()`, `info()`, `warning()`, `error()`, `debug()`, `success()`.
  - Accumulates warnings and errors for summary display.
  - Used throughout the generator for user-friendly messages.

- **Tests**: `test/dart_swagger_to_models_test.dart`
  - End-to-end tests for:
    - Swagger 2.0 and OpenAPI 3.0.
    - `nullable` fields, `allOf`, arrays, `additionalProperties`, int vs num.
    - All 3 styles (plain, json_serializable, freezed).
    - Per-file mode and marker-based regeneration.
    - Configuration file support and priority resolution.
    - `@JsonKey` generation for snake_case JSON keys.
    - Import generation between models.
    - Enum improvements (`x-enumNames`, `x-enum-varnames`).
    - OpenAPI composition schemas (`allOf`, `oneOf`, `anyOf`):
      - Nested `allOf` combinations and multiple inheritance.
      - Safe `dynamic` wrappers for `oneOf`/`anyOf` with clear error messages.
      - Discriminator detection and logging (architecture prepared for future union-type generation).
      - Circular dependency detection in `allOf`.
    - Incremental generation:
      - First run (generates all schemas and creates cache).
      - Incremental run (only changed schemas).
      - Adding new schemas.
      - Removing schemas.
      - Modifying single schema in large spec.
    - Pluggable styles:
      - Registering custom styles via `StyleRegistry`.
      - Using custom styles via config file or CLI.
      - Example: Equatable style generator.

### Key invariants / rules

- **Per-file mode (ALWAYS on)**
  - Each schema becomes its own file (`user.dart`, `order.dart`, etc.).
  - Files start with:

    ```dart
    /*SWAGGER-TO-DART*/
    ```

    marker for identification.
  - Inside file:

    ```dart
    /*SWAGGER-TO-DART: Codegen start*/
    // generated code
    /*SWAGGER-TO-DART: Codegen stop*/
    ```

  - On regeneration:
    - **Only** content between `Codegen start/stop` is replaced.
    - Everything else (imports, helper functions, extensions) is preserved.

- **Nullability rule (important for models)**
  - If a field is present in the schema `properties` → it is **treated as required by default**.
  - If the field has `nullable: true` → it is generated as **nullable** (`Type?`).
  - This rule is implemented in `_generateClass`:
    - `isNonNullable = !propNullable;`
    - `dartType = _dartTypeForSchema(..., required: isNonNullable);`
  - `_dartTypeForSchema`:
    - Returns `base` if `required == true`, otherwise `'$base?'`.

- **Styles behave consistently**
  - All three strategies use `FieldInfo.dartType` & `FieldInfo.isRequired`.
  - Nullability semantics are **style-independent**.

### Typical commands (for tools to suggest)

- Basic:

```bash
dart run dart_swagger_to_models:dart_swagger_to_models --input api.yaml
```

- With style and custom output:

```bash
dart run dart_swagger_to_models:dart_swagger_to_models \
  --input api.yaml \
  --output-dir lib/models \
  --style json_serializable
```

- Regenerating existing files:

```bash
dart run dart_swagger_to_models:dart_swagger_to_models \
  --input api.yaml \
  --output-dir lib/models \
  --project-dir .
```

- Using configuration file:

```bash
dart run dart_swagger_to_models:dart_swagger_to_models \
  --input api.yaml \
  --config dart_swagger_to_models.yaml
```

- With verbose logging:

```bash
dart run dart_swagger_to_models:dart_swagger_to_models \
  --input api.yaml \
  --verbose
```

- Quiet mode (minimal output):

```bash
dart run dart_swagger_to_models:dart_swagger_to_models \
  --input api.yaml \
  --quiet
```

### When modifying this project (for LLMs)

- If you change nullability logic:
  - Update `_generateClass` and `_dartTypeForSchema`.
  - Sync tests in `test/dart_swagger_to_models_test.dart` that assert on field
    declarations (they look for strings like `final String? email;`).

- If you add a new style:
  - Add new value to `GenerationStyle`.
  - Implement a new `ClassGeneratorStrategy`.
  - Wire it into `GeneratorFactory.createStrategy`.
  - Extend tests in the `Generation styles` group.

