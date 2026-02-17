## Использование dart_swagger_to_models (RU)

Этот документ описывает типовые сценарии использования `dart_swagger_to_models`.

### Оглавление

1. [Базовая генерация](#1-базовая-генерация)
2. [Кастомная директория и стиль](#2-кастомная-директория-и-стиль)
3. [Использование стиля `freezed`](#3-использование-стиля-freezed)
4. [Перегенерация существующих файлов](#4-перегенерация-существующих-файлов)
5. [Конфигурационный файл](#5-конфигурационный-файл)
6. [Lint правила валидации спецификаций](#6-lint-правила-валидации-спецификаций)
7. [Правила null-safety](#7-правила-null-safety)
8. [Логирование и управление выводом](#8-логирование-и-управление-выводом)
9. [Схемы композиции OpenAPI (allOf, oneOf, anyOf)](#9-схемы-композиции-openapi-allof-oneof-anyof)
10. [Инкрементальная генерация](#10-инкрементальная-генерация)
11. [Кастомные стили генерации (подключаемые стили)](#11-кастомные-стили-генерации-подключаемые-стили)
12. [Интеграция с build_runner](#12-интеграция-с-build_runner)
13. [FAQ / Решение проблем](#13-faq--решение-проблем)


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

### 4. Перегенерация существующих файлов

Если модель уже интегрирована в проект и содержит маркер:

```dart
/*SWAGGER-TO-DART*/
```

можно перегенерировать файлы, запустив:

```bash
dart run dart_swagger_to_models:dart_swagger_to_models \
  --input api.yaml \
  --output-dir lib/models \
  --project-dir .
```

Все Dart-файлы, содержащие маркер `/*SWAGGER-TO-DART*/`, будут обновлены.

### 5. Конфигурационный файл

Вы можете создать файл `dart_swagger_to_models.yaml` в корне проекта для настройки генератора:

```yaml
# Глобальные опции
defaultStyle: json_serializable
outputDir: lib/generated
projectDir: .

# Переопределения для отдельных схем
schemas:
  User:
    className: CustomUser
    fieldNames:
      user_id: userId
      user_name: userName
    typeMapping:
      string: MyString
      integer: MyInt
```

**Приоритет**: аргументы CLI > конфигурационный файл > значения по умолчанию

**Опции конфигурации:**
- `defaultStyle`: стиль генерации по умолчанию (`plain_dart`, `json_serializable`, `freezed`)
- `outputDir`: директория для выходных файлов по умолчанию
- `projectDir`: корневая директория проекта по умолчанию
- `useJsonKey`: генерировать `@JsonKey(name: '...')` для полей, где JSON-ключ отличается от Dart имени поля (по умолчанию: `false`)
- `lint`: конфигурация lint правил для валидации спецификаций (см. ниже)
- `schemas`: переопределения для отдельных схем:
  - `className`: кастомное имя класса (переопределяет автоматически сгенерированное)
  - `fieldNames`: маппинг JSON ключей на Dart имена полей
  - `typeMapping`: маппинг типов схемы на Dart типы
  - `useJsonKey`: переопределить глобальную опцию `useJsonKey` для этой схемы

**Конфигурация lint правил:**

Вы можете настроить lint правила для валидации ваших Swagger/OpenAPI спецификаций:

```yaml
lint:
  enabled: true  # Включить/выключить все lint правила (по умолчанию: true)
  rules:
    missing_type: error          # Поле без типа и без $ref
    suspicious_id_field: warning # ID поле без required и nullable
    missing_ref_target: error    # Отсутствующая цель для $ref
    type_inconsistency: warning  # Несогласованность типов (например, integer с format)
    empty_object: warning        # Пустой объект (нет properties и additionalProperties)
    array_without_items: warning # Массив без items
    empty_enum: warning          # Enum без значений
```

Каждое правило может быть установлено в:
- `off` - правило отключено
- `warning` - правило выводит предупреждение
- `error` - правило выводит ошибку

**Пример с конфигурацией lint:**

```yaml
defaultStyle: json_serializable
lint:
  rules:
    missing_type: error
    suspicious_id_field: off
    missing_ref_target: error
schemas:
  User:
    className: CustomUser
```

**Пример с `useJsonKey`:**

Когда установлено `useJsonKey: true`, поля с snake_case JSON-ключами автоматически получат аннотации `@JsonKey`:

```yaml
# dart_swagger_to_models.yaml
useJsonKey: true
```

Для схемы с полями `user_id` и `user_name` генератор создаст:

```dart
@JsonSerializable()
class User {
  @JsonKey(name: 'user_id')
  final int userId;
  
  @JsonKey(name: 'user_name')
  final String userName;
  
  // ...
}
```

Это работает как для стиля `json_serializable`, так и для `freezed`.

**Пример с кастомным конфигурационным файлом:**

```bash
dart run dart_swagger_to_models:dart_swagger_to_models \
  --input api.yaml \
  --config custom_config.yaml
```

### 6. Правила null-safety

Генератор использует простое правило:
- Если поле присутствует в `properties` схемы — оно **required по умолчанию**.
- Если у поля есть `nullable: true` — оно генерируется как nullable (`Type?`).

Это правило одинаково работает для всех трёх стилей:
- `plain_dart`
- `json_serializable`
- `freezed`

### 7. Логирование и управление выводом

Генератор предоставляет гибкие опции логирования:

**Режим подробного вывода (`--verbose` / `-v`):**
- Показывает детальную отладочную информацию
- Отображает прогресс обработки каждой схемы
- Полезен для отладки и понимания процесса генерации

```bash
dart run dart_swagger_to_models:dart_swagger_to_models \
  --input api.yaml \
  --verbose
```

**Тихий режим (`--quiet` / `-q`):**
- Минимальный вывод (только ошибки и критичные сообщения)
- Полезен в CI/CD пайплайнах или скриптах

```bash
dart run dart_swagger_to_models:dart_swagger_to_models \
  --input api.yaml \
  --quiet
```

**Режим по умолчанию:**
- Показывает информационные сообщения, предупреждения и ошибки
- Отображает сводку после генерации

**Сводка генерации:**
После успешной генерации инструмент отображает сводку:
- Количество обработанных схем
- Количество обработанных enum'ов
- Количество созданных файлов
- Количество обновлённых файлов
- Всего файлов сгенерировано
- Выходная директория

**Сообщения об ошибках:**
Генератор предоставляет понятные сообщения об ошибках для:
- Отсутствующих целей для `$ref` (с контекстом о том, где использовалась ссылка)
- Неподдерживаемых или неоднозначных конструкций схем
- Предупреждений о подозрительных спецификациях (например, поля `id` без `nullable: true`, но и без `required`)

### 8. Схемы композиции OpenAPI (allOf, oneOf, anyOf)

Генератор поддерживает схемы композиции OpenAPI 3.0:

**`allOf` (множественное наследование):**
Генератор объединяет все свойства из всех элементов `allOf` в один класс:

```yaml
components:
  schemas:
    BaseEntity:
      type: object
      required: [id]
      properties:
        id:
          type: integer
        createdAt:
          type: string
          format: date-time
    
    User:
      allOf:
        - $ref: '#/components/schemas/BaseEntity'
        - type: object
          properties:
            name:
              type: string
            email:
              type: string
```

Сгенерированный класс `User` будет содержать все свойства из `BaseEntity` плюс свои собственные.

**Возможности:**
- Рекурсивная обработка вложенных комбинаций `allOf`
- Поддержка множественного наследования (несколько `$ref` в `allOf`)
- Обнаружение и предотвращение циклических зависимостей
- Подробное логирование обработки вложенных `allOf` (используйте `--verbose`)

**`oneOf` / `anyOf` (объединённые типы):**
Для схем `oneOf` и `anyOf` генератор создаёт безопасную обёртку с `dynamic` значением:

```yaml
components:
  schemas:
    StringValue:
      type: object
      properties:
        value:
          type: string
    
    NumberValue:
      type: object
      properties:
        value:
          type: number
    
    Value:
      oneOf:
        - $ref: '#/components/schemas/StringValue'
        - $ref: '#/components/schemas/NumberValue'
```

Сгенерированный класс `Value` будет:

```dart
/// Класс для oneOf схемы "Value".
///
/// Внимание: Для oneOf схем генерируется обёртка с dynamic значением.
/// В будущих версиях будет поддержка генерации union-типов.
/// Возможные типы: StringValue, NumberValue.
class Value {
  /// Значение (может быть одним из возможных типов).
  final dynamic value;

  const Value(this.value);

  /// Создаёт экземпляр из JSON.
  ///
  /// Внимание: Для oneOf схем требуется ручная валидация типа.
  factory Value.fromJson(dynamic json) {
    if (json == null) {
      throw ArgumentError('JSON не может быть null для Value');
    }
    return Value(json);
  }

  /// Преобразует в JSON.
  dynamic toJson() => value;

  @override
  String toString() => 'Value(value: $value)';
}
```

**Возможности:**
- Безопасные обёртки с `dynamic` и понятными сообщениями об ошибках
- Обнаружение и логирование использования `discriminator` (архитектура подготовлена для будущей генерации union-типов)
- Подробное логирование о возможных типах в схемах `oneOf`/`anyOf` (используйте `--verbose`)
- Понятные комментарии в документации, объясняющие ограничения

**Примечание:** Полная генерация union-типов (особенно с `discriminator`) запланирована на будущие версии. В настоящее время схемы `oneOf`/`anyOf` генерируют безопасные обёртки, требующие ручной валидации типов.

### 9. Инкрементальная генерация

Генератор поддерживает инкрементальную генерацию для улучшения производительности при работе с большими спецификациями:

**Флаг `--changed-only`:**
При включении генератор перегенерирует только те схемы, которые изменились с момента последнего запуска:

```bash
dart run dart_swagger_to_models:dart_swagger_to_models \
  --input api.yaml \
  --changed-only
```

**Как это работает:**
- Генератор кэширует хеши схем в файле `.dart_swagger_to_models.cache` в корне проекта
- При каждом запуске сравнивает текущие хеши схем с закэшированными
- Обрабатываются только изменённые, новые или удалённые схемы
- Автоматически удаляет файлы для удалённых схем

**Преимущества:**
- Значительно быстрее генерация для больших спецификаций
- Перегенерирует только то, что действительно изменилось
- Уменьшает количество ненужных записей в файлы

**Пример использования:**

```bash
# Первый запуск - генерирует все схемы и создаёт кэш
dart run dart_swagger_to_models:dart_swagger_to_models \
  --input api.yaml \
  --output-dir lib/models \
  --changed-only

# Изменяем только одну схему в api.yaml

# Второй запуск - перегенерирует только изменённую схему
dart run dart_swagger_to_models:dart_swagger_to_models \
  --input api.yaml \
  --output-dir lib/models \
  --changed-only
```

**Файл кэша:**
- Расположение: `.dart_swagger_to_models.cache` в корне проекта (указывается через `--project-dir`)
- Формат: JSON файл, содержащий хеши схем
- Автоматическое управление: Создаётся, обновляется и поддерживается автоматически
- Безопасно для коммита: Файл кэша можно коммитить в систему контроля версий, но обычно его добавляют в `.gitignore`

**Примечание:** Если вы хотите принудительно выполнить полную регенерацию, просто опустите флаг `--changed-only` или удалите файл кэша.

### 10. Кастомные стили генерации (подключаемые стили)

Генератор поддерживает кастомные стили генерации, которые вы можете создать и зарегистрировать:

**Создание кастомного стиля:**

1. Создайте класс, который расширяет `ClassGeneratorStrategy`
2. Зарегистрируйте его с помощью `StyleRegistry.register()`
3. Используйте через конфигурационный файл или CLI

**Пример:**

```dart
import 'package:dart_swagger_to_models/dart_swagger_to_models.dart';

class MyCustomGenerator extends ClassGeneratorStrategy {
  // Реализуйте необходимые методы...
}

// Регистрируем стиль
StyleRegistry.register('my_style', () => MyCustomGenerator());
```

**Использование кастомного стиля:**

Через конфигурационный файл (`dart_swagger_to_models.yaml`):
```yaml
defaultStyle: my_style
```

Через CLI:
```bash
dart run dart_swagger_to_models:dart_swagger_to_models \
  --input api.yaml \
  --style my_style
```

**Важно:** Кастомные стили должны быть зарегистрированы в вашем Dart коде перед запуском генератора. Обычно это делается в build-скрипте или файле инициализации.

**Полное руководство:** См. `docs/ru/CUSTOM_STYLES.md` для подробного пошагового руководства по созданию кастомных стилей, включая полный пример Equatable.

### 11. Интеграция с build_runner

Генератор может быть интегрирован с `build_runner` для автоматической генерации моделей как части пайплайна сборки.

#### Настройка

**Важно:** Builder не экспортируется из основной библиотеки, чтобы избежать загрузки `dart:mirrors` (который не поддерживается в Flutter). Импортируйте его напрямую при необходимости.

1. **Добавьте зависимости** в ваш `pubspec.yaml`:

```yaml
dependencies:
  dart_swagger_to_models: ^0.1.0
  json_annotation: ^4.9.0  # Если используете стиль json_serializable

dev_dependencies:
  build_runner: ^2.4.0
  json_serializable: ^6.8.0  # Если используете стиль json_serializable
```

2. **Создайте `build.yaml`** в корне проекта:

```yaml
targets:
  $default:
    builders:
      # Builder находится в src/build/swagger_builder.dart
      # build_runner найдёт его автоматически используя dart:mirrors
      dart_swagger_to_models|swaggerBuilder:
        enabled: true
        generate_for:
          - swagger/**
          - openapi/**
          - api/**
```

**Примечание:** Builder не экспортируется из основной библиотеки, чтобы избежать загрузки `dart:mirrors` при обычном использовании. `build_runner` найдёт его автоматически используя reflection.

3. **Поместите ваши спецификации OpenAPI/Swagger** в одну из этих директорий:
   - `swagger/`
   - `openapi/`
   - `api/`

4. **Создайте файл конфигурации `dart_swagger_to_models.yaml`** (опционально):

```yaml
defaultStyle: json_serializable
outputDir: lib/generated/models
useJsonKey: true
```

#### Использование

Запустите build_runner для генерации моделей:

```bash
# Для Dart проектов
dart run build_runner build

# Для Flutter проектов
flutter pub run build_runner build
```

Генератор будет:
- Искать все файлы спецификаций OpenAPI/Swagger в настроенных директориях
- Генерировать Dart-модели согласно вашей конфигурации
- Размещать сгенерированные файлы в указанной выходной директории

#### Сгенерированные файлы

Модели генерируются в директории, указанной в `outputDir` в вашей конфигурации (по умолчанию: `lib/generated/models`). Каждая схема становится отдельным Dart-файлом.

#### Примеры

Полные примеры доступны в:
- `example/dart_example/` - Проект на чистом Dart с build_runner
- `example/flutter_example/` - Flutter проект с интеграцией HTTP-клиента

#### Преимущества

- **Автоматическая генерация**: Модели автоматически регенерируются при изменении спецификаций
- **Интеграция со сборкой**: Работает бесшовно с другими генераторами кода (например, `json_serializable`)
- **Инкрементальные сборки**: Регенерирует только изменённые модели (при использовании флага `--changed-only` через CLI)
- **Поддержка IDE**: Сгенерированные файлы являются частью структуры проекта

#### Ограничения

- Builder обрабатывает файлы индивидуально, поэтому каждая спецификация генерирует модели отдельно
- Для нескольких спецификаций рассмотрите их объединение или использование отдельных выходных директорий
- Кастомные стили должны быть зарегистрированы до запуска build_runner (обычно в build-скрипте)
