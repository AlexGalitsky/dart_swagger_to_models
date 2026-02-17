dart_swagger_to_models
======================

CLI-инструмент для генерации **null-safe Dart-моделей** из спецификаций
**Swagger / OpenAPI** (JSON/YAML).

### Установка

- **Локально в проект** (как dev-зависимость, пример):

```yaml
dev_dependencies:
  dart_swagger_to_models:
    path: ./tools/dart_swagger_to_models
```

### Использование (кратко)

- Базовый запуск:

```bash
dart run dart_swagger_to_models:dart_swagger_to_models --input api.yaml
```

- С указанием директории, имени библиотеки и стиля:

```bash
dart run dart_swagger_to_models:dart_swagger_to_models \
  --input api.yaml \
  --output-dir lib/generated_models \
  --library-name api_models \
  --style json_serializable
```

Поддерживаются **Swagger 2.0** (`swagger`) и **OpenAPI 3** (`openapi`).

### Основные аргументы CLI

- **`--input`, `-i`** — путь к спецификации (файл или URL), **обязательный**.
- **`--output-dir`, `-o`** — директория для моделей (по умолчанию `lib/models`).
- **`--library-name`, `-l`** — имя библиотеки (исторический параметр, в режиме per-file почти не используется).
- **`--style`, `-s`** — стиль генерации:
  - `plain_dart` — обычные Dart-классы с ручным `fromJson`/`toJson`,
  - `json_serializable` — классы с `@JsonSerializable()` и делегацией в `_$ClassFromJson` / `_$ClassToJson`,
  - `freezed` — иммутабельные классы `@freezed` с `const factory` и `fromJson`.
- **`--project-dir`** — корень проекта для сканирования существующих Dart-файлов.
- **`--config`, `-c`** — путь к конфигурационному файлу (по умолчанию ищется `dart_swagger_to_models.yaml` в корне проекта).
- **`--verbose`, `-v`** — подробный вывод (включает отладочную информацию).
- **`--quiet`, `-q`** — минимальный вывод (только ошибки и критичные сообщения).
- **`--help`, `-h`** — показать помощь.

### Конфигурационный файл

Создайте файл `dart_swagger_to_models.yaml` в корне проекта для настройки генератора. Подробнее см. в основной документации.

### Правила null-safety

- Если поле **присутствует в `properties`** схемы — оно считается **required по умолчанию**.
- Если у поля явно указано `nullable: true` — оно генерируется как nullable (`Type?`).

Это правило действует для всех стилей (`plain_dart`, `json_serializable`, `freezed`).

### Режим «одна модель = один файл»
### Режим «одна модель = один файл»

Генератор всегда работает в режиме per-file:
- каждая схема → отдельный Dart-файл (`user.dart`, `order.dart` и т.д.),
- в начале файла — маркер `/*SWAGGER-TO-DART*/` для идентификации,
- между маркерами `/*SWAGGER-TO-DART: Codegen start*/` и
  `/*SWAGGER-TO-DART: Codegen stop*/` код может безопасно перегенерироваться,
  остальной код (импорты, методы, расширения) сохраняется.

### Расширенные возможности OpenAPI-композиции

- `allOf`:
  - Объединение свойств из нескольких схем (включая вложенные `allOf` и множественное наследование).
  - Обнаружение и логирование циклических зависимостей.
- `oneOf` / `anyOf`:
  - Безопасные обёртки с `dynamic` для общих случаев.
  - Discriminator-aware union-классы при обнаружении паттерна discriminator+enum (см. `doc/en/USAGE.md#9-openapi-composition-schemas-allof-oneof-anyof` и `doc/en/UNION_TYPES_NOTES.md` для деталей).

Более подробные примеры и описание смотрите в:
- `doc/en/USAGE.md` — основная документация (EN),
- `doc/ru/USAGE.md` — подробное русскоязычное руководство по использованию.

