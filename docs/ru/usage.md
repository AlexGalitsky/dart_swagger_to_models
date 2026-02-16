## Использование dart_swagger_to_models (RU)

Этот документ описывает типовые сценарии использования `dart_swagger_to_models`.

### 1. Базовая генерация

Генерация моделей из локального файла `api.yaml` (стиль `plain_dart`,
одна модель = один файл):

```bash
dart run dart_swagger_to_models:dart_swagger_to_models --input api.yaml
```

Модели будут записаны в директорию `lib/models` (по умолчанию).

### 2. Кастомная директория и стиль

```bash
dart run dart_swagger_to_models:dart_swagger_to_models \
  --input api.yaml \
  --output-dir lib/api_models \
  --style json_serializable
```

В этом случае:
- файлы будут записаны в `lib/api_models`,
- для моделей будет сгенерирован стиль `json_serializable` c
  `@JsonSerializable()` и `part '*.g.dart';`.

### 3. Использование стиля `freezed`

```bash
dart run dart_swagger_to_models:dart_swagger_to_models \
  --input openapi.yaml \
  --output-dir lib/models \
  --style freezed
```

Каждая модель будет выглядеть примерно так:

```dart
@freezed
class User with _$User {
  const factory User({
    required int id,
    required String name,
    String? email,
  }) = _User;

  factory User.fromJson(Map<String, dynamic> json) => _$UserFromJson(json);
}
```

### 4. Выборочная перегенерация по endpoint (`--endpoint`)

Если модель уже интегрирована в проект и содержит маркер:

```dart
/*SWAGGER-TO-DART:https://api.example.com/v1/users*/
```

можно перегенерировать только файлы с этим маркером:

```bash
dart run dart_swagger_to_models:dart_swagger_to_models \
  --input api.yaml \
  --output-dir lib/models \
  --project-dir . \
  --endpoint https://api.example.com/v1/users
```

Будут обновлены только те Dart-файлы, где в маркере указан данный URL.

### 5. Правила null-safety

Генератор использует простое правило:
- Если поле присутствует в `properties` схемы — оно **required по умолчанию**.
- Если у поля есть `nullable: true` — оно генерируется как nullable (`Type?`).

Это правило одинаково работает для всех трёх стилей:
- `plain_dart`
- `json_serializable`
- `freezed`

