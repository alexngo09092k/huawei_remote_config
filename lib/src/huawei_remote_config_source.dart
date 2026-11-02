/// Where a value returned by [HuaweiRemoteConfig] last came from.
///
/// Mirrors the native `AGConnectConfig.SOURCE` enum
/// (`STATIC` / `DEFAULT` / `REMOTE`) — see the Huawei AppGallery Connect
/// Remote Config Android reference for `AGConnectConfig.getSource`.
enum HuaweiRemoteConfigSource {
  /// No value is known for the key at all (no default, no fetched value).
  static_,

  /// The value came from [HuaweiRemoteConfig.applyDefaults].
  default_,

  /// The value came from a fetched-and-applied remote config.
  remote,
}

/// Parses the raw string sent by the native side (`STATIC`/`DEFAULT`/`REMOTE`)
/// into a [HuaweiRemoteConfigSource].
HuaweiRemoteConfigSource huaweiRemoteConfigSourceFromNative(String value) {
  switch (value) {
    case 'DEFAULT':
      return HuaweiRemoteConfigSource.default_;
    case 'REMOTE':
      return HuaweiRemoteConfigSource.remote;
    case 'STATIC':
    default:
      return HuaweiRemoteConfigSource.static_;
  }
}
