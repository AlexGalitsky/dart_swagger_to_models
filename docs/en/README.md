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
- **`--library-name`, `-l`**: имя библиотеки/файла без расширения (по умолчанию `models`, исторический параметр).
- **`--style`, `-s`**: стиль генерации моделей:
  - `plain_dart` — простые Dart классы с ручным `fromJson`/`toJson` (по умолчанию),
  - `json_serializable` — классы с `@JsonSerializable()` и делегацией в `_$ClassFromJson`/`_$ClassToJson`,
  - `freezed` — иммутабельные классы `@freezed` с `const factory` и `fromJson`.
- **`--project-dir`**: корневая директория проекта для сканирования Dart файлов (поиск существующих файлов моделей, по умолчанию `.`).
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

### Режим per-file (одна модель = один файл)

Генератор **всегда** работает в режиме «одна модель = один файл». Для каждой схемы из Swagger/OpenAPI создаётся отдельный Dart-файл (например, `user.dart`, `order.dart`).

```bash
dart run dart_swagger_to_models:dart_swagger_to_models \
  --input api.yaml \
  --output-dir lib/models \
  --style plain_dart \
  --project-dir .
```

**Особенности режима:**

- **Одна модель = один файл**: каждая схема из Swagger/OpenAPI генерируется в отдельный файл (например, `user.dart`, `order.dart`).
- **Маркеры для идентификации**: каждый файл начинается с маркера `/*SWAGGER-TO-DART*/` для идентификации.
- **Интеграция с существующим кодом**: генератор сканирует проект (`--project-dir`) и обновляет существующие файлы с соответствующими маркерами.
- **Сохранение кастомного кода**: содержимое между маркерами `/*SWAGGER-TO-DART: Fields start*/` и `/*SWAGGER-TO-DART: Fields stop*/` заменяется, всё остальное сохраняется (импорты, методы, расширения и т.д.).

**Пример существующего файла:**

```dart
/*SWAGGER-TO-DART*/

import 'package:some_package/some_package.dart';

// Кастомный код до маркеров
void customFunction() {
  print('Custom code');
}

/*SWAGGER-TO-DART: Fields start*/
// Здесь будет сгенерированный класс
class User {
  final int id;
  final String? name;
  // ...
}
/*SWAGGER-TO-DART: Fields stop*/

// Кастомный код после маркеров
extension UserExtension on User {
  String get displayName => name ?? 'Unknown';
}
```

При повторной генерации содержимое между маркерами будет обновлено, а кастомный код сохранён.

### Ограничения и упрощения

- Схемы обрабатываются на уровне верхних сущностей (`definitions` / `components.schemas`).
- `$ref` на другие схемы разрешаются в типы Dart-классов.
- Режим per-file поддерживает все три стиля генерации (`plain_dart`, `json_serializable`, `freezed`).

