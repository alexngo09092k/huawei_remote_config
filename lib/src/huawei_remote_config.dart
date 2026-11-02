import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'huawei_remote_config_exception.dart';
import 'huawei_remote_config_source.dart';
import 'huawei_remote_config_values.dart';

/// Flutter client for Huawei AppGallery Connect's native Remote Config SDK
/// (`AGConnectConfig`).
///
/// Android-only: there is no Google Play Services equivalent, so this
/// package declares itself Android-only in `pubspec.yaml` and every method
/// throws [HuaweiRemoteConfigException] with code `unsupported_platform` on
/// any other platform, rather than silently doing nothing.
///
/// This package is intentionally unaware of Firebase Remote Config, feature
/// flags, or any app-specific fallback strategy — it is a thin, testable
/// wrapper around the native SDK. Deciding *when* to use Huawei Remote
/// Config (e.g. only on Huawei/Honor devices) and how to combine its values
/// with another remote-config backend is the host app's responsibility.
///
/// See the host app's `android/build.gradle` requirements in this package's
/// README — the native SDK dependency travels with this plugin, but AGC
/// project initialisation (the `agconnect-services.json` file and the
/// `com.huawei.agconnect` Gradle plugin) must still be set up in the
/// consuming app's `android/app` module, because AGC reads its own
/// initialisation config from the application module, not from a library.
class HuaweiRemoteConfig {
  /// Creates a client backed by [channel], or by the plugin's default
  /// `MethodChannel` if omitted.
  ///
  /// Most callers should use [instance] instead; passing [channel] is mainly
  /// useful in tests, to stub out the native side with
  /// `TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler`.
  HuaweiRemoteConfig({MethodChannel? channel}) : _channel = channel ?? _defaultChannel;

  static const _channelName = 'huawei_remote_config';

  static const MethodChannel _defaultChannel = MethodChannel(_channelName, StandardMethodCodec());

  static final HuaweiRemoteConfig _instance = HuaweiRemoteConfig();

  /// A shared instance, for the common case of a single Remote Config
  /// project per app — mirrors `AGConnectConfig.getInstance()`.
  static HuaweiRemoteConfig get instance => _instance;

  final MethodChannel _channel;

  /// Sets local default values, used whenever a key has never been fetched
  /// (or fetched-and-applied) from the remote backend.
  ///
  /// Mirrors `AGConnectConfig.applyDefault(Map)`. Values must be
  /// `bool`/`double`/`int`/`String` — [HuaweiRemoteConfigSource.default_] is
  /// then reported by [getSource] for these keys until a remote value is
  /// applied.
  Future<void> applyDefaults(Map<String, Object> defaults) => _invoke('applyDefaults', {'defaults': defaults});

  /// Fetches remote config values from the AGC backend without activating
  /// them.
  ///
  /// Fetched values are held natively as "pending" until [apply] (or
  /// [fetchAndApply]) is called — mirroring the native
  /// `AGConnectConfig.fetch()` / `apply(ConfigValues)` split. Unlike
  /// [getAll], this deliberately does not return the fetched values: the
  /// native `ConfigValues` handle returned by `fetch()` only supports
  /// look-up by a key you already know (`containKey`/`getValueAsX`), not
  /// enumeration, so there is no way to hand back "everything that was
  /// fetched" without already knowing every key to ask for.
  ///
  /// [interval] forces a minimum fetch interval; omit it to use the SDK's
  /// own default throttling. Throws [HuaweiRemoteConfigException] with code
  /// `fetch_failed` if the fetch fails (no connectivity, AGC not configured
  /// for this app, etc.).
  Future<void> fetch({Duration? interval}) =>
      _invoke('fetch', {if (interval != null) 'intervalSeconds': interval.inSeconds});

  /// Activates the values from the most recent [fetch] call, merging them
  /// into the values readable via [getAll]/[getString]/[getBool]/[getInt]/
  /// [getDouble]/[getSource].
  ///
  /// Throws [HuaweiRemoteConfigException] with code `no_pending_fetch` if
  /// called without a preceding successful [fetch].
  Future<void> apply() => _invoke('apply');

  /// Fetches and immediately activates remote config values, returning a
  /// snapshot of every currently known value (defaults + remote) — i.e.
  /// equivalent to calling [fetch], then [apply], then [getAll], but in one
  /// platform-channel round trip. This is the method most callers want.
  ///
  /// With no [interval] the native SDK applies its own throttling (a cache of
  /// roughly 12 hours), so a parameter published in the AGC console minutes
  /// ago will not show up. Pass `Duration.zero` to force an actual round trip
  /// — do that in development/QA builds, not in production, where the cache
  /// is what keeps the app off the network on every cold start.
  Future<HuaweiRemoteConfigValues> fetchAndApply({Duration? interval}) async {
    final result = await _invoke<Map<Object?, Object?>>('fetchAndApply', {
      if (interval != null) 'intervalSeconds': interval.inSeconds,
    });
    return HuaweiRemoteConfigValues(result ?? const {});
  }

  /// Returns every currently known value (defaults + remote), whichever
  /// takes precedence per the native SDK's own merge rules.
  ///
  /// Mirrors `AGConnectConfig.getMergedAll()`.
  Future<HuaweiRemoteConfigValues> getAll() async {
    final result = await _invoke<Map<Object?, Object?>>('getAll');
    return HuaweiRemoteConfigValues(result ?? const {});
  }

  /// Which AGC app this build actually talks to, read from the
  /// `agconnect-services.json` baked into the APK, plus the keys currently
  /// applied.
  ///
  /// Intended for logging when a fetch succeeds but returns nothing: the
  /// `appId`/`packageName` reported here must match the app selected in the
  /// AGC console's Remote Configuration page, otherwise the fetch is reading
  /// a different app's (empty) configuration. Keys:
  ///
  /// - `packageName` — the running app's package
  /// - `configuredPackageName` — the package `agconnect-services.json`
  ///   resolved to; a mismatch with `packageName` means the multi-app
  ///   `appInfos` entry for this flavour is missing
  /// - `appId`, `clientId`, `projectId`, `productId` — resolved AGC identifiers
  /// - `region`, `gatewayUrl` — the AGC data-processing location in use
  /// - `apiKeySuffix`, `clientSecretSuffix` — last few characters of the
  ///   credentials, enough to diff against the console without leaking them
  /// - `appliedKeys` — `List<String>` of currently applied config keys
  ///
  /// Values are whatever the native side could resolve; any of them may be
  /// `null` if the AGC SDK failed to initialise (itself a useful finding).
  Future<Map<String, Object?>> diagnostics() async {
    final result = await _invoke<Map<Object?, Object?>>('diagnostics');
    return {for (final entry in (result ?? const {}).entries) entry.key.toString(): entry.value};
  }

  /// Returns the value for [key] as a [String], or `null` if unknown.
  Future<String?> getString(String key) => _invoke<String?>('getString', {'key': key});

  /// Returns the value for [key] as a [bool], or `null` if unknown.
  Future<bool?> getBool(String key) => _invoke<bool?>('getBool', {'key': key});

  /// Returns the value for [key] as an [int], or `null` if unknown.
  ///
  /// Native integral values are backed by Java `Long` (`getValueAsLong`).
  Future<int?> getInt(String key) => _invoke<int?>('getInt', {'key': key});

  /// Returns the value for [key] as a [double], or `null` if unknown.
  Future<double?> getDouble(String key) => _invoke<double?>('getDouble', {'key': key});

  /// Returns where the current value of [key] came from.
  ///
  /// Mirrors `AGConnectConfig.getSource(String)`.
  Future<HuaweiRemoteConfigSource> getSource(String key) async {
    final result = await _invoke<String>('getSource', {'key': key});
    return huaweiRemoteConfigSourceFromNative(result ?? 'STATIC');
  }

  /// Clears every applied value, default value, and pending fetch.
  ///
  /// Mirrors `AGConnectConfig.clearAll()`.
  Future<void> clearAll() => _invoke('clearAll');

  /// Enables or disables AGC developer mode, which disables the SDK's
  /// throttling of fetch requests — useful during development/QA, never in
  /// production.
  ///
  /// Mirrors `AGConnectConfig.setDeveloperMode(boolean)`.
  Future<void> setDeveloperMode({required bool enabled}) => _invoke('setDeveloperMode', {'enabled': enabled});

  /// Sets custom attributes used by the AGC backend for percentage/condition
  /// targeting (A/B testing, staged rollouts, ...).
  ///
  /// Mirrors `AGConnectConfig.setCustomAttributes(Map)`.
  Future<void> setCustomAttributes(Map<String, String> attributes) =>
      _invoke('setCustomAttributes', {'attributes': attributes});

  /// Returns the custom attributes currently set via [setCustomAttributes].
  ///
  /// Mirrors `AGConnectConfig.getCustomAttributes()`.
  Future<Map<String, String>> getCustomAttributes() async {
    final result = await _invoke<Map<Object?, Object?>>('getCustomAttributes');
    return {for (final entry in (result ?? const {}).entries) entry.key.toString(): entry.value.toString()};
  }

  Future<T?> _invoke<T>(String method, [Map<String, Object?>? arguments]) async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      throw const HuaweiRemoteConfigException(
        code: 'unsupported_platform',
        message: 'huawei_remote_config is Android-only.',
      );
    }
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on PlatformException catch (e) {
      throw HuaweiRemoteConfigException(code: e.code, message: e.message, details: _stringifyDetails(e.details));
    } on MissingPluginException {
      throw const HuaweiRemoteConfigException(
        code: 'unsupported_platform',
        message: 'No huawei_remote_config native handler is registered on this platform.',
      );
    }
  }

  /// The native side sends error metadata (exception type, message, cause) as
  /// the platform error details; anything else is ignored rather than guessed
  /// at, so [HuaweiRemoteConfigException.details] is always a `String`-keyed
  /// map or `null`.
  static Map<String, String>? _stringifyDetails(Object? details) {
    if (details is! Map) return null;
    final entries = {
      for (final entry in details.entries)
        if (entry.key != null && entry.value != null) entry.key.toString(): entry.value.toString(),
    };
    return entries.isEmpty ? null : entries;
  }
}
