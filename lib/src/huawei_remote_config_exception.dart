/// An error raised by a native `AGConnectConfig` operation, or by the plugin
/// itself when it is used incorrectly (e.g. calling [HuaweiRemoteConfig.apply]
/// before a successful [HuaweiRemoteConfig.fetch]).
///
/// Callers on non-Huawei devices or non-Android platforms should expect this
/// on every call — there is no fallback built into the plugin, by design:
/// deciding what to do when Huawei Remote Config isn't available (e.g.
/// falling back to Firebase Remote Config defaults) is the host app's
/// concern, not this package's.
class HuaweiRemoteConfigException implements Exception {
  /// Creates an exception with the given machine-readable [code], and
  /// optional human-readable [message] and native [details].
  const HuaweiRemoteConfigException({required this.code, this.message, this.details});

  /// A stable, machine-readable code. One of:
  /// - `fetch_failed` — the native `fetch()`/`fetch(interval)` call failed
  ///   (no connectivity, AGC not configured, etc.)
  /// - `no_pending_fetch` — [HuaweiRemoteConfig.apply] was called without a
  ///   preceding successful [HuaweiRemoteConfig.fetch]
  /// - `unsupported_platform` — called on a platform other than Android
  ///   (e.g. iOS), where no native handler is registered
  /// - `native_error` — any other native-side exception
  final String code;

  /// A human-readable message from the native side, if any.
  final String? message;

  /// Native error metadata, when the failure came from the AGC SDK: `type`
  /// (the Java exception class), `message`, and `cause`. `null` for failures
  /// raised by the plugin itself (`unsupported_platform`, `no_pending_fetch`).
  ///
  /// The AGC SDK reports misconfiguration and server rejections through the
  /// exception type and message rather than distinct codes, so this is what
  /// tells "no connectivity" apart from "this app has no Remote Config".
  final Map<String, String>? details;

  @override
  String toString() =>
      'HuaweiRemoteConfigException(code: $code, message: $message${details == null ? '' : ', details: $details'})';
}
