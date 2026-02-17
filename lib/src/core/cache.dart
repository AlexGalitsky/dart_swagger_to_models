import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

/// Кэш для инкрементальной генерации.
/// 
/// Хранит хеши схем для определения изменений между запусками генератора.
class GenerationCache {
  final String cacheFilePath;
  Map<String, String> _schemaHashes = {};

  GenerationCache(this.cacheFilePath);

  /// Загружает кэш из файла.
  static Future<GenerationCache?> load(String projectDir) async {
    final cacheFile = File(p.join(projectDir, '.dart_swagger_to_models.cache'));
    
    if (!await cacheFile.exists()) {
      return GenerationCache(cacheFile.path);
    }

    try {
      final content = await cacheFile.readAsString();
      final data = jsonDecode(content) as Map<String, dynamic>;
      final cache = GenerationCache(cacheFile.path);
      cache._schemaHashes = Map<String, String>.from(
        (data['schemaHashes'] as Map?)?.map((k, v) => MapEntry(k.toString(), v.toString())) ?? {},
      );
      return cache;
    } catch (e) {
      // Если не удалось загрузить кэш, возвращаем пустой
      return GenerationCache(cacheFile.path);
    }
  }

  /// Сохраняет кэш в файл.
  Future<void> save() async {
    final cacheFile = File(cacheFilePath);
    final data = {
      'schemaHashes': _schemaHashes,
    };
    await cacheFile.writeAsString(jsonEncode(data));
  }

  /// Вычисляет хеш схемы.
  static String computeSchemaHash(Map<String, dynamic> schema) {
    // Нормализуем схему: сортируем ключи для стабильности хеша
    final normalized = _normalizeSchema(schema);
    final jsonString = jsonEncode(normalized);
    final bytes = utf8.encode(jsonString);
    final hash = sha256.convert(bytes);
    return hash.toString();
  }

  /// Нормализует схему для стабильного хеширования.
  static Map<String, dynamic> _normalizeSchema(Map<String, dynamic> schema) {
    final result = <String, dynamic>{};
    
    // Сортируем ключи для стабильности
    final sortedKeys = schema.keys.toList()..sort();
    
    for (final key in sortedKeys) {
      final value = schema[key];
      
      if (value is Map<String, dynamic>) {
        result[key] = _normalizeSchema(value);
      } else if (value is List) {
        result[key] = value.map((item) {
          if (item is Map<String, dynamic>) {
            return _normalizeSchema(item);
          }
          return item;
        }).toList();
      } else {
        result[key] = value;
      }
    }
    
    return result;
  }

  /// Получает хеш схемы из кэша.
  String? getHash(String schemaName) {
    return _schemaHashes[schemaName];
  }

  /// Устанавливает хеш схемы.
  void setHash(String schemaName, String hash) {
    _schemaHashes[schemaName] = hash;
  }

  /// Удаляет хеш схемы (для удалённых схем).
  void removeHash(String schemaName) {
    _schemaHashes.remove(schemaName);
  }

  /// Проверяет, изменилась ли схема.
  bool hasChanged(String schemaName, Map<String, dynamic> schema) {
    final currentHash = computeSchemaHash(schema);
    final cachedHash = getHash(schemaName);
    return cachedHash == null || cachedHash != currentHash;
  }

  /// Получает список всех закэшированных схем.
  Set<String> get cachedSchemas => _schemaHashes.keys.toSet();

  /// Очищает кэш.
  void clear() {
    _schemaHashes.clear();
  }
}
