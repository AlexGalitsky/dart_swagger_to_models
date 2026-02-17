## Developer Guide — dart_swagger_to_models

This document explains how the project is structured and how to work with the codebase as a contributor.

### 1. Repository structure

- `lib/`
  - `dart_swagger_to_models.dart` — main library facade:
    - `SwaggerToDartGenerator.generateModels` — entry point for programmatic use.
    - Per-file generation (`_generateModelsPerFile`), imports, enums, classes.
    - OpenAPI composition (`_generateAllOfClass`, `_generateOneOfClass`).
    - Validation helpers (`_generateValidationExtension`).
    - Test data helpers (`_generateTestDataFactory`).
  - `src/config/`:
    - `config.dart` — `Config` and `SchemaOverride` models.
    - `config_loader.dart` — YAML parser for `dart_swagger_to_models.yaml`.
  - `src/core/`:
    - `types.dart` — enums and DTOs (`SpecVersion`, `GenerationStyle`, `GenerationResult`, `GenerationContext`).
    - `logger.dart` — logging utilities and in-memory warnings/errors.
    - `cache.dart` — incremental generation cache (`GenerationCache`).
    - `lint_rules.dart` — spec linting configuration (`LintConfig`, `LintRuleId`, `LintSeverity`).
  - `src/generators/`:
    - `class_generator_strategy.dart` — strategy interface + `FieldInfo`.
    - `plain_dart_generator.dart` — plain Dart classes.
    - `json_serializable_generator.dart` — `@JsonSerializable` classes.
    - `freezed_generator.dart` — `@freezed` data classes.
    - `generator_factory.dart` — maps `GenerationStyle` to strategy, integrates custom styles.
    - `style_registry.dart` — registration of custom generation strategies.
  - `src/build/swagger_builder.dart` — `build_runner` integration.

- `bin/dart_swagger_to_models.dart`
  - CLI entrypoint:
    - Parses arguments (`args` package).
    - Loads config via `ConfigLoader` (if present).
    - Sets `Logger` level.
    - Supports:
      - `--input`, `--output-dir`, `--library-name`, `--style`,
      - `--project-dir`, `--config`,
      - `--format`, `--verbose`, `--quiet`,
      - `--changed-only` (incremental),
      - `--watch` (file watch mode),
      - `--interactive` (interactive confirmation).
    - Calls `SwaggerToDartGenerator.generateModels` and prints summary.

- `doc/`
  - `en/USAGE.md` / `ru/USAGE.md` — main usage docs.
  - `en/CUSTOM_STYLES.md` / `ru/CUSTOM_STYLES.md` — custom style guides.
  - `en/LLM_CONTEXT.md` / `ru/LLM_CONTEXT.md` — LLM-oriented overview.
  - `en/UNION_TYPES_NOTES.md` — design notes for `oneOf`/`anyOf` unions.

- `test/`
  - `dart_swagger_to_models_test.dart` — master test file that imports topic-specific suites.
  - Topical tests:
    - `generator_test.dart` — core generation (Swagger/OpenAPI, enums, arrays, additionalProperties, int/num).
    - `generation_styles_test.dart` — styles (`plain_dart`, `json_serializable`, `freezed`).
    - `configuration_test.dart` — config loading and schema overrides.
    - `code_quality_test.dart` — code quality of generated models (imports, enums, etc.).
    - `json_key_test.dart` — `@JsonKey` behavior.
    - `linting_test.dart` — spec linting rules.
    - `openapi_test.dart` — `allOf`, `oneOf`, `anyOf` behavior.
    - `incremental_generation_test.dart` — incremental cache and `--changed-only`.
    - `pluggable_styles_test.dart` — custom styles via `StyleRegistry`.
    - `build_runner_test.dart` — basic `build_runner` integration placeholder.

### 2. Typical workflows

#### 2.1 Running analysis and tests

- Static analysis:

```bash
dart analyze bin lib test
```

- Tests:

```bash
dart test --reporter=compact
```

Use `--chain-stack-traces` when debugging complex failures:

```bash
dart test --chain-stack-traces test/dart_swagger_to_models_test.dart -p vm
```

#### 2.2 Developing a new feature

1. **Understand the scope**:
   - Check `ROADMAP.md` / `ROADMAP.ru.md` for the relevant version and task.
   - Skim `doc/en/USAGE.md` and `doc/ru/USAGE.md` sections that describe the area you are changing.

2. **Locate the code**:
   - Generation logic → `lib/dart_swagger_to_models.dart`.
   - Style-specific behavior → `lib/src/generators/*.dart`.
   - Config / flags → `lib/src/config/*.dart` and `bin/dart_swagger_to_models.dart`.
   - Spec linting → `lib/src/core/lint_rules.dart`.

3. **Add configuration (if needed)**:
   - Add new fields to `Config` and merge logic in `config.dart`.
   - Parse YAML in `ConfigLoader._parseConfig` (and/or `_parseSchemaOverride`).
   - If CLI flag is needed, add it to `bin/dart_swagger_to_models.dart` and map it into `Config`.

4. **Implement the feature**:
   - Prefer small, focused helpers in `lib/dart_swagger_to_models.dart` (e.g., `_generateXyz(...)`).
   - Keep per-file behavior and marker rules intact:
     - Only generated code between `Codegen start/stop` should be replaced.
   - Avoid breaking existing `GenerationStyle` semantics.

5. **Add / update tests**:
   - Create or extend a topical test file in `test/`.
   - Use temporary directories (`Directory.systemTemp.createTemp(...)`) to keep tests isolated.
   - Write expectations against generated file **content** using `contains(...)` rather than full-string equality.

6. **Update documentation**:
   - Update `doc/en/USAGE.md` and `doc/ru/USAGE.md` with new flags/options.
   - If behavior is non-trivial (like unions or validation), add a short note to `ROADMAP.md` and/or a dedicated `doc/en/*.md` file.

7. **Run `dart analyze` and `dart test`** before creating a PR.

### 3. Key design principles

- **Per-file mode only**:
  - Each schema → its own Dart file.
  - Only generated region between `/*SWAGGER-TO-DART: Codegen start*/` and `/*SWAGGER-TO-DART: Codegen stop*/` is modified.
  - All surrounding user code must be preserved.

- **Nullability contract**:
  - Field present in `properties` → required by default.
  - `nullable: true` → `Type?`.
  - This rule is style-independent and is enforced in `_generateClass` and `_dartTypeForSchema`.

- **Extensibility via strategies**:
  - To add a new style, implement `ClassGeneratorStrategy` and register it in `GeneratorFactory` or `StyleRegistry`.

- **Config/CLI precedence**:
  - CLI → Config file → Defaults.
  - Keep this order consistent when adding new settings.

- **Spec- vs code-level validation**:
  - Spec linting (missing types, suspicious ids, etc.) happens before generation via `_validateSchemas` and `_checkMissingRefs`.
  - Runtime validation (`validate()` helpers) is opt-in via `generateValidation` and should never crash on unexpected input (only report errors).

### 4. How to add a new generation style

1. Add a new value to `GenerationStyle` in `lib/src/core/types.dart` (if it is a built-in style).
2. Create a new file in `lib/src/generators/` that extends `ClassGeneratorStrategy`.
3. Wire it in:
   - Update `GeneratorFactory.createStrategy` to return your strategy for the new style.
   - Optionally register it via `StyleRegistry` (for custom styles).
4. Add tests:
   - Extend `test/generation_styles_test.dart` with expectations for the new style.
5. Document:
   - Add a short section to `doc/en/USAGE.md` and `doc/en/CUSTOM_STYLES.md`.

### 5. How to debug generation issues

- Enable verbose logging:

```bash
dart run dart_swagger_to_models:dart_swagger_to_models \
  --input api.yaml \
  --verbose
```

- When using `build_runner`, check:
  - `build.yaml` configuration.
  - That specs are under `swagger/`, `openapi/`, or `api/` directories.
  - That `dart_swagger_to_models` and `build_runner` are present in `pubspec.yaml`.

- For spec-related issues:
  - Temporarily enable stricter lint rules in `dart_swagger_to_models.yaml` under `lint.rules`.
  - Look at warnings printed after generation.

