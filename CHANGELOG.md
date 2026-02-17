## 0.4.2 (Unreleased)

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

## 0.3.2

### Added
- `@JsonKey` generation for snake_case JSON keys
  - Global config option `useJsonKey: true/false`
  - Per-schema override `useJsonKey` in schema overrides
  - Works with both `json_serializable` and `freezed` styles
  - Automatically detects when JSON key differs from Dart field name

## 0.2.2

### Added
- Configuration file support (`dart_swagger_to_models.yaml`)
  - Global options: `defaultStyle`, `outputDir`, `projectDir`
  - Per-schema overrides: `className`, `fieldNames`, `typeMapping`
- CLI option `--config` / `-c` for specifying custom config file path
- Priority system: CLI arguments > config file > defaults

## 1.0.0

- Initial version.
