import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_app/ai/base_url_policy.dart';
import 'package:quiz_app/core/errors/app_exception.dart';

void main() {
  test('isLocalNetworkHost', () {
    for (final h in [
      'localhost',
      'LOCALHOST',
      'ollama.localhost',
      'my-mac.local',
      '127.0.0.1',
      '127.1.2.3',
      '::1',
      '[::1]',
      '10.0.0.5',
      '192.168.1.20',
      '172.16.0.1',
      '172.31.255.255',
    ]) {
      expect(isLocalNetworkHost(h), isTrue, reason: h);
    }
    for (final h in [
      'openrouter.ai',
      'localhost.evil.com',
      'local',
      '10.0.0.1.nip.io',
      '172.15.0.1',
      '172.32.0.1',
      '192.169.0.1',
      '8.8.8.8',
      '256.0.0.1',
      '1.2.3',
      '',
    ]) {
      expect(isLocalNetworkHost(h), isFalse, reason: h);
    }
  });

  test('baseUrlProblem', () {
    expect(baseUrlProblem(''), isNull);
    expect(baseUrlProblem('https://openrouter.ai/api/v1'), isNull);
    expect(baseUrlProblem('http://localhost:11434/v1'), isNull);
    expect(baseUrlProblem('http://[::1]:11434/v1'), isNull);
    expect(baseUrlProblem('http://10.1.2.3/v1'), isNull);
    expect(baseUrlProblem('http://box.local:1234/v1'), isNull);

    expect(baseUrlProblem('openrouter'), contains('full base URL'));
    expect(baseUrlProblem('ftp://example.com'), contains('full base URL'));
    expect(baseUrlProblem('http://openrouter.ai/api/v1'), contains('https://'));
    expect(
      baseUrlProblem('http://127.0.0.1@evil.com/v1'),
      contains('https://'),
    );
  });

  test('normalizeBaseUrl trims and throws ValidationException', () {
    expect(
      normalizeBaseUrl(' https://x.example/v1// '),
      'https://x.example/v1',
    );
    expect(
      () => normalizeBaseUrl('http://api.example.com/v1'),
      throwsA(isA<ValidationException>()),
    );
  });
}
