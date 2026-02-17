# Dart Example with build_runner

This example demonstrates how to use `dart_swagger_to_models` with `build_runner` in a pure Dart project.

## Setup

1. Install dependencies:
```bash
dart pub get
```

2. Run build_runner to generate models:
```bash
dart run build_runner build
```

3. Run the example:
```bash
dart run lib/main.dart
```

## Project Structure

- `swagger/api.yaml` - OpenAPI specification
- `dart_swagger_to_models.yaml` - Generator configuration
- `build.yaml` - build_runner configuration
- `lib/generated/models/` - Generated Dart models (created by build_runner)

## Configuration

The `dart_swagger_to_models.yaml` file configures the generator:
- `defaultStyle: json_serializable` - Uses json_serializable style
- `outputDir: lib/generated/models` - Output directory for generated models
- `useJsonKey: true` - Generates @JsonKey annotations for snake_case JSON keys

## Usage

After running `build_runner`, you can import and use the generated models:

```dart
import 'package:dart_example/generated/models/user.dart';

final user = User.fromJson({'id': 1, 'name': 'John'});
```
