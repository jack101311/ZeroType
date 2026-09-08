import 'package:flutter_test/flutter_test.dart';
import 'package:zero_type/core/security/endpoint_policy.dart';

void main() {
  test('Allows defaults and trusted HTTPS endpoint configuration', () {
    expect(EndpointPolicy.validate('  '), '');
    expect(
      EndpointPolicy.validate(' https://example.com/v1/audio/transcriptions '),
      'https://example.com/v1/audio/transcriptions',
    );
  });
  for (final String input in [
    'http://example.com',
    'file:///tmp/audio',
    '//example.com',
    'https://user:password@example.com',
    'https://example.com?q=secret',
    'https://example.com#fragment',
    'not a url',
  ]) {
    test('Rejects unsafe endpoint $input', () {
      expect(() => EndpointPolicy.validate(input), throwsFormatException);
    });
  }
}
