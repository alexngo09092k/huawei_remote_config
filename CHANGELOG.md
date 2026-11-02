## 1.0.0

* Added an `example/` app demonstrating `applyDefaults`, `fetchAndApply`,
  `getSource`, and `diagnostics`.
* Documented the remaining public constructors (`HuaweiRemoteConfig.new`,
  `HuaweiRemoteConfigException.new`, `HuaweiRemoteConfigValues.new`).
* No API changes since `0.1.0`; promoted to a stable `1.0.0` release.

## 0.1.0

* Initial release.
* Wraps `AGConnectConfig`: `applyDefaults`, `fetch`, `apply`, `fetchAndApply`,
  `getAll`, `getString`/`getBool`/`getInt`/`getDouble`, `getSource`,
  `clearAll`, `setDeveloperMode`, `setCustomAttributes`/`getCustomAttributes`.
* `diagnostics()` reports which AGC app the build resolves to (`appId`,
  `packageName`, `region`, credential suffixes) plus the applied keys — the
  check for "the fetch succeeded but returned nothing".
* Every fetch logs to logcat under the `HuaweiRemoteConfig` tag: elapsed time,
  resolved app, returned keys, and an explicit warning when AGC returns zero
  parameters.
* `HuaweiRemoteConfigException.details` carries the native exception type,
  message and cause for `fetch_failed`/`native_error`.
* Android-only.
