import 'package:youtube_explode_dart/youtube_explode_dart.dart';

void main() async {
  final yt = YoutubeExplode();
  try {
    final video = await yt.videos.get(VideoId('dQw4w9WgXcQ'));
    final related = await yt.videos.getRelatedVideos(video);
    print(related?.length);
  } catch (e) {
    print(e);
  }
  yt.close();
}
