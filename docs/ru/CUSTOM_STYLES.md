# Как создать собственный стиль генерации

Это руководство объясняет, как создать и зарегистрировать кастомные стили генерации для `dart_swagger_to_models`.

## Обзор

Генератор использует паттерн Strategy для генерации кода. Каждый стиль (например, `plain_dart`, `json_serializable`, `freezed`) реализован как `ClassGeneratorStrategy`. Вы можете создать свою собственную стратегию и зарегистрировать её для использования с генератором.

## Шаг 1: Создайте класс стратегии

Создайте класс, который расширяет `ClassGeneratorStrategy`:

```dart
import 'package:dart_swagger_to_models/dart_swagger_to_models.dart';

class MyCustomGenerator extends ClassGeneratorStrategy {
  @override
  List<String> generateImportsAndParts(String fileName) {
    // Возвращаем импорты и part директивы, необходимые для этого стиля
    return [
      "import 'package:my_package/my_package.dart';",
    ];
  }

  @override
  List<String> generateClassAnnotations(String className) {
    // Возвращаем аннотации уровня класса (например, @JsonSerializable(), @freezed)
    return [];
  }

  @override
  String generateFullClass(
    String className,
    Map<String, FieldInfo> fields,
    String Function(String jsonKey, Map<String, dynamic> schema) fromJsonExpression,
    String Function(String fieldName, Map<String, dynamic> schema) toJsonExpression, {
    bool useJsonKey = false,
  }) {
    // Генерируем полный код класса
    final buffer = StringBuffer()
      ..writeln('class $className {');
    
    // Добавляем поля
    fields.forEach((propName, field) {
      buffer.writeln('  final ${field.dartType} ${field.camelCaseName};');
    });
    
    // Добавляем конструктор, fromJson, toJson и т.д.
    // ...
    
    buffer.writeln('}');
    return buffer.toString();
  }
}
```

## Шаг 2: Зарегистрируйте ваш стиль

Зарегистрируйте ваш кастомный стиль с помощью `StyleRegistry`:

```dart
import 'package:dart_swagger_to_models/dart_swagger_to_models.dart';

void main() {
  // Регистрируем ваш кастомный стиль
  StyleRegistry.register('my_custom_style', () => MyCustomGenerator());
  
  // Теперь вы можете использовать 'my_custom_style' в конфиге или CLI
}
```

## Шаг 3: Используйте ваш кастомный стиль

### Вариант 1: Через конфигурационный файл

Создайте файл `dart_swagger_to_models.yaml`:

```yaml
defaultStyle: my_custom_style
```

### Вариант 2: Через CLI

```bash
dart run dart_swagger_to_models:dart_swagger_to_models \
  --input api.yaml \
  --style my_custom_style
```

**Примечание:** Вам нужно зарегистрировать стиль в вашем Dart коде перед запуском генератора. Обычно это делается в build-скрипте или файле инициализации.

## Пример: Стиль Equatable

Вот полный пример, который добавляет поддержку `Equatable`:

```dart
import 'package:dart_swagger_to_models/dart_swagger_to_models.dart';
import 'package:equatable/equatable.dart';

class EquatableGenerator extends ClassGeneratorStrategy {
  @override
  List<String> generateImportsAndParts(String fileName) {
    return [
      "import 'package:equatable/equatable.dart';",
    ];
  }

  @override
  List<String> generateClassAnnotations(String className) {
    return [];
  }

  @override
  String generateFullClass(
    String className,
    Map<String, FieldInfo> fields,
    String Function(String jsonKey, Map<String, dynamic> schema) fromJsonExpression,
    String Function(String fieldName, Map<String, dynamic> schema) toJsonExpression, {
    bool useJsonKey = false,
  }) {
    final buffer = StringBuffer()
      ..writeln('class $className extends Equatable {');

    // Поля
    fields.forEach((propName, field) {
      buffer.writeln('  final ${field.dartType} ${field.camelCaseName};');
    });

    buffer.writeln();

    // Конструктор
    buffer.writeln('  const $className({');
    fields.forEach((propName, field) {
      final prefix = field.isRequired ? 'required ' : '';
      buffer.writeln('    $prefix this.${field.camelCaseName},');
    });
    buffer.writeln('  });');
    buffer.writeln();

    // fromJson
    buffer.writeln('  factory $className.fromJson(Map<String, dynamic> json) {');
    buffer.writeln('    return $className(');
    fields.forEach((propName, field) {
      final jsonKey = propName;
      final assign = fromJsonExpression(jsonKey, field.schema);
      buffer.writeln('      ${field.camelCaseName}: $assign,');
    });
    buffer.writeln('    );');
    buffer.writeln('  }');
    buffer.writeln();

    // toJson
    buffer.writeln('  Map<String, dynamic> toJson() {');
    buffer.writeln('    return <String, dynamic>{');
    fields.forEach((propName, field) {
      final jsonKey = propName;
      final assign = toJsonExpression(field.camelCaseName, field.schema);
      buffer.writeln('      \'$jsonKey\': $assign,');
    });
    buffer.writeln('    };');
    buffer.writeln('  }');
    buffer.writeln();

    // Equatable props
    buffer.writeln('  @override');
    buffer.writeln('  List<Object?> get props => [');
    fields.forEach((propName, field) {
      buffer.writeln('    ${field.camelCaseName},');
    });
    buffer.writeln('  ];');

    buffer.writeln('}');
    return buffer.toString();
  }
}

// Регистрируем стиль
void registerEquatableStyle() {
  StyleRegistry.register('equatable', () => EquatableGenerator());
}
```

## API FieldInfo

Класс `FieldInfo` предоставляет полезную информацию о каждом поле:

- `name` - Имя поля в Dart (может быть переименовано через конфиг)
- `jsonKey` - Оригинальный JSON ключ из схемы
- `dartType` - Dart тип (например, `int`, `String?`, `List<String>`)
- `isRequired` - Является ли поле обязательным (non-nullable)
- `schema` - Оригинальное определение схемы
- `camelCaseName` - Версия имени поля в camelCase
- `needsJsonKey(bool useJsonKeyEnabled)` - Нужно ли генерировать аннотацию `@JsonKey`

## Рекомендации

1. **Переиспользуйте существующую логику**: Посмотрите на `PlainDartGenerator`, `JsonSerializableGenerator` или `FreezedGenerator` для референсных реализаций.

2. **Обрабатывайте nullable типы**: Используйте `field.isRequired` для определения, должно ли поле быть nullable.

3. **Поддерживайте `useJsonKey`**: Когда `useJsonKey` включен и `field.needsJsonKey(true)` возвращает true, генерируйте аннотации `@JsonKey(name: '...')`.

4. **Генерируйте правильные импорты**: Включайте все необходимые импорты в `generateImportsAndParts`.

5. **Тестируйте ваш стиль**: Создавайте тесты, чтобы убедиться, что ваш кастомный стиль генерирует правильный код.

## Ограничения

- Кастомные стили регистрируются во время выполнения, поэтому они должны быть зарегистрированы до запуска генератора.
- Кастомные стили лучше всего работают при использовании программно (через Dart API), а не через CLI, если только вы не создадите обёрточный скрипт.

## См. также

- `example/custom_style_equatable.dart` - Полный пример генератора стиля Equatable
- `lib/src/generators/` - Референсные реализации встроенных стилей
