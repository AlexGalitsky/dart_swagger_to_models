## 0.6.0

### Added
- Advanced OpenAPI `oneOf`/`anyOf` support:
  - Dynamic wrappers for `oneOf`/`anyOf` without discriminator.
  - Discriminator-aware union-style classes (single class with discriminator field, nullable variant fields and `when`/`maybeWhen` helpers) when the `discriminator` + enum pattern is detected.
  - Detailed design notes in `doc/en/UNION_TYPES_NOTES.md`.
- Runtime validation helpers:
  - Optional `generateValidation: true` flag in `dart_swagger_to_models.yaml`.
  - `validate()` extension methods generated per model, based on schema constraints:
    - `minimum` / `maximum` (or `min` / `max`) for numeric fields,
    - `minLength` / `maxLength` for string lengths,
    - `minItems` / `maxItems` for array lengths.
- DartDoc generation:
  - Optional `generateDocs: true` flag in `dart_swagger_to_models.yaml`.
  - Class-level and field-level DartDoc comments from OpenAPI/Swagger `description` / `example`.
- Test data helpers:
  - Optional `generateTestData: true` flag in `dart_swagger_to_models.yaml`.
  - Simple test data factories per model (e.g. `User createUserTestData(...)`) with sensible defaults for primitive fields.
- DX improvements:
  - `--watch` mode for automatic regeneration when the input spec file changes.
  - `--interactive` mode that shows the list of schemas and asks for confirmation before generation.
  - New developer guides: `doc/en/DEVELOPERS.md` and `doc/ru/DEVELOPERS.md`.

## 0.5.2

### Added
- Spec linting (spec quality hints)
  - Configurable lint rules in `dart_swagger_to_models.yaml`
  - Ability to enable/disable individual rules
  - Configurable severity level (warning vs error) for each rule
  - Available rules:
    - `missing_type` - field without type and without $ref
    - `suspicious_id_field` - suspicious id field (not required and not nullable)
    - `missing_ref_target` - missing target for $ref
    - `type_inconsistency` - type inconsistency (for example, integer with format)
    - `empty_object` - empty object (no properties and no additionalProperties)
    - `array_without_items` - array without items
    - `empty_enum` - enum without values
  - Example configuration:
    ```yaml
    lint:
      enabled: true
      rules:
        missing_type: error
        suspicious_id_field: warning
        missing_ref_target: error
        type_inconsistency: warning
        empty_object: off
        array_without_items: warning
        empty_enum: warning
    ```

## 0.5.1

### Added
- Incremental generation
  - Cache system for tracking schema changes:
    - Caches schema hashes in `.dart_swagger_to_models.cache` file
    - Uses SHA-256 hashes to detect schema changes
    - Automatically handles new, modified, and deleted schemas
  - `--changed-only` CLI flag:
    - Regenerates only schemas that have changed since last run
    - Significantly improves performance for large specifications
    - Automatically removes files for deleted schemas
  - Comprehensive tests:
    - First run (generates all schemas)
    - Incremental run (only changed schemas)
    - Adding new schemas
    - Removing schemas
    - Modifying single schema in large spec
  - Example usage:
    ```bash
    # First run - generates all schemas
    dart run dart_swagger_to_models:dart_swagger_to_models \
      --input api.yaml \
      --changed-only
    
    # Subsequent runs - only changed schemas
    dart run dart_swagger_to_models:dart_swagger_to_models \
      --input api.yaml \
      --changed-only
    ```

## 0.4.2

### Added
- Improved DX and logging
  - CLI flags `--verbose` / `-v` for detailed logs
  - CLI flag `--quiet` / `-q` for minimal output
  - Human-friendly error messages for missing `$ref` targets
  - Warnings about unsupported or ambiguous schema constructs
  - Warnings about suspicious specs (e.g., `id` without `nullable: true` but no `required`)
  - Summary after generation showing:
    - Number of processed schemas
    - Number of processed enums
    - Number of created/updated files
    - Total files generated

## 0.4.1

### Added
- build_runner integration
  - `SwaggerBuilder` class for generating models as part of build_runner pipeline
  - Automatic detection of OpenAPI/Swagger specification files in `swagger/`, `openapi/`, or `api/` directories
  - Configuration via `build.yaml` file
  - Support for all generation styles (plain_dart, json_serializable, freezed)
  - Example projects:
    - `example/dart_example/` - Pure Dart project demonstrating build_runner integration
    - `example/flutter_example/` - Flutter project with HTTP client integration
  - Documentation:
    - Added section "Integration with build_runner" to `doc/en/USAGE.md`
  - Added section "Integration with build_runner" to `doc/ru/USAGE.md`
  - Usage:
    ```yaml
    # build.yaml
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
    ```bash
    # Run build_runner
    dart run build_runner build
    # or for Flutter
    flutter pub run build_runner build
    ```
  - Features:
    - Automatic model generation when specifications change
    - Seamless integration with other code generators (e.g., json_serializable)
    - Works with all configuration options (defaultStyle, outputDir, useJsonKey, etc.)
    - Generated files are part of project structure for IDE support

## 0.3.2

### Added
- `@JsonKey` generation for snake_case JSON keys
  - Global config option `useJsonKey: true/false`
  - Per-schema override `useJsonKey` in schema overrides
  - Works with both `json_serializable` and `freezed` styles
  - Automatically detects when JSON key differs from Dart field name

## 0.3.1

### Added
- Pluggable styles
  - Public API for registering custom generation styles:
    - `StyleRegistry` class for registering custom styles
    - `StyleRegistry.register()` method to register a custom style
    - `StyleRegistry.createCustomStrategy()` to create a strategy instance
    - Support for custom style names in configuration files
    - Support for custom style names via CLI `--style` option
  - Example custom style:
    - `example/custom_style_equatable.dart` - Complete example of an Equatable style generator
  - Documentation:
    - `doc/en/CUSTOM_STYLES.md` - Step-by-step guide on creating custom styles
    - `doc/ru/CUSTOM_STYLES.md` - Step-by-step guide in Russian
  - Usage:
    ```dart
    // Register a custom style
    StyleRegistry.register('my_style', () => MyCustomGenerator());
    
    // Use in config file
    // dart_swagger_to_models.yaml:
    // defaultStyle: my_style
    
    // Or via CLI
    // --style my_style
    ```
  - Features:
    - External packages can provide their own `ClassGeneratorStrategy` implementations
    - Style name → strategy mapping via `StyleRegistry`
    - Custom styles work alongside built-in styles (`plain_dart`, `json_serializable`, `freezed`)
    - Clear error messages when using unregistered styles

## 0.2.2

### Added
- Configuration file support (`dart_swagger_to_models.yaml`)
  - Global options: `defaultStyle`, `outputDir`, `projectDir`
  - Per-schema overrides: `className`, `fieldNames`, `typeMapping`
- CLI option `--config` / `-c` for specifying custom config file path
- Priority system: CLI arguments > config file > defaults

## 0.2.1

### Added
- Improved OpenAPI handling
  - Enhanced `oneOf` / `anyOf` support:
    - Safer `dynamic` wrappers with clear error messages
    - Architecture prepared for future union-type generation (especially with `discriminator`)
    - Verbose logging about possible types in `oneOf`/`anyOf` schemas
    - Detection and logging of `discriminator` usage
  - Extended `allOf` support:
    - Recursive handling of nested `allOf` combinations
    - Support for multiple inheritance cases
    - Detection and prevention of circular dependencies
    - Verbose logging for nested `allOf` processing
  - Comprehensive tests for complex composed schemas:
    - Nested `allOf` combinations
    - Multiple inheritance through `allOf`
    - `oneOf` / `anyOf` with discriminator
    - Circular dependency handling
