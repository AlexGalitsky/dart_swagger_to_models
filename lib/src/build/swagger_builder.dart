import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:build/build.dart';
import 'package:dart_swagger_to_models/dart_swagger_to_models.dart';
import 'package:dart_swagger_to_models/src/config/config_loader.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// Builder для генерации Dart-моделей из Swagger/OpenAPI спецификаций.
/// 
/// Этот Builder обрабатывает файлы спецификаций (`.yaml`, `.yml`, `.json`)
/// и генерирует Dart-модели в указанной выходной директории.
/// 
/// Конфигурация читается из `dart_swagger_to_models.yaml` в корне проекта.
/// 
/// Использование:
/// 1. Создайте файл `build.yaml` в корне проекта:
/// ```yaml
/// targets:
///   $default:
///     builders:
///       dart_swagger_to_models|swaggerBuilder:
///         enabled: true
/// ```
/// 2. Поместите файлы спецификаций в `swagger/` или `openapi/` директорию
/// 3. Запустите `dart run build_runner build`
class SwaggerBuilder implements Builder {
  /// Имя конфигурационного файла.
  static const String configFileName = 'dart_swagger_to_models.yaml';

  @override
  Map<String, List<String>> get buildExtensions => {
        // Обрабатываем файлы спецификаций и генерируем Dart-файлы
        '.yaml': ['.dart'],
        '.yml': ['.dart'],
        '.json': ['.dart'],
      };

  @override
  FutureOr<void> build(BuildStep buildStep) async {
    final inputId = buildStep.inputId;
    
    // Пропускаем файлы, которые не являются спецификациями OpenAPI/Swagger
    if (!_isSpecFile(inputId.path)) {
      return;
    }

    // Читаем спецификацию
    final specContent = await buildStep.readAsString(inputId);
    Map<String, dynamic> spec;
    try {
      if (inputId.path.endsWith('.json')) {
        spec = jsonDecode(specContent) as Map<String, dynamic>;
      } else {
        // Для YAML используем yaml пакет
        final yaml = loadYaml(specContent) as Map;
        spec = Map<String, dynamic>.from(yaml.map((k, v) => MapEntry(k.toString(), v)));
      }
    } catch (e) {
      log.warning('Не удалось распарсить спецификацию ${inputId.path}: $e');
      return;
    }

    // Проверяем, что это действительно Swagger/OpenAPI спецификация
    if (!_isSwaggerOrOpenApiSpec(spec)) {
      return; // Пропускаем файлы, которые не являются спецификациями
    }

    // Находим корень проекта
    final projectRoot = await _findProjectRoot(buildStep);
    
    // Читаем конфигурацию
    final configPath = p.join(projectRoot, configFileName);
    Config? config;
    try {
      config = await ConfigLoader.loadConfig(configPath, projectRoot);
    } catch (e) {
      // Конфигурация не обязательна
      log.fine('Конфигурация не найдена: $e');
    }

    // Определяем выходную директорию
    final outputDir = config?.outputDir ?? 'lib/generated/models';
    final effectiveOutputDir = p.isAbsolute(outputDir)
        ? outputDir
        : p.join(projectRoot, outputDir);

    // Создаём временный файл для спецификации (build_runner работает с AssetId)
    final tempSpecFile = File(p.join(Directory.systemTemp.path, '${inputId.path.replaceAll('/', '_')}'));
    try {
      await tempSpecFile.writeAsString(specContent);
      
      // Генерируем модели
      final result = await SwaggerToDartGenerator.generateModels(
        input: tempSpecFile.path,
        outputDir: effectiveOutputDir,
        projectDir: projectRoot,
        config: config,
      );

      // Записываем сгенерированные файлы как выходные assets
      for (final generatedFile in result.generatedFiles) {
        final file = File(generatedFile);
        if (await file.exists()) {
          final content = await file.readAsString();
          // Определяем AssetId для выходного файла
          final relativePath = p.relative(generatedFile, from: projectRoot);
          final outputAssetId = AssetId(
            inputId.package,
            relativePath.replaceAll('\\', '/'),
          );
          await buildStep.writeAsString(outputAssetId, content);
        }
      }

      log.info(
        'Сгенерировано ${result.generatedFiles.length} файлов из ${inputId.path}',
      );
    } catch (e, st) {
      log.severe('Ошибка генерации моделей из ${inputId.path}: $e');
      log.fine(st.toString());
    } finally {
      // Удаляем временный файл
      if (await tempSpecFile.exists()) {
        await tempSpecFile.delete();
      }
    }
  }

  /// Проверяет, является ли файл спецификацией OpenAPI/Swagger.
  bool _isSpecFile(String path) {
    final lowerPath = path.toLowerCase();
    return (lowerPath.contains('swagger') || 
            lowerPath.contains('openapi') ||
            lowerPath.contains('api')) &&
           (path.endsWith('.yaml') || path.endsWith('.yml') || path.endsWith('.json'));
  }

  /// Проверяет, является ли содержимое спецификацией Swagger/OpenAPI.
  bool _isSwaggerOrOpenApiSpec(Map<String, dynamic> spec) {
    return spec.containsKey('swagger') || 
           spec.containsKey('openapi') ||
           (spec.containsKey('info') && (spec.containsKey('paths') || spec.containsKey('definitions') || spec.containsKey('components')));
  }

  /// Находит корневую директорию проекта.
  Future<String> _findProjectRoot(BuildStep buildStep) async {
    // Ищем pubspec.yaml вверх по дереву директорий
    var current = p.dirname(buildStep.inputId.path);
    var package = buildStep.inputId.package;
    
    while (current.isNotEmpty && current != '.' && current != p.rootPrefix(current)) {
      final pubspecId = AssetId(package, p.join(current, 'pubspec.yaml'));
      if (await buildStep.canRead(pubspecId)) {
        // Для build_runner нужно вернуть путь относительно package
        return current.isEmpty ? '.' : current;
      }
      final parent = p.dirname(current);
      if (parent == current || parent.isEmpty) break;
      current = parent;
    }
    return '.';
  }
}

/// Builder factory для регистрации в build.yaml.
Builder swaggerBuilder(BuilderOptions options) => SwaggerBuilder();
