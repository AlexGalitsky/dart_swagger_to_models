import 'class_generator_strategy.dart';

/// Registry for custom generation styles.
/// 
/// Allows registering custom generation styles
/// that can be used instead of built-in styles.
class StyleRegistry {
  static final Map<String, ClassGeneratorStrategy Function()> _customStyles = {};

  /// Registers a custom generation style.
  /// 
  /// [styleName] - style name (e.g., 'equatable', 'my_custom_style').
  /// [factory] - function that creates a generation strategy instance.
  /// 
  /// Example:
  /// ```dart
  /// StyleRegistry.register('equatable', () => EquatableGenerator());
  /// ```
  static void register(String styleName, ClassGeneratorStrategy Function() factory) {
    if (styleName.isEmpty) {
      throw ArgumentError('Style name cannot be empty');
    }
    _customStyles[styleName.toLowerCase()] = factory;
  }

  /// Unregisters a custom style.
  static void unregister(String styleName) {
    _customStyles.remove(styleName.toLowerCase());
  }

  /// Checks if style is registered.
  static bool isRegistered(String styleName) {
    return _customStyles.containsKey(styleName.toLowerCase());
  }

  /// Creates strategy for custom style.
  /// 
  /// Throws [ArgumentError] if style is not registered.
  static ClassGeneratorStrategy createCustomStrategy(String styleName) {
    final factory = _customStyles[styleName.toLowerCase()];
    if (factory == null) {
      throw ArgumentError(
        'Custom style "$styleName" is not registered. '
        'Use StyleRegistry.register() to register the style.',
      );
    }
    return factory();
  }

  /// Gets list of all registered custom styles.
  static List<String> get registeredStyles => _customStyles.keys.toList();

  /// Clears all registered styles (mainly for tests).
  static void clear() {
    _customStyles.clear();
  }
}
