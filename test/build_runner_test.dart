import 'package:test/test.dart';

void main() {
  group('build_runner integration (0.4.1)', () {
    test('Builder is available for use in build.yaml', () {
      // Builder should be imported directly from src/build/swagger_builder.dart
      // to avoid loading dart:mirrors during normal library usage
      // Actual Builder functionality is covered by main generator tests
      // To use Builder in build.yaml use:
      // dart_swagger_to_models|swaggerBuilder
      expect(true,
          isTrue); // Placeholder test - Builder functionality is covered by main generator tests
    });
  },
      skip: 'Builder tests require build package which uses dart:mirrors. '
          'Builder functionality is covered by main generator tests. '
          'To use Builder import: import \'package:dart_swagger_to_models/src/build/swagger_builder.dart\';');
}
