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

- **Базовый пример**:

```bash
dart run bin/dart_swagger_to_models.dart --input api.yaml
```

- **С указанием директории и имени библиотеки**:

```bash
dart run bin/dart_swagger_to_models.dart \
  --input api.yaml \
  --output-dir lib/generated_models \
  --library-name api_models
```

Поддерживаются Swagger 2.0 (`swagger`) и OpenAPI 3 (`openapi`).
Из секций `definitions` / `components.schemas` генерируются Dart-классы
с `fromJson` / `toJson` и null-safety полями.

### Аргументы CLI

- **`--input`, `-i`**: путь к Swagger/OpenAPI спецификации (файл или URL) — **обязательный**.
- **`--output-dir`, `-o`**: директория для сохранения моделей (по умолчанию `lib/models`).
- **`--library-name`, `-l`**: имя библиотеки/файла без расширения (по умолчанию `models`).
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

