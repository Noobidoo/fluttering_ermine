import 'revolt_file.dart';

class UserProfile {
  final String? content;
  final RevoltFile? background;

  UserProfile({this.content, this.background});

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
        content: json['content'] as String?,
        background: json['background'] != null
            ? RevoltFile.fromJson(
                json['background'] as Map<String, dynamic>)
            : null,
      );
}
