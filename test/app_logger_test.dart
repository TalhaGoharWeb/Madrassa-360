import 'package:flutter_test/flutter_test.dart';
import 'package:madrasa_360/core/observability/app_logger.dart';

void main() {
  group('AppLogger.redact', () {
    test('masks map values for sensitive keys', () {
      final out = AppLogger.redact({
        'username': 'talha',
        'password': 'hunter2',
        'api_key': 'sk-live-abc',
        'note': 'nothing secret',
      }) as Map;
      expect(out['username'], 'talha');
      expect(out['password'], AppLogger.mask);
      expect(out['api_key'], AppLogger.mask);
      expect(out['note'], 'nothing secret');
    });

    test('matches token/secret/authorization/bearer case-insensitively', () {
      final out = AppLogger.redact({
        'Authorization': 'Bearer xyz',
        'REFRESH_TOKEN': 'tok123',
        'clientSecret': 's3cr3t',
      }) as Map;
      expect(out['Authorization'], AppLogger.mask);
      expect(out['REFRESH_TOKEN'], AppLogger.mask);
      expect(out['clientSecret'], AppLogger.mask);
    });

    test('recurses into nested maps and lists', () {
      final out = AppLogger.redact({
        'user': {'name': 'a', 'password': 'p'},
        'items': [
          {'token': 't1'},
          'plain',
        ],
      }) as Map;
      expect((out['user'] as Map)['password'], AppLogger.mask);
      expect(((out['items'] as List)[0] as Map)['token'], AppLogger.mask);
      expect((out['items'] as List)[1], 'plain');
    });

    test('masks inline key=value fragments in free-form strings', () {
      expect(
        AppLogger.redact('login failed for user=x password=hunter2 retry=1'),
        contains('password=${AppLogger.mask}'),
      );
      expect(
        AppLogger.redact('login failed for user=x password=hunter2'),
        isNot(contains('hunter2')),
      );
      expect(
        AppLogger.redact('header Authorization: Bearer abc.def.ghi'),
        contains('Authorization=${AppLogger.mask}'),
      );
    });

    test('leaves non-sensitive values untouched', () {
      expect(AppLogger.redact('plain message'), 'plain message');
      expect(AppLogger.redact(42), 42);
      expect(AppLogger.redact(null), isNull);
      expect(AppLogger.redact(true), isTrue);
    });
  });
}
