import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_app/ai/youtube_url.dart';

void main() {
  const id = 'dQw4w9WgXcQ';

  group('YoutubeUrl.parseVideoId', () {
    final valid = <String>[
      'https://www.youtube.com/watch?v=$id',
      'https://youtube.com/watch?v=$id&t=42s&list=PL123',
      'http://m.youtube.com/watch?feature=share&v=$id',
      'https://music.youtube.com/watch?v=$id',
      'www.youtube.com/watch?v=$id',
      'youtube.com/watch?v=$id',
      'https://youtu.be/$id',
      'https://youtu.be/$id?si=abcdef&t=10',
      'youtu.be/$id',
      'https://www.youtube.com/shorts/$id',
      'https://youtube.com/shorts/$id?feature=share',
      'https://www.youtube.com/embed/$id?start=5',
      'https://www.youtube-nocookie.com/embed/$id',
      'https://www.youtube.com/v/$id',
      'https://www.youtube.com/live/$id?si=x',
      '  https://www.youtube.com/watch?v=$id  ',
      id,
    ];
    for (final url in valid) {
      test('parses "$url"', () {
        expect(YoutubeUrl.parseVideoId(url), id);
      });
    }

    final invalid = <String>[
      '',
      'not a url',
      'https://vimeo.com/123456',
      'https://www.youtube.com/watch?v=short',
      'https://www.youtube.com/channel/UC1234567890',
      'https://www.youtube.com/',
      'https://example.com/watch?v=$id',
      'ftp://youtube.com/watch?v=$id',
    ];
    for (final url in invalid) {
      test('rejects "$url"', () {
        expect(YoutubeUrl.parseVideoId(url), isNull);
      });
    }
  });

  test('normalize returns the canonical watch URL', () {
    expect(
      YoutubeUrl.normalize('https://youtu.be/$id?si=x'),
      'https://www.youtube.com/watch?v=$id',
    );
    expect(YoutubeUrl.normalize('https://vimeo.com/1'), isNull);
  });
}
