import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huawei_remote_config/huawei_remote_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('huawei_remote_config', StandardMethodCodec());
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late List<MethodCall> calls;
  late HuaweiRemoteConfig sut;

  setUp(() {
    calls = [];
    sut = HuaweiRemoteConfig(channel: channel);
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  void handleWith(Object? Function(MethodCall call) handler) {
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return handler(call);
    });
  }

  group('applyDefaults', () {
    test('invokes native applyDefaults with the given defaults', () async {
      handleWith((_) => null);

      await sut.applyDefaults({'greeting': 'hello', 'limit': 10});

      expect(calls, [
        isA<MethodCall>().having((c) => c.method, 'method', 'applyDefaults').having((c) => c.arguments, 'arguments', {
          'defaults': {'greeting': 'hello', 'limit': 10},
        }),
      ]);
    });
  });

  group('fetch', () {
    test('invokes native fetch with no arguments by default', () async {
      handleWith((_) => null);

      await sut.fetch();

      expect(calls.single.method, 'fetch');
      expect(calls.single.arguments, isEmpty);
    });

    test('sends intervalSeconds when interval is provided', () async {
      handleWith((_) => null);

      await sut.fetch(interval: const Duration(minutes: 2));

      expect(calls.single.arguments, {'intervalSeconds': 120});
    });

    test('throws HuaweiRemoteConfigException(fetch_failed) when native rejects', () async {
      handleWith((_) => throw PlatformException(code: 'fetch_failed', message: 'no connectivity'));

      await expectLater(
        sut.fetch(),
        throwsA(
          isA<HuaweiRemoteConfigException>()
              .having((e) => e.code, 'code', 'fetch_failed')
              .having((e) => e.message, 'message', 'no connectivity'),
        ),
      );
    });
  });

  group('apply', () {
    test('invokes native apply', () async {
      handleWith((_) => null);

      await sut.apply();

      expect(calls.single.method, 'apply');
    });

    test('throws HuaweiRemoteConfigException(no_pending_fetch) when native rejects', () async {
      handleWith((_) => throw PlatformException(code: 'no_pending_fetch', message: 'call fetch() first'));

      await expectLater(
        sut.apply(),
        throwsA(
          isA<HuaweiRemoteConfigException>()
              .having((e) => e.code, 'code', 'no_pending_fetch')
              .having((e) => e.message, 'message', 'call fetch() first'),
        ),
      );
    });
  });

  group('fetchAndApply', () {
    test('returns a HuaweiRemoteConfigValues snapshot and forwards interval', () async {
      handleWith((_) => {'greeting': 'hello'});

      final result = await sut.fetchAndApply(interval: const Duration(seconds: 30));

      expect(result.getString('greeting'), 'hello');
      expect(calls.single.method, 'fetchAndApply');
      expect(calls.single.arguments, {'intervalSeconds': 30});
    });
  });

  group('getAll', () {
    test('returns every currently known value', () async {
      handleWith((_) => {'a': 1, 'b': true});

      final result = await sut.getAll();

      expect(result.getInt('a'), 1);
      expect(result.getBool('b'), true);
    });
  });

  group('diagnostics', () {
    test('returns the native snapshot with String keys', () async {
      handleWith(
        (_) => {'packageName': 'com.example.app.dev', 'appId': '115308197', 'appliedKeys': <String>['url']},
      );

      final result = await sut.diagnostics();

      expect(calls.single.method, 'diagnostics');
      expect(result, {
        'packageName': 'com.example.app.dev',
        'appId': '115308197',
        'appliedKeys': ['url'],
      });
    });

    test('returns an empty map when the native side reports nothing', () async {
      handleWith((_) => null);

      expect(await sut.diagnostics(), isEmpty);
    });
  });

  group('typed getters', () {
    test('getString forwards the key and returns the native result', () async {
      handleWith((_) => 'value');

      expect(await sut.getString('key'), 'value');
      expect(calls.single.arguments, {'key': 'key'});
    });

    test('getBool forwards the key and returns the native result', () async {
      handleWith((_) => true);

      expect(await sut.getBool('key'), true);
    });

    test('getInt forwards the key and returns the native result', () async {
      handleWith((_) => 42);

      expect(await sut.getInt('key'), 42);
    });

    test('getDouble forwards the key and returns the native result', () async {
      handleWith((_) => 4.2);

      expect(await sut.getDouble('key'), 4.2);
    });
  });

  group('getSource', () {
    test('parses REMOTE/DEFAULT/STATIC from the native string', () async {
      handleWith((call) => call.arguments['key'] == 'remote' ? 'REMOTE' : 'DEFAULT');

      expect(await sut.getSource('remote'), HuaweiRemoteConfigSource.remote);
      expect(await sut.getSource('other'), HuaweiRemoteConfigSource.default_);
    });

    test('defaults to static when the native side returns null', () async {
      handleWith((_) => null);

      expect(await sut.getSource('unknown'), HuaweiRemoteConfigSource.static_);
    });
  });

  group('clearAll', () {
    test('invokes native clearAll', () async {
      handleWith((_) => null);

      await sut.clearAll();

      expect(calls.single.method, 'clearAll');
    });
  });

  group('setDeveloperMode', () {
    test('forwards enabled', () async {
      handleWith((_) => null);

      await sut.setDeveloperMode(enabled: true);

      expect(calls.single.arguments, {'enabled': true});
    });
  });

  group('custom attributes', () {
    test('setCustomAttributes forwards the attributes map', () async {
      handleWith((_) => null);

      await sut.setCustomAttributes({'segment': 'beta'});

      expect(calls.single.arguments, {
        'attributes': {'segment': 'beta'},
      });
    });

    test('getCustomAttributes returns a String-keyed, String-valued map', () async {
      handleWith((_) => {'segment': 'beta'});

      expect(await sut.getCustomAttributes(), {'segment': 'beta'});
    });
  });

  group('error mapping', () {
    test('wraps a native_error PlatformException as HuaweiRemoteConfigException', () async {
      handleWith((_) => throw PlatformException(code: 'native_error', message: 'unexpected AGC failure'));

      await expectLater(
        sut.getAll(),
        throwsA(
          isA<HuaweiRemoteConfigException>()
              .having((e) => e.code, 'code', 'native_error')
              .having((e) => e.message, 'message', 'unexpected AGC failure')
              .having((e) => e.details, 'details', isNull),
        ),
      );
    });

    test('exposes native error metadata as String-keyed details', () async {
      handleWith(
        (_) => throw PlatformException(
          code: 'fetch_failed',
          message: 'network error',
          details: {'type': 'com.huawei.agconnect.AGCServerException', 'message': 'network error', 'cause': null},
        ),
      );

      await expectLater(
        sut.fetch(),
        throwsA(
          isA<HuaweiRemoteConfigException>().having((e) => e.details, 'details', {
            'type': 'com.huawei.agconnect.AGCServerException',
            'message': 'network error',
          }),
        ),
      );
    });

    test('leaves details null when the native side sends a non-map', () async {
      handleWith((_) => throw PlatformException(code: 'fetch_failed', message: 'boom', details: 'not-a-map'));

      await expectLater(
        sut.fetch(),
        throwsA(isA<HuaweiRemoteConfigException>().having((e) => e.details, 'details', isNull)),
      );
    });

    test('maps a missing native handler to unsupported_platform', () async {
      messenger.setMockMethodCallHandler(channel, null);

      await expectLater(
        sut.getAll(),
        throwsA(isA<HuaweiRemoteConfigException>().having((e) => e.code, 'code', 'unsupported_platform')),
      );
    });
  });

  group('unsupported platform', () {
    setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.iOS);
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test('throws without ever reaching the channel', () async {
      handleWith((_) => fail('should not invoke the native channel on a non-Android platform'));

      await expectLater(
        sut.getAll(),
        throwsA(isA<HuaweiRemoteConfigException>().having((e) => e.code, 'code', 'unsupported_platform')),
      );
      expect(calls, isEmpty);
    });
  });
}
