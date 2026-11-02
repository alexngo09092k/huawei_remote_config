import 'package:flutter_test/flutter_test.dart';
import 'package:huawei_remote_config/huawei_remote_config.dart';

void main() {
  group('HuaweiRemoteConfigValues', () {
    test('drops entries with a null key or null value', () {
      final values = HuaweiRemoteConfigValues({'a': 1, null: 2, 'b': null});

      expect(values.keys, {'a'});
    });

    test('getString returns null for a non-String value', () {
      final values = HuaweiRemoteConfigValues({'a': 1});

      expect(values.getString('a'), isNull);
    });

    test('getBool returns null for a non-bool value', () {
      final values = HuaweiRemoteConfigValues({'a': 'true'});

      expect(values.getBool('a'), isNull);
    });

    test('getInt accepts an int', () {
      final values = HuaweiRemoteConfigValues({'a': 42});

      expect(values.getInt('a'), 42);
    });

    test('getInt accepts a whole-number double', () {
      final values = HuaweiRemoteConfigValues({'a': 42.0});

      expect(values.getInt('a'), 42);
    });

    test('getInt returns null for a fractional double', () {
      final values = HuaweiRemoteConfigValues({'a': 42.5});

      expect(values.getInt('a'), isNull);
    });

    test('getDouble accepts a double', () {
      final values = HuaweiRemoteConfigValues({'a': 4.2});

      expect(values.getDouble('a'), 4.2);
    });

    test('getDouble accepts an int', () {
      final values = HuaweiRemoteConfigValues({'a': 42});

      expect(values.getDouble('a'), 42.0);
    });

    test('getDouble returns null for a non-numeric value', () {
      final values = HuaweiRemoteConfigValues({'a': 'nope'});

      expect(values.getDouble('a'), isNull);
    });

    test('asMap returns an unmodifiable copy of the values', () {
      final values = HuaweiRemoteConfigValues({'a': 1});

      expect(() => values.asMap()['b'] = 2, throwsUnsupportedError);
    });

    test('missing keys return null from every typed getter', () {
      final values = HuaweiRemoteConfigValues(const {});

      expect(values.getString('missing'), isNull);
      expect(values.getBool('missing'), isNull);
      expect(values.getInt('missing'), isNull);
      expect(values.getDouble('missing'), isNull);
    });
  });
}
