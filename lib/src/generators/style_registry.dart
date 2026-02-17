import 'class_generator_strategy.dart';

/// Реестр кастомных стилей генерации.
/// 
/// Позволяет регистрировать пользовательские стили генерации,
/// которые могут быть использованы вместо встроенных стилей.
class StyleRegistry {
  static final Map<String, ClassGeneratorStrategy Function()> _customStyles = {};

  /// Регистрирует кастомный стиль генерации.
  /// 
  /// [styleName] - имя стиля (например, 'equatable', 'my_custom_style').
  /// [factory] - функция, создающая экземпляр стратегии генерации.
  /// 
  /// Пример:
  /// ```dart
  /// StyleRegistry.register('equatable', () => EquatableGenerator());
  /// ```
  static void register(String styleName, ClassGeneratorStrategy Function() factory) {
    if (styleName.isEmpty) {
      throw ArgumentError('Имя стиля не может быть пустым');
    }
    _customStyles[styleName.toLowerCase()] = factory;
  }

  /// Отменяет регистрацию кастомного стиля.
  static void unregister(String styleName) {
    _customStyles.remove(styleName.toLowerCase());
  }

  /// Проверяет, зарегистрирован ли стиль.
  static bool isRegistered(String styleName) {
    return _customStyles.containsKey(styleName.toLowerCase());
  }

  /// Создаёт стратегию для кастомного стиля.
  /// 
  /// Выбрасывает [ArgumentError], если стиль не зарегистрирован.
  static ClassGeneratorStrategy createCustomStrategy(String styleName) {
    final factory = _customStyles[styleName.toLowerCase()];
    if (factory == null) {
      throw ArgumentError(
        'Кастомный стиль "$styleName" не зарегистрирован. '
        'Используйте StyleRegistry.register() для регистрации стиля.',
      );
    }
    return factory();
  }

  /// Получает список всех зарегистрированных кастомных стилей.
  static List<String> get registeredStyles => _customStyles.keys.toList();

  /// Очищает все зарегистрированные стили (в основном для тестов).
  static void clear() {
    _customStyles.clear();
  }
}
