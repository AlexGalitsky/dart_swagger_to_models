import '../core/types.dart';
import 'class_generator_strategy.dart';
import 'freezed_generator.dart';
import 'json_serializable_generator.dart';
import 'plain_dart_generator.dart';

/// Фабрика для создания стратегий генерации.
class GeneratorFactory {
  /// Создаёт стратегию генерации на основе стиля.
  static ClassGeneratorStrategy createStrategy(GenerationStyle style) {
    if (style == GenerationStyle.plainDart) {
      return PlainDartGenerator();
    }
    if (style == GenerationStyle.jsonSerializable) {
      return JsonSerializableGenerator();
    }
    // По умолчанию — freezed.
    return FreezedGenerator();
  }
}
