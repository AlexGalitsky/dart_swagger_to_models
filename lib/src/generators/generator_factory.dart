import '../core/types.dart';
import 'class_generator_strategy.dart';
import 'freezed_generator.dart';
import 'json_serializable_generator.dart';
import 'plain_dart_generator.dart';
import 'style_registry.dart';

/// Фабрика для создания стратегий генерации.
class GeneratorFactory {
  /// Создаёт стратегию генерации на основе стиля.
  ///
  /// Поддерживает как встроенные стили (через enum GenerationStyle),
  /// так и кастомные стили (через строковое имя).
  static ClassGeneratorStrategy createStrategy(GenerationStyle? style,
      {String? customStyleName}) {
    // Если указан кастомный стиль, используем его
    if (customStyleName != null && customStyleName.isNotEmpty) {
      return StyleRegistry.createCustomStrategy(customStyleName);
    }

    // Иначе используем встроенные стили
    if (style == null) {
      return PlainDartGenerator(); // По умолчанию
    }

    if (style == GenerationStyle.plainDart) {
      return PlainDartGenerator();
    }
    if (style == GenerationStyle.jsonSerializable) {
      return JsonSerializableGenerator();
    }
    // По умолчанию — freezed.
    return FreezedGenerator();
  }

  /// Создаёт стратегию генерации из строкового имени стиля.
  ///
  /// Поддерживает как встроенные стили ('plain_dart', 'json_serializable', 'freezed'),
  /// так и кастомные стили, зарегистрированные через StyleRegistry.
  static ClassGeneratorStrategy createStrategyFromString(String styleName) {
    // Пытаемся распарсить как встроенный стиль
    final style = _parseStyleName(styleName);
    if (style != null) {
      return createStrategy(style);
    }

    // Если не встроенный стиль, пытаемся найти кастомный
    return StyleRegistry.createCustomStrategy(styleName);
  }

  /// Парсит строковое имя стиля в enum GenerationStyle.
  static GenerationStyle? _parseStyleName(String styleName) {
    switch (styleName.toLowerCase()) {
      case 'plain_dart':
        return GenerationStyle.plainDart;
      case 'json_serializable':
        return GenerationStyle.jsonSerializable;
      case 'freezed':
        return GenerationStyle.freezed;
      default:
        return null;
    }
  }
}
