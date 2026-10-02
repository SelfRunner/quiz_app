/// Calendar-day helpers in the user's local time zone (pure functions).
///
/// A "day" is represented as a UTC midnight `DateTime` carrying the local
/// calendar date, so day arithmetic is exact (no DST surprises):
/// `localDay(t)` for 23:30 local on 3 March is `DateTime.utc(y, 3, 3)`.
library;

/// Converts a UTC instant to local wall-clock time. Defaults to the device
/// time zone; tests pass a fixed offset ([fixedOffset]).
typedef ToLocal = DateTime Function(DateTime instant);

DateTime deviceLocal(DateTime instant) => instant.toLocal();

/// A [ToLocal] for a fixed UTC offset (tests, previews).
ToLocal fixedOffset(Duration offset) =>
    (instant) => instant.toUtc().add(offset);

/// The local calendar date of [instant] as a UTC midnight.
DateTime localDay(DateTime instant, [ToLocal toLocal = deviceLocal]) {
  final l = toLocal(instant);
  return DateTime.utc(l.year, l.month, l.day);
}

/// Whole days from day [a] to day [b] (both from [localDay]).
int daysBetween(DateTime a, DateTime b) =>
    (b.difference(a).inHours / 24).round();
