import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_example/generated/models/user.dart';

/// API service for fetching users.
///
/// This service demonstrates how to use generated models with HTTP client.
class ApiService {
  final String baseUrl;
  final http.Client _client;

  ApiService({
    this.baseUrl = 'https://jsonplaceholder.typicode.com',
    http.Client? client,
  }) : _client = client ?? http.Client();

  /// Fetches all users from the API.
  Future<List<User>> getUsers() async {
    final response = await _client.get(
      Uri.parse('$baseUrl/users'),
    );

    if (response.statusCode == 200) {
      final List<dynamic> jsonList = jsonDecode(response.body);
      return jsonList
          .map((json) => User.fromJson(json as Map<String, dynamic>))
          .toList();
    } else {
      throw Exception('Failed to load users: ${response.statusCode}');
    }
  }

  /// Fetches a single user by ID.
  Future<User> getUser(int id) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/users/$id'),
    );

    if (response.statusCode == 200) {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return User.fromJson(json);
    } else {
      throw Exception('Failed to load user: ${response.statusCode}');
    }
  }

  void dispose() {
    _client.close();
  }
}
