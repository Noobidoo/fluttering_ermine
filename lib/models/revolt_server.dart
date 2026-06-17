import 'revolt_file.dart';

class RevoltServer {
  final String id;
  final String name;
  final String? description;
  final List<String> channelIds;
  final RevoltFile? icon;

  RevoltServer({
    required this.id,
    required this.name,
    this.description,
    required this.channelIds,
    this.icon,
  });

  factory RevoltServer.fromJson(Map<String, dynamic> json) => RevoltServer(
    id: json['_id'] as String,
    name: json['name'] as String,
    description: json['description'] as String?,
    channelIds: (json['channels'] as List<dynamic>?)?.cast<String>() ?? [],
    icon: json['icon'] != null
        ? RevoltFile.fromJson(json['icon'] as Map<String, dynamic>)
        : null,
  );

  String? iconUrlFor(String autumnBase) => icon?.urlFor(autumnBase);
}
