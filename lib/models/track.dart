class Track {
  const Track({
    required this.id,
    required this.title,
    required this.artist,
    required this.thumbnailUrl,
    required this.webUrl,
    this.durationSeconds = 0,
    this.localPath,
    this.addedAt,
  });

  final String id;
  final String title;
  final String artist;
  final String thumbnailUrl;
  final String webUrl;
  final int durationSeconds;
  final String? localPath;
  final DateTime? addedAt;

  bool get isDownloaded => localPath != null && localPath!.isNotEmpty;

  String get durationLabel {
    final minutes = durationSeconds ~/ 60;
    final seconds = (durationSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Track copyWith({String? localPath, DateTime? addedAt}) => Track(
    id: id,
    title: title,
    artist: artist,
    thumbnailUrl: thumbnailUrl,
    webUrl: webUrl,
    durationSeconds: durationSeconds,
    localPath: localPath ?? this.localPath,
    addedAt: addedAt ?? this.addedAt,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'title': title,
    'artist': artist,
    'thumbnailUrl': thumbnailUrl,
    'webUrl': webUrl,
    'durationSeconds': durationSeconds,
    'localPath': localPath,
    'addedAt': (addedAt ?? DateTime.now()).toIso8601String(),
  };

  factory Track.fromMap(Map<dynamic, dynamic> map) => Track(
    id: map['id'] as String,
    title: map['title'] as String? ?? 'Unknown title',
    artist: map['artist'] as String? ?? 'Unknown artist',
    thumbnailUrl: map['thumbnailUrl'] as String? ?? '',
    webUrl: map['webUrl'] as String? ?? '',
    durationSeconds: map['durationSeconds'] as int? ?? 0,
    localPath: map['localPath'] as String?,
    addedAt: map['addedAt'] == null
        ? null
        : DateTime.tryParse(map['addedAt'] as String),
  );
}
