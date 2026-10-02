/// Base type for every error the app surfaces to the UI.
///
/// Convention: repositories and services *throw* [AppException] subclasses
/// (wrapping lower-level errors from Supabase, Hive, HTTP, ...). Riverpod turns
/// thrown errors into `AsyncValue.error`, and UI code shows [message].
/// Use `Result`/`runCatching` from `result.dart` when an explicit value is
/// more convenient than try/catch (e.g. button handlers).
sealed class AppException implements Exception {
  const AppException(this.message, {this.cause, this.stackTrace});

  /// Human-readable message, safe to show to the user.
  final String message;

  /// Underlying error, if any (for logging only).
  final Object? cause;
  final StackTrace? stackTrace;

  @override
  String toString() => '$runtimeType: $message';
}

/// No connectivity / request failed in transit / timeout.
final class NetworkException extends AppException {
  const NetworkException(super.message, {super.cause, super.stackTrace});
}

/// Sign-in/up failures, missing or expired session.
final class AppAuthException extends AppException {
  const AppAuthException(super.message, {super.cause, super.stackTrace});
}

/// Entity (or user, for share lookups) does not exist or is not visible.
final class NotFoundException extends AppException {
  const NotFoundException(super.message, {super.cause, super.stackTrace});
}

/// RLS / ownership violation, e.g. editing a shared (read-only) item.
final class PermissionDeniedException extends AppException {
  const PermissionDeniedException(
    super.message, {
    super.cause,
    super.stackTrace,
  });
}

/// Invalid user input or invalid data shape.
final class ValidationException extends AppException {
  const ValidationException(super.message, {super.cause, super.stackTrace});
}

/// The resource is already shared with that recipient (unique violation
/// `23505` on `shares`). A [ValidationException], so generic handlers that
/// show validation errors inline keep working.
final class AlreadySharedException extends ValidationException {
  const AlreadySharedException(super.message, {super.cause, super.stackTrace});
}

/// Local storage / sync failures.
final class StorageException extends AppException {
  const StorageException(super.message, {super.cause, super.stackTrace});
}

enum AiErrorKind {
  /// No API key stored for the selected provider.
  missingApiKey,

  /// Provider rejected the key (401/403).
  invalidApiKey,

  /// 429 / quota exhausted.
  rateLimited,

  /// Model returned output that is not valid JSON or fails the schema,
  /// even after the automatic repair retry.
  invalidOutput,

  /// Feature not supported by the provider (e.g. YouTube URL input).
  unsupported,

  /// Any other provider-side error.
  provider,
}

/// Errors from the AI layer (providers, AiService).
final class AiException extends AppException {
  const AiException(
    super.message, {
    this.kind = AiErrorKind.provider,
    this.statusCode,
    super.cause,
    super.stackTrace,
  });

  final AiErrorKind kind;
  final int? statusCode;
}

/// YouTube video has no captions, is private, or fetching was blocked
/// (e.g. CORS on web).
final class TranscriptUnavailableException extends AppException {
  const TranscriptUnavailableException(
    super.message, {
    super.cause,
    super.stackTrace,
  });
}

/// Anything not covered above.
final class UnknownException extends AppException {
  const UnknownException(super.message, {super.cause, super.stackTrace});
}
