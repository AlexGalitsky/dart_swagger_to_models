## dart_swagger_to_models — контекст для LLM (RU)

Этот файл предназначен для нейросетей / LLM-инструментов, чтобы быстро
восстановить контекст проекта.

### Назначение проекта

- CLI-утилита для **генерации Dart-моделей** по спецификациям
  **Swagger / OpenAPI (2.0 / 3.x)**.
- Вход: JSON/YAML спецификация (путь к файлу или URL).
- Выход: **один Dart-файл на одну схему** (режим per-file, всегда включён).
- Поддерживаемые стили генерации:
  - `plain_dart` — обычные Dart-классы с ручным `fromJson` / `toJson`,
  - `json_serializable` — `@JsonSerializable()` + `part '*.g.dart';`,
  - `freezed` — `@freezed` + `part '*.freezed.dart';` + `part '*.g.dart';`.

### Ключевые файлы

- **`lib/dart_swagger_to_models.dart`**
  - Основной фасад: `SwaggerToDartGenerator.generateModels({ ... })`.
  - Парсит спецификацию (`loadSpec`, `detectVersion`,
    `_extractSchemas` / `_getAllSchemas`).
  - Реализует правило nullable (см. ниже).
  - Отвечает за per-file генерацию:
    - `_generateModelsPerFile` — обход всех схем.
    - `_scanProjectForMarkers` — поиск существующих Dart-файлов
      с маркером `/*SWAGGER-TO-DART*/`.
    - `_createNewFileWithEnum` / `_createNewFileWithClass` —
      создание новых файлов с маркерами и импортами под стиль.
    - `_updateExistingFileWithEnum` / `_updateExistingFileWithClass` —
      замена кода **только** между
      `/*SWAGGER-TO-DART: Fields start*/` и `/*SWAGGER-TO-DART: Fields stop*/`.
  - Использует паттерн Strategy через `GeneratorFactory`.
  - Валидирует схемы (`_validateSchemas`) и проверяет отсутствующие цели для `$ref` (`_checkMissingRefs`).
  - Собирает зависимости для генерации импортов (`_collectDependencies`, `_generateImportsForDependencies`).
  - Обрабатывает схемы композиции OpenAPI:
    - `_generateAllOfClass` — рекурсивная обработка вложенных комбинаций `allOf`, множественное наследование, обнаружение циклических зависимостей.
    - `_generateOneOfClass` — безопасные обёртки с `dynamic` для `oneOf`/`anyOf` с обнаружением и логированием discriminator.
  - Поддерживает инкрементальную генерацию:
    - Класс `GenerationCache` для кэширования хешей схем в `.dart_swagger_to_models.cache`
    - CLI флаг `--changed-only` для регенерации только изменённых схем
    - Автоматическое обнаружение новых, изменённых и удалённых схем
    - Автоматическая очистка файлов для удалённых схем
  - Логирует прогресс и ошибки через класс `Logger`.

- **`lib/src/generators/*.dart`**
  - `class_generator_strategy.dart`:
    - интерфейс `ClassGeneratorStrategy` с методом `generateFullClass(...)`,
    - `FieldInfo` (имя, `dartType`, `isRequired`, `schema`, `camelCaseName`).
  - `plain_dart_generator.dart`:
    - генерирует обычный Dart-класс (поля, `const` конструктор,
      `fromJson`/`toJson`).
  - `json_serializable_generator.dart`:
    - добавляет `@JsonSerializable()` и делегирует JSON в сгенерированные функции.
  - `freezed_generator.dart`:
    - добавляет `@freezed`, `const factory` и `fromJson`.
  - `generator_factory.dart`:
    - сопоставляет `GenerationStyle` → конкретная стратегия.
    - поддерживает кастомные стили через `StyleRegistry`.
  - `style_registry.dart`:
    - класс `StyleRegistry` для регистрации кастомных стилей генерации.
    - метод `register()` для регистрации кастомных стилей.
    - метод `createCustomStrategy()` для создания экземпляров стратегий.

- **CLI-вход**: `bin/dart_swagger_to_models.dart`
  - Парсит опции (`--input`, `--output-dir`, `--library-name`, `--style`,
    `--project-dir`, `--config`, `--verbose`, `--quiet`, `--format`).
  - Загружает конфигурацию из `dart_swagger_to_models.yaml` (если существует).
  - Устанавливает уровень логирования через `Logger.setLevel()` на основе флагов `--verbose`/`--quiet`.
  - Вызывает `SwaggerToDartGenerator.generateModels` с конфигурацией.
  - Отображает сводку генерации и накопленные предупреждения/ошибки.

- **Конфигурация**: `lib/src/config/*.dart`
  - `config.dart`: классы `Config` и `SchemaOverride`.
  - `config_loader.dart`: `ConfigLoader` для парсинга YAML конфигурационных файлов.
  - Поддерживает глобальные опции (`defaultStyle`, `outputDir`, `projectDir`, `useJsonKey`).
  - Поддерживает переопределения для схем (`className`, `fieldNames`, `typeMapping`, `useJsonKey`).
  - Приоритет: аргументы CLI > конфигурационный файл > значения по умолчанию.

- **Логирование**: `lib/src/core/logger.dart`
  - Класс `Logger` с уровнями логирования: `quiet`, `normal`, `verbose`.
  - Методы: `verbose()`, `info()`, `warning()`, `error()`, `debug()`, `success()`.
  - Накопление предупреждений и ошибок для последующего вывода сводки.
  - Используется по всему генератору для понятных сообщений пользователю.

- **Тесты**: `test/dart_swagger_to_models_test.dart`
  - E2E-тесты:
    - Swagger 2.0 и OpenAPI 3.0,
    - `nullable` поля, `allOf`, массивы, `additionalProperties`, `int` vs `num`,
    - все 3 стиля (plain, json_serializable, freezed),
    - per-file режим и перегенерация по маркерам,
    - поддержка конфигурационного файла и разрешение приоритетов,
    - генерация `@JsonKey` для snake_case JSON-ключей,
    - схемы композиции OpenAPI (`allOf`, `oneOf`, `anyOf`):
      - вложенные комбинации `allOf` и множественное наследование,
      - безопасные обёртки с `dynamic` для `oneOf`/`anyOf` с понятными сообщениями об ошибках,
      - обнаружение и логирование discriminator (архитектура подготовлена для будущей генерации union-типов),
      - обнаружение циклических зависимостей в `allOf`,
    - инкрементальная генерация:
      - первый запуск (генерирует все схемы и создаёт кэш),
      - инкрементальный запуск (только изменённые схемы),
      - добавление новых схем,
      - удаление схем,
      - изменение одной схемы в большой спецификации,
    - подключаемые стили:
      - регистрация кастомных стилей через `StyleRegistry`,
      - использование кастомных стилей через конфигурационный файл или CLI,
      - пример: генератор стиля Equatable,
    - генерация импортов между моделями,
    - улучшения для enum (`x-enumNames`, `x-enum-varnames`).

### Важные инварианты / правила

- **Per-file режим (всегда включён)**
  - Каждая схема → свой Dart-файл (`user.dart`, `order.dart` и т.п.).
  - В начале файла:

    ```dart
    /*SWAGGER-TO-DART*/
    ```

    маркер для идентификации.
  - Внутри файла:

    ```dart
    /*SWAGGER-TO-DART: Fields start*/
    // сгенерированный код
    /*SWAGGER-TO-DART: Fields stop*/
    ```

  - При перегенерации:
    - заменяется **только** содержимое между маркерами `Fields start/stop`,
    - остальной код (импорты, методы, extension'ы и т.п.) сохраняется.

- **Правило nullability (критично для моделей)**
  - Если поле присутствует в `properties` схемы — оно считается
    **required по умолчанию**.
  - Если у поля есть `nullable: true` — оно генерируется как nullable (`Type?`).
  - Реализация в `_generateClass`:
    - `isNonNullable = !propNullable;`
    - `dartType = _dartTypeForSchema(..., required: isNonNullable);`
  - `_dartTypeForSchema`:
    - возвращает `base`, если `required == true`,
    - возвращает `'$base?'`, если `required == false`.
  - Это правило одинаково для всех стилей.

### Частые команды (подсказка для инструментов)

- Базовая генерация:

```bash
dart run dart_swagger_to_models:dart_swagger_to_models --input api.yaml
```

- С указанием стиля и директории:

```bash
dart run dart_swagger_to_models:dart_swagger_to_models \
  --input api.yaml \
  --output-dir lib/models \
  --style json_serializable
```

- Перегенерация существующих файлов:

```bash
dart run dart_swagger_to_models:dart_swagger_to_models \
  --input api.yaml \
  --output-dir lib/models \
  --project-dir .
```

- Использование конфигурационного файла:

```bash
dart run dart_swagger_to_models:dart_swagger_to_models \
  --input api.yaml \
  --config dart_swagger_to_models.yaml
```

- С подробным логированием:

```bash
dart run dart_swagger_to_models:dart_swagger_to_models \
  --input api.yaml \
  --verbose
```

- Тихий режим (минимальный вывод):

```bash
dart run dart_swagger_to_models:dart_swagger_to_models \
  --input api.yaml \
  --quiet
```

### Рекомендации при изменении проекта (для LLM)

- Если меняется логика nullability:
  - править `_generateClass` и `_dartTypeForSchema`,
  - синхронизировать тесты в `test/dart_swagger_to_models_test.dart`,
    которые проверяют строки вида `final String? email;` и т.п.

- Если добавляется новый стиль:
  - добавить новое значение в `GenerationStyle`,
  - реализовать новую `ClassGeneratorStrategy`,
  - зарегистрировать её в `GeneratorFactory.createStrategy`,
  - добавить тесты в группу `Generation styles`.

