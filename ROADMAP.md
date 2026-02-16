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

---

Next step recommendation
------------------------

Start with **v0.2.2 (configuration file)** and **v0.2.3 (generated code quality)**:
- They are relatively contained.
- Сильно улучшают DX без ломки существующего API.
- Хорошо ложатся в отдельные GitHub issues / PR.

