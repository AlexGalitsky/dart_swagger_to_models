## 0.2.1 (Unreleased)

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

## 0.5.2 (Unreleased)

### Added
- Spec linting (подсказки по качеству спецификаций)
  - Конфигурируемые lint правила в `dart_swagger_to_models.yaml`
  - Поддержка включения/выключения отдельных правил
  - Настройка уровня серьёзности (warning vs error) для каждого правила
  - Доступные правила:
    - `missing_type` - поле без типа и без $ref
    - `suspicious_id_field` - подозрительное id поле (без required и без nullable)
    - `missing_ref_target` - отсутствующая цель для $ref
    - `type_inconsistency` - несогласованность типов (например, integer с format)
    - `empty_object` - пустой объект (нет properties и additionalProperties)
    - `array_without_items` - массив без items
    - `empty_enum` - enum без значений
  - Пример конфигурации:
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
