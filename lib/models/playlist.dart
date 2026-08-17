class Playlist {
  const Playlist({
    required this.id,
    required this.name,
    required this.trackIds,
  });

  final String id;
  final String name;
  final List<String> trackIds;

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'trackIds': trackIds,
  };

  factory Playlist.fromMap(Map<dynamic, dynamic> map) => Playlist(
    id: map['id'] as String,
    name: map['name'] as String,
    trackIds: List<String>.from(map['trackIds'] as List? ?? const []),
  );
}
