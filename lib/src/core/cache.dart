import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

/// Cache for incremental generation.
///
/// Stores schema hashes to detect changes between generator runs.
class GenerationCache {
  final String cacheFilePath;
  Map<String, String> _schemaHashes = {};

  GenerationCache(this.cacheFilePath);

  /// Loads cache from a file.
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
        (data['schemaHashes'] as Map?)
                ?.map((k, v) => MapEntry(k.toString(), v.toString())) ??
            {},
      );
      return cache;
    } catch (e) {
      // If cache cannot be loaded, return an empty one
      return GenerationCache(cacheFile.path);
    }
  }

  /// Saves cache to a file.
  Future<void> save() async {
    final cacheFile = File(cacheFilePath);
    final data = {
      'schemaHashes': _schemaHashes,
    };
    await cacheFile.writeAsString(jsonEncode(data));
  }

  /// Computes a hash for a schema.
  static String computeSchemaHash(Map<String, dynamic> schema) {
    // Normalize schema: sort keys for stable hash
    final normalized = _normalizeSchema(schema);
    final jsonString = jsonEncode(normalized);
    final bytes = utf8.encode(jsonString);
    final hash = sha256.convert(bytes);
    return hash.toString();
  }

  /// Normalizes schema for stable hashing.
  static Map<String, dynamic> _normalizeSchema(Map<String, dynamic> schema) {
    final result = <String, dynamic>{};

    // Sort keys for stability
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

  /// Gets schema hash from the cache.
  String? getHash(String schemaName) {
    return _schemaHashes[schemaName];
  }

  /// Sets schema hash in the cache.
  void setHash(String schemaName, String hash) {
    _schemaHashes[schemaName] = hash;
  }

  /// Removes schema hash (for deleted schemas).
  void removeHash(String schemaName) {
    _schemaHashes.remove(schemaName);
  }

  /// Checks whether a schema has changed.
  bool hasChanged(String schemaName, Map<String, dynamic> schema) {
    final currentHash = computeSchemaHash(schema);
    final cachedHash = getHash(schemaName);
    return cachedHash == null || cachedHash != currentHash;
  }

  /// Returns a set of all cached schemas.
  Set<String> get cachedSchemas => _schemaHashes.keys.toSet();

  /// Clears the cache.
  void clear() {
    _schemaHashes.clear();
  }
}
