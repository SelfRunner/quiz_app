/// Rules for user-supplied base URLs (OpenAI-compatible endpoints).
///
/// API keys are sent as bearer tokens, so a base URL must use `https://`.
/// Plain `http://` is allowed only for loopback / private-network hosts
/// (local LLM servers such as Ollama or LM Studio): `localhost`,
/// `*.localhost`, `*.local`, `127.0.0.0/8`, `::1`, `10.0.0.0/8`,
/// `172.16.0.0/12` and `192.168.0.0/16`.
library;

import '../core/errors/app_exception.dart';

/// Whether [host] is a loopback or private-network host for which plain
/// `http://` is accepted.
bool isLocalNetworkHost(String host) {
  var h = host.trim().toLowerCase();
  if (h.startsWith('[') && h.endsWith(']')) h = h.substring(1, h.length - 1);
  if (h.endsWith('.')) h = h.substring(0, h.length - 1);
  if (h.isEmpty) return false;
  if (h == 'localhost' || h.endsWith('.localhost') || h.endsWith('.local')) {
    return true;
  }
  if (h == '::1' || h == '0:0:0:0:0:0:0:1') return true;

  final parts = h.split('.');
  if (parts.length != 4) return false;
  final octets = <int>[];
  for (final p in parts) {
    if (p.isEmpty || p.length > 3 || !RegExp(r'^\d+$').hasMatch(p)) {
      return false;
    }
    final n = int.parse(p);
    if (n > 255) return false;
    octets.add(n);
  }
  final [a, b, _, _] = octets;
  return a == 127 ||
      a == 10 ||
      (a == 192 && b == 168) ||
      (a == 172 && b >= 16 && b <= 31);
}

/// User-facing reason why [input] is not an acceptable base URL, or null
/// when it is fine (an empty input is fine: it means "use the default").
String? baseUrlProblem(String input) {
  final s = input.trim();
  if (s.isEmpty) return null;
  final uri = Uri.tryParse(s);
  if (uri == null ||
      !(uri.scheme == 'https' || uri.scheme == 'http') ||
      uri.host.isEmpty) {
    return 'Enter a full base URL, e.g. https://openrouter.ai/api/v1';
  }
  if (uri.scheme == 'http' && !isLocalNetworkHost(uri.host)) {
    return 'Use https:// for remote servers (http:// would send your API key '
        'unencrypted). http:// is only allowed for local servers such as '
        'localhost, 192.168.x.x or *.local.';
  }
  return null;
}

/// Trimmed [input] without trailing slashes. Throws [ValidationException]
/// (message from [baseUrlProblem]) when it is not acceptable.
String normalizeBaseUrl(String input) {
  final problem = baseUrlProblem(input);
  if (problem != null) throw ValidationException(problem);
  return input.trim().replaceAll(RegExp(r'/+$'), '');
}
