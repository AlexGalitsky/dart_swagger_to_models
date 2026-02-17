import 'package:dart_example/generated/models/user.dart';
import 'package:dart_example/generated/models/product.dart';

void main() {
  // Пример использования сгенерированных моделей
  final user = User.fromJson({
    'id': 1,
    'name': 'John Doe',
    'email': 'john@example.com',
  });

  print('User: ${user.name} (${user.email})');

  final product = Product.fromJson({
    'id': 1,
    'name': 'Example Product',
    'price': 99.99,
    'description': 'This is an example product',
  });

  print('Product: ${product.name} - \$${product.price}');
}
