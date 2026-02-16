import '../../dart_swagger_to_models.dart' show GenerationStyle;
import 'class_generator_strategy.dart';
import 'freezed_generator.dart';
import 'json_serializable_generator.dart';
import 'plain_dart_generator.dart';

/// Фабрика для создания стратегий генерации.
class GeneratorFactory {
  /// Создаёт стратегию генерации на основе стиля.
  static ClassGeneratorStrategy createStrategy(GenerationStyle style) {
    switch (style) {
      case GenerationStyle.plainDart:
        return PlainDartGenerator();
      case GenerationStyle.jsonSerializable:
        return JsonSerializableGenerator();
      case GenerationStyle.freezed:
        return FreezedGenerator();
    }
  }
}
