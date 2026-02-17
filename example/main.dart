import 'dart:io';

import 'package:dart_swagger_to_models/dart_swagger_to_models.dart';

/// Simple example showing how to use the library API directly.
///
/// In real projects you would usually call the CLI, but this demonstrates
/// that the package can be used programmatically as well.
Future<void> main() async {
  // Suppose you have a local OpenAPI/Swagger file `example/swagger/api.yaml`.
  final inputSpec = 'example/dart_example/swagger/api.yaml';

  // Generate models into `example_output/models` directory inside this package.
  final outputDir = 'example_output/models';

  final result = await SwaggerToDartGenerator.generateModels(
    input: inputSpec,
    outputDir: outputDir,
    projectDir: Directory.current.path,
  );

  stdout.writeln('Generated ${result.generatedFiles.length} files:');
  for (final file in result.generatedFiles) {
    stdout.writeln('  - $file');
  }
}

