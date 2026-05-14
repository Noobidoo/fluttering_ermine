class RevoltFile {
  final String id;
  final String tag;
  final String filename;

  RevoltFile({required this.id, required this.tag, required this.filename});

  factory RevoltFile.fromJson(Map<String, dynamic> json) => RevoltFile(
        id: json['_id'] as String,
        tag: json['tag'] as String,
        filename: json['filename'] as String? ?? '',
      );

  String urlFor(String autumnBase) => '$autumnBase/$tag/$id';
}
