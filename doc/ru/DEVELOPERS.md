## Руководство для разработчиков — dart_swagger_to_models

Этот документ описывает структуру проекта и порядок работы с кодовой базой для новых разработчиков.

### 1. Структура репозитория

- `lib/`
  - `dart_swagger_to_models.dart` — основной фасад библиотеки:
    - `SwaggerToDartGenerator.generateModels` — входная точка для программного использования.
    - Per-file генерация (`_generateModelsPerFile`), импорты, enum'ы, классы.
    - Композиция OpenAPI (`_generateAllOfClass`, `_generateOneOfClass`).
    - Генерация валидации (`_generateValidationExtension`).
    - Генерация тестовых данных (`_generateTestDataFactory`).
  - `src/config/`:
    - `config.dart` — модели `Config` и `SchemaOverride`.
    - `config_loader.dart` — парсер YAML-конфига `dart_swagger_to_models.yaml`.
  - `src/core/`:
    - `types.dart` — enum'ы и DTO (`SpecVersion`, `GenerationStyle`, `GenerationResult`, `GenerationContext`).
    - `logger.dart` — логгер и накопление предупреждений/ошибок.
    - `cache.dart` — кэш инкрементальной генерации (`GenerationCache`).
    - `lint_rules.dart` — конфигурация spec-lint'ов (`LintConfig`, `LintRuleId`, `LintSeverity`).
  - `src/generators/`:
    - `class_generator_strategy.dart` — интерфейс стратегии + `FieldInfo`.
    - `plain_dart_generator.dart` — обычные Dart-классы.
    - `json_serializable_generator.dart` — классы с `@JsonSerializable`.
    - `freezed_generator.dart` — иммутабельные классы `@freezed`.
    - `generator_factory.dart` — сопоставление `GenerationStyle` с стратегией, интеграция кастомных стилей.
    - `style_registry.dart` — регистрация кастомных стратегий генерации.
  - `src/build/swagger_builder.dart` — интеграция с `build_runner`.

- `bin/dart_swagger_to_models.dart`
  - CLI-входная точка:
    - Парсит аргументы (`args`).
    - Загружает конфиг через `ConfigLoader` (если он есть).
    - Настраивает уровень логирования через `Logger`.
    - Поддерживает:
      - `--input`, `--output-dir`, `--library-name`, `--style`,
      - `--project-dir`, `--config`,
      - `--format`, `--verbose`, `--quiet`,
      - `--changed-only` (инкрементальная генерация),
      - `--watch` (watch-режим),
      - `--interactive` (интерактивный режим с подтверждением).
    - Вызывает `SwaggerToDartGenerator.generateModels` и выводит сводку.

- `doc/`
  - `en/USAGE.md` / `ru/USAGE.md` — основная документация по использованию.
  - `en/CUSTOM_STYLES.md` / `ru/CUSTOM_STYLES.md` — руководство по кастомным стилям.
  - `en/LLM_CONTEXT.md` / `ru/LLM_CONTEXT.md` — краткий обзор для LLM-инструментов.
  - `en/UNION_TYPES_NOTES.md` — архитектурные заметки по union-типам (`oneOf`/`anyOf`).

- `test/`
  - `dart_swagger_to_models_test.dart` — главный файл, импортирующий тематические тестовые файлы.
  - Тематические тесты:
    - `generator_test.dart` — базовая генерация (Swagger/OpenAPI, enum'ы, массивы, `additionalProperties`, int/num).
    - `generation_styles_test.dart` — стили (`plain_dart`, `json_serializable`, `freezed`).
    - `configuration_test.dart` — загрузка конфига и overrides для схем.
    - `code_quality_test.dart` — качество сгенерированного кода (импорты, enum'ы и т.д.).
    - `json_key_test.dart` — поведение `@JsonKey`.
    - `linting_test.dart` — lint-правила спецификаций.
    - `openapi_test.dart` — поведение `allOf`, `oneOf`, `anyOf`.
    - `incremental_generation_test.dart` — инкрементальная генерация и `--changed-only`.
    - `pluggable_styles_test.dart` — кастомные стили через `StyleRegistry`.
    - `build_runner_test.dart` — базовый тест интеграции с `build_runner`.

### 2. Типовой рабочий процесс

#### 2.1 Запуск анализа и тестов

- Статический анализ:

```bash
dart analyze bin lib test
```

- Тесты:

```bash
dart test --reporter=compact
```

Для отладки сложных падений удобно добавлять `--chain-stack-traces`:

```bash
dart test --chain-stack-traces test/dart_swagger_to_models_test.dart -p vm
```

#### 2.2 Добавление новой фичи

1. **Определить область изменений**:
   - Посмотреть `ROADMAP.md` / `ROADMAP.ru.md` для соответствующей версии и задачи.
   - Прочитать релевантные секции в `doc/en/USAGE.md` и `doc/ru/USAGE.md`.

2. **Найти нужный код**:
   - Логика генерации → `lib/dart_swagger_to_models.dart`.
   - Поведение стилей → `lib/src/generators/*.dart`.
   - Конфиг и CLI-флаги → `lib/src/config/*.dart` и `bin/dart_swagger_to_models.dart`.
   - Lint'ы спецификаций → `lib/src/core/lint_rules.dart`.

3. **Добавить конфигурацию (при необходимости)**:
   - Добавить новые поля в `Config` и логику merge в `config.dart`.
   - Распарсить YAML в `ConfigLoader._parseConfig` (и/или `_parseSchemaOverride`).
   - Если нужен CLI-флаг — добавить его в `bin/dart_swagger_to_models.dart` и пробросить в `Config`.

4. **Реализовать фичу**:
   - По возможности, выносить логику в небольшие приватные функции (`_generateXxx(...)`) в `lib/dart_swagger_to_models.dart`.
   - Сохранять per-file поведение и правила маркеров:
     - модифицируется только код между `Codegen start/stop`,
     - пользовательский код вокруг маркеров не трогаем.
   - Не ломать существующие стили (`GenerationStyle`) и их контракт.

5. **Добавить / обновить тесты**:
   - Создать или расширить тематический тест в `test/`.
   - Использовать временные директории (`Directory.systemTemp.createTemp(...)`) для изоляции.
   - Проверять содержимое сгенерированных файлов через `contains(...)`, а не полное равенство строк.

6. **Обновить документацию**:
   - Обновить `doc/en/USAGE.md` и `doc/ru/USAGE.md` (флаги, опции, новые сценарии).
   - Для нетривиальных изменений (union-типы, валидация и т.п.) при необходимости добавить/обновить заметки в `ROADMAP.md` и/или отдельные файлы в `doc/en/*.md`.

7. **Перед PR**:
   - Обязательно прогнать `dart analyze` и `dart test`.

### 3. Ключевые принципы дизайна

- **Per-file режим**:
  - Каждая схема → свой Dart-файл.
  - При перегенерации изменяется только участок между `/*SWAGGER-TO-DART: Codegen start*/` и `/*SWAGGER-TO-DART: Codegen stop*/`.
  - Внешний пользовательский код (импорты, расширения, хелперы) всегда сохраняется.

- **Правило nullability**:
  - Поле есть в `properties` → оно считается required по умолчанию.
  - `nullable: true` → генерируется как `Type?`.
  - Реализация сконцентрирована в `_generateClass` и `_dartTypeForSchema` и не зависит от стиля.

- **Расширяемость через стратегии**:
  - Новый стиль реализуется как новый `ClassGeneratorStrategy` и регистрируется в `GeneratorFactory`/`StyleRegistry`.

- **Приоритеты конфигурации**:
  - CLI → конфиг-файл → значения по умолчанию.
  - При добавлении новых опций нужно соблюдать этот порядок.

- **Валидация**:
  - Lint'ы спецификаций (отсутствующие типы, подозрительные id и т.п.) выполняются **до** генерации через `_validateSchemas` и `_checkMissingRefs`.
  - Runtime-валидация (`validate()` helpers) включается флагом `generateValidation` и никогда не должна приводить к крэшу — только возвращать список ошибок.

### 4. Как добавить новый стиль генерации

1. Добавить новое значение в `GenerationStyle` в `lib/src/core/types.dart` (если это встроенный стиль).
2. Создать новый файл в `lib/src/generators/`, наследующий `ClassGeneratorStrategy`.
3. Прописать стиль в:
   - `GeneratorFactory.createStrategy` (возврат нужной стратегии),
   - при необходимости зарегистрировать через `StyleRegistry` (для полностью кастомных стилей).
4. Добавить тесты:
   - Расширить `test/generation_styles_test.dart` проверками для нового стиля.
5. Обновить документацию:
   - Добавить секцию в `doc/en/USAGE.md` и `doc/en/CUSTOM_STYLES.md` (и/или русские эквиваленты).

### 5. Как отлаживать проблемы с генерацией

- Включить подробный лог:

```bash
dart run dart_swagger_to_models:dart_swagger_to_models \
  --input api.yaml \
  --verbose
```

- При использовании `build_runner`:
  - Проверить `build.yaml` (наличие `dart_swagger_to_models|swaggerBuilder`).
  - Убедиться, что спецификации лежат в `swagger/`, `openapi/` или `api/`.
  - Убедиться, что `dart_swagger_to_models` и `build_runner` добавлены в `pubspec.yaml`.

- Для проблем со спецификациями:
  - Временно ужесточить lint-правила в `dart_swagger_to_models.yaml` в секции `lint.rules`.
  - Обратить внимание на предупреждения, выводимые после генерации.

