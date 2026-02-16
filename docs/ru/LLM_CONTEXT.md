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

- **CLI-вход**: `bin/dart_swagger_to_models.dart`
  - Парсит опции (`--input`, `--output-dir`, `--library-name`, `--style`,
    `--project-dir`).
  - Вызывает `SwaggerToDartGenerator.generateModels`.

- **Тесты**: `test/dart_swagger_to_models_test.dart`
  - E2E-тесты:
    - Swagger 2.0 и OpenAPI 3.0,
    - `nullable` поля, `allOf`, массивы, `additionalProperties`, `int` vs `num`,
    - все 3 стиля (plain, json_serializable, freezed),
    - per-file режим и перегенерация по маркерам.

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

