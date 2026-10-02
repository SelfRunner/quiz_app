/// Transcript of a YouTube video.
class VideoTranscript {
  const VideoTranscript({
    required this.videoId,
    required this.text,
    this.title,
    this.languageCode,
  });

  final String videoId;
  final String? title;

  /// Plain caption text (no timestamps).
  final String text;
  final String? languageCode;
}

/// Fetches YouTube captions client-side (used for non-Gemini providers).
abstract interface class TranscriptService {
  /// Throws `ValidationException` for an invalid URL and
  /// `TranscriptUnavailableException` when there are no captions or the
  /// request is blocked (e.g. CORS on web).
  Future<VideoTranscript> fetchTranscript(String url);
}
