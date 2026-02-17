dart_swagger_to_models — Roadmap
================================

Ниже — план развития проекта. Формулировки на английском, чтобы было проще использовать в issue / PR.

## v0.2 — Core hardening & DX

### 0.2.1 Improved OpenAPI handling
- Normalize support for `oneOf` / `anyOf`:
  - Provide safer `dynamic` wrappers and clear log messages for now.
  - Prepare architecture for future union-type generation (especially with `discriminator`).
- Extend `allOf` support:
  - Handle nested `allOf` combinations and multiple inheritance cases.
  - Add tests for complex composed schemas.

### 0.2.2 Generator configuration file
- Add support for `dart_swagger_to_models.yaml` at project root:
  - Global options: `defaultStyle`, `outputDir`, `projectDir`.
  - Per-schema overrides: custom `className`, custom field names, type overrides.
- Add `--config` CLI option to specify a custom config path.
- Tests:
  - Priority resolution: CLI > config > defaults.

### 0.2.3 Generated code quality
- Run `dart format` on all generated files (behind `--format` flag).
- Enum improvements:
  - Support `x-enumNames` / `x-enum-varnames` when present.
  - Keep current behavior as fallback.
- Ensure correct imports between generated models instead of `dynamic` where a real schema exists.

## v0.3 — Extensibility & styles

### 0.3.1 Pluggable styles
- Public API for registering custom generation styles:
  - External package can provide its own `ClassGeneratorStrategy`.
  - Map style name → strategy via config or extension point.
- Example custom style:
  - e.g. `equatable` support, extra `copyWith`, etc.
- Documentation:
  - “How to create your own generation style” with step‑by‑step guide.

### 0.3.2 Better json_serializable / freezed ergonomics
- Optional `@JsonKey(name: '...')` generation for snake_case JSON keys.
- Config options:
  - `useJsonKey: true/false` (global and per-schema).
- Update docs and tests to cover `JsonKey` behavior in both `json_serializable` and `freezed` modes.

## v0.4 — Ecosystem integration

### 0.4.1 build_runner integration
- Implement a `Builder` that:
  - Reads Swagger/OpenAPI spec and config.
  - Generates models as part of `build_runner` pipeline.
- Provide an `example/` project:
  - Pure Dart example.
  - Flutter example using generated models + HTTP client.
- Document build_runner integration in `docs/en/USAGE.md` and `docs/ru/USAGE.md`.

### 0.4.2 DX & logging
- CLI flags:
  - `--verbose` for detailed logs.
  - `--quiet` for minimal output.
- Human‑friendly error messages:
  - Missing `$ref` targets.
  - Unsupported or ambiguous schema constructs.
  - Warnings about suspicious specs (e.g. `id` without `nullable: true` but no `required`).
- Summary after generation:
  - Number of processed schemas, enums, created/updated files.

## v0.5 — Incremental generation & spec linting

### 0.5.1 Incremental generation
- Cache last processed spec (per-schema hash) in `.dart_swagger_to_models.cache`.
- `--changed-only` option:
  - Regenerate only models whose schemas actually changed.
- Tests:
  - Adding a new schema.
  - Removing a schema.
  - Modifying only one schema in a large spec.

### 0.5.2 Spec quality hints
- Optional “lint” layer for specs:
  - Warn on fields without `type`.
  - Warn on obviously inconsistent constructs (configurable).
- Configurable rules in `dart_swagger_to_models.yaml`:
  - Enable/disable individual lint rules.
  - Choose warning vs error severity.

## v0.6 — Advanced OpenAPI features

### 0.6.1 Union types for oneOf/anyOf
- Generate proper union types instead of `dynamic` wrappers:
  - Support `discriminator` property for type discrimination
  - Generate sealed classes or freezed unions
  - Type-safe pattern matching for union types
- Configuration:
  - Option to choose union type implementation (sealed classes vs freezed unions)
  - Support for custom discriminator mappings
- Tests:
  - Complex oneOf/anyOf scenarios with discriminator
  - Nested union types
  - Union types with allOf combinations

### 0.6.2 Schema validation generation
- Generate validation code based on Swagger constraints:
  - `min`/`max` for numbers and strings
  - `pattern` for string validation (RegExp)
  - `format` validation (email, uri, date-time, etc.)
  - `minLength`/`maxLength` for strings and arrays
  - `minItems`/`maxItems` for arrays
- Integration options:
  - Generate validation methods in models
  - Support for validation packages (dart_validators, reactive_forms)
  - Optional validation annotations
- Configuration:
  - Enable/disable validation generation
  - Choose validation approach (methods vs annotations)

### 0.6.3 Documentation generation
- Generate DartDoc comments from Swagger descriptions:
  - Class-level documentation from schema `description`
  - Field-level documentation from property `description`
  - Preserve examples from Swagger as code comments
  - Support for markdown in descriptions
- Configuration:
  - Enable/disable documentation generation
  - Customize documentation format

## v0.7 — Developer experience improvements

### 0.7.1 Watch mode
- `--watch` flag for automatic regeneration:
  - Monitor specification file for changes
  - Regenerate models automatically on file save
  - Support for multiple specification files
  - Configurable debounce delay
- Features:
  - Show diff preview before regeneration
  - Option to confirm before overwriting files
  - Integration with IDE file watchers

### 0.7.2 Test data generation
- Generate test factories for models:
  - Create separate files with test factories (e.g., `test/models/factories/`)
  - Use Swagger examples for realistic test data
  - Generate valid/invalid variants for testing
  - Support for faker libraries (faker_dart)
- Configuration:
  - Output directory for test factories
  - Customize factory generation style
  - Include/exclude specific schemas

### 0.7.3 Interactive mode
- CLI interactive mode for selective generation:
  - Menu-based selection of schemas to generate
  - Preview of changes before generation
  - Confirmation prompts for file overwrites
  - Show diff for existing files
- Features:
  - Filter schemas by name pattern
  - Batch operations (select all, deselect all)
  - Save/load selection presets

## v0.8 — Performance & scalability

### 0.8.1 Parallel generation
- Generate multiple models in parallel:
  - Utilize multiple CPU cores for faster generation
  - Parallel processing of independent schemas
  - Progress tracking for parallel operations
- Configuration:
  - Number of parallel workers
  - Memory usage optimization

### 0.8.2 Large specification optimization
- Optimizations for large specifications (1000+ schemas):
  - Streaming JSON/YAML parsing
  - Incremental schema processing
  - Memory-efficient dependency resolution
  - Progress indicators for long operations

### 0.8.3 Caching improvements
- Enhanced caching system:
  - Cache parsed specifications
  - Cache resolved $ref references
  - Cache generated code templates
  - Cache invalidation strategies

## v0.9 — Ecosystem & integrations

### 0.9.1 State management integrations
- Generate code for popular state management solutions:
  - Riverpod providers for models
  - BLoC events and states
  - Provider factories
- Configuration:
  - Choose state management library
  - Customize generation patterns

### 0.9.2 API client generation (experimental)
- Generate HTTP client code from OpenAPI paths:
  - REST API client methods
  - Request/response type safety
  - Error handling
  - Support for popular HTTP clients (dio, http, chopper)
- Configuration:
  - Choose HTTP client library
  - Customize client generation style
  - Base URL configuration

### 0.9.3 CI/CD integration
- GitHub Actions workflow templates
- GitLab CI configuration examples
- Pre-commit hooks for model validation
- Automated model generation in CI pipelines

## v0.10 — Advanced features

### 0.10.1 Custom code templates
- Support for custom code templates:
  - Template engine for model generation
  - User-defined templates per style
  - Template inheritance and composition
- Configuration:
  - Template directory
  - Template selection per schema

### 0.10.2 Multi-file specification support
- Support for multiple specification files:
  - Merge multiple OpenAPI/Swagger files
  - Resolve cross-file $ref references
  - Generate models from multiple sources
- Configuration:
  - Specification file list
  - Merge strategy

### 0.10.3 Code generation hooks
- Pre/post generation hooks:
  - Custom scripts before/after generation
  - Transform generated code
  - Custom validation
- Configuration:
  - Hook scripts configuration
  - Hook execution order

---

## Completed versions

✅ **v0.2** — Core hardening & DX (all tasks completed)
✅ **v0.3** — Extensibility & styles (all tasks completed)
✅ **v0.4** — Ecosystem integration (all tasks completed)
✅ **v0.5** — Incremental generation & spec linting (all tasks completed)

---

## Next step recommendation

Recommended starting points for v0.6+:

1. **v0.6.1 (Union types)** — High value, builds on existing oneOf/anyOf architecture
2. **v0.7.1 (Watch mode)** — Great DX improvement, relatively straightforward
3. **v0.6.3 (Documentation generation)** — Quick win, improves code quality

These tasks are relatively self-contained and can be split into separate GitHub Issues / PRs.

