import 'permissions.dart';

class RevoltRole {
  final String id;
  final String name;
  final int? colour;
  final int rank;
  final bool hoist;
  final OverrideField? permissions;
  final bool isAdmin;

  RevoltRole({
    required this.id,
    required this.name,
    this.colour,
    this.rank = 0,
    this.hoist = false,
    this.permissions,
    this.isAdmin = false,
  });

  factory RevoltRole.fromJson(String roleId, Map<String, dynamic> json) {
    return RevoltRole(
      id: roleId,
      name: json['name'] as String? ?? 'Unknown',
      colour: json['colour'] != null
          ? _parseColour(json['colour'])
          : null,
      rank: json['rank'] as int? ?? 0,
      hoist: json['hoist'] as bool? ?? false,
      permissions: OverrideField.fromJson(json['permissions']),
      isAdmin: json['is_admin'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    final data = <String, dynamic>{
      'name': name,
      'rank': rank,
      'hoist': hoist,
    };
    if (colour != null) {
      data['colour'] = '#${colour!.toRadixString(16).padLeft(6, '0')}';
    }
    if (permissions != null) data['permissions'] = permissions!.toJson();
    if (isAdmin) data['is_admin'] = true;
    return data;
  }

  static int? _parseColour(dynamic value) {
    if (value is int) return value;
    if (value is String) {
      final hex = value.replaceFirst('#', '');
      if (hex.length == 6) {
        return int.parse(hex, radix: 16) | 0xFF000000;
      }
    }
    return null;
  }
}
