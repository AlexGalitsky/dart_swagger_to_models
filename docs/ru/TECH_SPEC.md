# Техническое задание: Swagger to Dart CLI пакет

## 1. Общее описание
Разработать Dart CLI пакет `swagger_to_dart`, который автоматически генерирует Dart модели на основе Swagger/OpenAPI спецификации. Пакет должен интегрироваться с существующим кодом проекта через специальные маркеры-комментарии и поддерживать различные стили генерации моделей.

## 2. Основные функции

### 2.1 Парсинг Swagger документации
- Принимать URL или локальный путь к Swagger/OpenAPI спецификации (JSON/YAML)
- Поддерживать Swagger 2.0 и OpenAPI 3.x
- Извлекать схемы данных (components/schemas или definitions)
- Парсить структуру объектов, типы полей, обязательные поля, описания
- Поддерживать вложенные объекты, массивы, enum, oneOf/anyOf
- Извлекать примеры значений для потенциальной генерации тестовых данных

### 2.2 Интеграция с существующим кодом
- Сканировать директории проекта для поиска Dart файлов
- Искать маркер `/*SWAGGER-TO-DART:{endpoint_address}*/` в начале файла для идентификации моделей, относящихся к конкретному endpoint'у
- Если файл модели не найден - создавать новый файл с соответствующим маркером
- В существующих моделях искать блоки между маркерами:
  - `/*SWAGGER-TO-DART: Fields start*/`
  - `/*SWAGGER-TO-DART: Fields stop*/`
- Генерировать поля модели строго внутри этих маркеров, сохраняя остальное содержимое файла (импорты, доп. методы, кастомную логику)

### 2.3 Режимы генерации моделей
Поддержка трех режимов через параметр командной строки `--style`:
- **`json_serializable`** - генерация с аннотациями `@JsonSerializable`, методами `fromJson`/`toJson`
- **`freezed`** - генерация с использованием пакета freezed для иммутабельных классов
- **`plain_dart`** - простые Dart классы с ручной реализацией fromJson/toJson

### 2.4 Структура генерируемого кода

#### Пример для json_serializable:
```dart
/*SWAGGER-TO-DART: /api/users*/
import 'package:json_annotation/json_annotation.dart';

part 'user_model.g.dart';

@JsonSerializable()
class User {
  /*SWAGGER-TO-DART: Fields start*/
  final int id;
  final String name;
  @JsonKey(name: 'created_at')
  final DateTime createdAt;
  /*SWAGGER-TO-DART: Fields stop*/
  
  User({required this.id, required this.name, required this.createdAt});
  
  factory User.fromJson(Map<String, dynamic> json) => _$UserFromJson(json);
  Map<String, dynamic> toJson() => _$UserToJson(this);
}
```

#### Пример для freezed:
```dart
/*SWAGGER-TO-DART: /api/users*/
import 'package:freezed_annotation/freezed_annotation.dart';

part 'user_model.freezed.dart';
part 'user_model.g.dart';

@freezed
class User with _$User {
  factory User({
    /*SWAGGER-TO-DART: Fields start*/
    required int id,
    required String name,
    @JsonKey(name: 'created_at') required DateTime createdAt,
    /*SWAGGER-TO-DART: Fields stop*/
  }) = _User;
  
  factory User.fromJson(Map<String, dynamic> json) => _$UserFromJson(json);
}
```

### 2.5 Параметры командной строки

```bash
swagger_to_dart [options]

Обязательные параметры:
  --source, -s        URL или путь к Swagger файлу

Опциональные параметры:
  --style, -t         Стиль генерации: json_serializable/freezed/plain_dart (по умолчанию: json_serializable)
  --endpoint, -e      Конкретный endpoint для генерации (генерировать только модели для указанного endpoint'а)
  --model, -m         Конкретный файл модели для обновления (путь к файлу)
  --output, -o        Директория для выходных файлов (по умолчанию: lib/models)
  --recursive, -r     Рекурсивный поиск моделей в поддиректориях
  --dry-run           Показать что будет сгенерировано без записи файлов
  --verbose, -v       Подробный вывод процесса
  --config, -c        Путь к конфигурационному файлу (YAML)
```

## 3. Дополнительные идеи для реализации

### 3.1 Конфигурационный файл
Поддержка YAML конфигурации для постоянных настроек:
```yaml
source: "https://api.example.com/swagger.json"
style: "freezed"
output: "lib/data/models"
endpoints:
  - "/api/users"
  - "/api/posts"
ignore_patterns:
  - "**/*.g.dart"
  - "**/*.freezed.dart"
custom_mappings:
  date: "DateTime"
  email: "String"
generate_examples: true
```

### 3.2 Смарт-обновление моделей
- При обновлении существующей модели сохранять порядок полей, заданный пользователем
- Не перезаписывать кастомные JsonKey аннотации, добавленные вручную
- Выводить предупреждения о несоответствии типов при обновлении

### 3.3 Генерация тестовых данных
- Создавать отдельные файлы с тестовыми фабриками (test/models/factories/)
- Использовать примеры из Swagger для генерации реалистичных тестовых данных
- Генерация валидных/невалидных вариантов для тестирования

### 3.4 Валидация схем
- Генерация кода валидации на основе Swagger ограничений (min/max, pattern, format)
- Интеграция с пакетами для валидации (dart_validators, reactive_forms)

### 3.5 Документация в коде
- Добавление DartDoc комментариев из описаний полей Swagger
- Сохранение примеров из Swagger как комментариев к полям

### 3.6 Интерактивный режим
- Возможность выборочной генерации через CLI меню
- Подтверждение перезаписи существующих файлов с показом diff

### 3.7 Плагины и расширения
- Архитектура для подключения пользовательских трансформаций
- Поддержка генерации для популярных state management решений (Riverpod, BLoC)

### 3.8 Мониторинг изменений
- Watch режим для автоматической регенерации при изменении Swagger файла
- Генерация отчета об изменениях между версиями моделей

## 4. Технические требования

### 4.1 Стек технологий
- Dart 3.0+
- Пакеты: `args`, `http`, `yaml`, `json_annotation`, `freezed_annotation`, `source_gen`
- Для парсинга OpenAPI: использование `openapi_spec` или собственная реализация

### 4.2 Архитектура
- Модульная структура с разделением на парсер, генератор кода, обработчик файлов
- Использование паттернов Visitor/Strategy для разных стилей генерации
- Кэширование результатов парсинга для ускорения повторных запусков

### 4.3 Тестирование
- Юнит-тесты для каждого модуля
- Интеграционные тесты с реальными Swagger файлами
- Тестирование на различных версиях OpenAPI спецификаций

### 4.4 Документация
- README с примерами использования
- Документация API для использования как библиотеки
- Примеры конфигурационных файлов

## 5. Примеры использования

### Базовое использование:
```bash
swagger_to_dart --source https://petstore.swagger.io/v2/swagger.json
```

### Генерация для конкретного endpoint'а в freezed стиле:
```bash
swagger_to_dart --source ./openapi.yaml --style freezed --endpoint /users
```

### Обновление конкретного файла модели:
```bash
swagger_to_dart --source https://api.example.com/swagger.json --model lib/models/user_model.dart
```

### Использование с конфигурационным файлом:
```bash
swagger_to_dart --config swagger_to_dart.yaml
```

## 6. Критерии готовности
- [ ] Парсинг Swagger 2.0 и OpenAPI 3.x спецификаций
- [ ] Генерация моделей во всех трех стилях
- [ ] Корректная работа с маркерами в существующих файлах
- [ ] Обработка всех основных типов данных и структур
- [ ] Покрытие тестами >80%
- [ ] Документация и примеры использования
- [ ] Публикация в pub.dev