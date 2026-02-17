/*SWAGGER-TO-DART*/

import 'package:json_annotation/json_annotation.dart';
part 'user.g.dart';

/*SWAGGER-TO-DART: Codegen start*/
@JsonSerializable()
class User {
  final int id;

  const User({
    required  this.id,
  });

  factory User.fromJson(Map<String, dynamic> json) => _$UserFromJson(json);

  Map<String, dynamic> toJson() => _$UserToJson(this);
}

/*SWAGGER-TO-DART: Codegen stop*/
