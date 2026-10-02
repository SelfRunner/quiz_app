import 'app_exception.dart';

/// Minimal success/failure value.
sealed class Result<T> {
  const Result();

  bool get isOk => this is Ok<T>;

  /// The value, or null on failure.
  T? get valueOrNull => switch (this) {
    Ok<T>(:final value) => value,
    Err<T>() => null,
  };

  /// The error, or null on success.
  AppException? get errorOrNull => switch (this) {
    Ok<T>() => null,
    Err<T>(:final error) => error,
  };
}

final class Ok<T> extends Result<T> {
  const Ok(this.value);
  final T value;
}

final class Err<T> extends Result<T> {
  const Err(this.error);
  final AppException error;
}

/// Runs [body] and converts thrown errors into an [Err].
/// Non-[AppException] errors are wrapped in [UnknownException].
Future<Result<T>> runCatching<T>(Future<T> Function() body) async {
  try {
    return Ok(await body());
  } on AppException catch (e) {
    return Err(e);
  } catch (e, st) {
    return Err(
      UnknownException("That didn't work. Try again.", cause: e, stackTrace: st),
    );
  }
}
