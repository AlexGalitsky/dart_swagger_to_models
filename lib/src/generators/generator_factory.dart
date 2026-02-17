import '../core/types.dart';
import 'class_generator_strategy.dart';
import 'freezed_generator.dart';
import 'json_serializable_generator.dart';
import 'plain_dart_generator.dart';
import 'style_registry.dart';

/// Factory for creating generation strategies.
class GeneratorFactory {
  /// Creates a generation strategy based on style.
  ///
  /// Supports both built-in styles (via GenerationStyle enum)
  /// and custom styles (via string style name).
  static ClassGeneratorStrategy createStrategy(GenerationStyle? style,
      {String? customStyleName}) {
    // If a custom style is specified, use it
    if (customStyleName != null && customStyleName.isNotEmpty) {
      return StyleRegistry.createCustomStrategy(customStyleName);
    }

    // Otherwise use built-in styles
    if (style == null) {
      return PlainDartGenerator(); // Default
    }

    if (style == GenerationStyle.plainDart) {
      return PlainDartGenerator();
    }
    if (style == GenerationStyle.jsonSerializable) {
      return JsonSerializableGenerator();
    }
    // Default fallback — freezed.
    return FreezedGenerator();
  }

  /// Creates generation strategy from a string style name.
  ///
  /// Supports both built-in styles ('plain_dart', 'json_serializable', 'freezed')
  /// and custom styles registered via StyleRegistry.
  static ClassGeneratorStrategy createStrategyFromString(String styleName) {
    // Try to parse as built-in style
    final style = _parseStyleName(styleName);
    if (style != null) {
      return createStrategy(style);
    }

    // If not built-in, try to find a custom style
    return StyleRegistry.createCustomStrategy(styleName);
  }

  /// Parses string style name into GenerationStyle enum.
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
