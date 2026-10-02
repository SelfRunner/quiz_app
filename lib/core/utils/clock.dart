import 'package:uuid/uuid.dart';

/// Current time in UTC. All timestamps in models are UTC.
typedef Clock = DateTime Function();

DateTime systemClock() => DateTime.now().toUtc();

/// Generates client-side ids (UUID v4) for every entity.
typedef IdGenerator = String Function();

const Uuid _uuid = Uuid();

String uuidV4() => _uuid.v4();
