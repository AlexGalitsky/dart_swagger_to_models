dart_swagger_to_models
======================

Генератор Dart-моделей по Swagger/OpenAPI спецификациям (JSON/YAML).

### Установка

- **Локально в проект** (как dev-зависимость, пример):

```yaml
dev_dependencies:
  dart_swagger_to_models:
    path: ./tools/dart_swagger_to_models
```

### Использование

- **Базовый пример (`plain_dart`)**:

```bash
dart run dart_swagger_to_models:dart_swagger_to_models --input api.yaml
```

- **С указанием директории, имени библиотеки и стиля**:

```bash
dart run dart_swagger_to_models:dart_swagger_to_models \
  --input api.yaml \
  --output-dir lib/generated_models \
  --library-name api_models \
  --style json_serializable
```

Поддерживаются Swagger 2.0 (`swagger`) и OpenAPI 3 (`openapi`).
Из секций `definitions` / `components.schemas` генерируются Dart-классы
с `fromJson` / `toJson` и null-safety полями.

### Аргументы CLI

- **`--input`, `-i`**: путь к Swagger/OpenAPI спецификации (файл или URL) — **обязательный**.
- **`--output-dir`, `-o`**: директория для сохранения моделей (по умолчанию `lib/models`).
- **`--library-name`, `-l`**: имя библиотеки/файла без расширения (по умолчанию `models`).
- **`--style`, `-s`**: стиль генерации моделей:
  - `plain_dart` — простые Dart классы с ручным `fromJson`/`toJson` (по умолчанию),
  - `json_serializable` — классы с `@JsonSerializable()` и делегацией в `_$ClassFromJson`/`_$ClassToJson`,
  - `freezed` — иммутабельные классы `@freezed` с `const factory` и `fromJson`.
- **`--help`, `-h`**: показать помощь.

### Пример результата

Для определения:

```yaml
definitions:
  User:
    type: object
    required:
      - id
      - name
    properties:
      id:
        type: integer
      name:
        type: string
      email:
        type: string
```

будет сгенерирован Dart-класс `User` с обязательными полями `id`, `name`
и опциональным `email`, а также методами `fromJson` и `toJson`.

### Ограничения и упрощения

- Схемы обрабатываются на уровне верхних сущностей (`definitions` / `components.schemas`).
- Наследование (`allOf`, `oneOf`, `anyOf`) и сложные комбинации пока не поддерживаются.
- `$ref` на другие схемы разрешаются в типы Dart-классов.

