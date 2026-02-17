# Flutter Example with build_runner

This example demonstrates how to use `dart_swagger_to_models` with `build_runner` in a Flutter project, including integration with an HTTP client.

## Setup

1. Install dependencies:
```bash
flutter pub get
```

2. Run build_runner to generate models:
```bash
flutter pub run build_runner build
```

3. Run the Flutter app:
```bash
flutter run
```

## Project Structure

- `swagger/api.yaml` - OpenAPI specification
- `dart_swagger_to_models.yaml` - Generator configuration
- `build.yaml` - build_runner configuration
- `lib/generated/models/` - Generated Dart models (created by build_runner)
- `lib/services/api_service.dart` - Example HTTP service using generated models

## Configuration

The `dart_swagger_to_models.yaml` file configures the generator:
- `defaultStyle: json_serializable` - Uses json_serializable style
- `outputDir: lib/generated/models` - Output directory for generated models
- `useJsonKey: true` - Generates @JsonKey annotations for snake_case JSON keys

## Usage

After running `build_runner`, you can import and use the generated models in your Flutter app:

```dart
import 'package:flutter_example/generated/models/user.dart';

final user = User.fromJson({'id': 1, 'name': 'John'});
```

The example includes an `ApiService` class that demonstrates how to:
- Fetch data from an API
- Parse JSON responses into generated models
- Use models in Flutter widgets

## Example API

This example uses [JSONPlaceholder](https://jsonplaceholder.typicode.com) as a mock API. You can replace it with your own API endpoint.
