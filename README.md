# huawei_remote_config

A Flutter plugin wrapping Huawei AppGallery Connect's native Remote Config
SDK (`AGConnectConfig`). **Android-only** — there is no equivalent on
Huawei/Honor devices for iOS, since Remote Config on iOS there would still
go through Firebase (Huawei/Honor devices only lack Google Play Services on
Android).

This package talks directly to the native AGConnect SDK rather than the
`agconnect_remote_config` package on pub.dev, which is effectively
unmaintained (unverified publisher, last released years ago, negligible
download count) — a poor supply-chain fit for a production app.

## Why a plugin, not app code

Firebase Remote Config's `fetchAndActivate()` always fails on Huawei/Honor
devices (no Google Play Services). Apps that ship to the Huawei AppGallery
need a second remote-config backend for those devices. This package isolates
that concern — the native SDK dependency, the `MethodChannel`, and the
platform-channel error handling — behind a small, testable Dart API, so the
host app's Firebase-based remote-config code doesn't need to know AGC
exists.

This package is deliberately unaware of Firebase, feature flags, or any
particular merge/fallback strategy. Deciding **when** to use it (e.g. "only
on Huawei/Honor devices") and how to combine its values with another
backend is entirely up to the consuming app.

## Setup

### 1. Add the dependency

```yaml
dependencies:
  huawei_remote_config: ^1.0.0
```

Or from the command line:

```sh
flutter pub add huawei_remote_config
```

### 2. Configure the host app's Android project

The native SDK dependency (`com.huawei.agconnect:agconnect-remoteconfig`)
travels with this plugin's own `android/build.gradle` — you do not need to
add it yourself. However, AppGallery Connect project initialisation cannot
live in a library module; it reads its configuration from the **application**
module, so the following three pieces still belong in the host app, not in
this plugin:

**`android/settings.gradle`** — make the Huawei Maven repo resolvable, and
map the `com.huawei.agconnect.agcp` plugin id to its Maven module (Gradle's
plugin resolution needs this indirection because the AGC plugin is not
published to the Gradle Plugin Portal):

```groovy
pluginManagement {
    repositories {
        // ...
        maven { url 'https://developer.huawei.com/repo/' }
    }
    resolutionStrategy {
        eachPlugin {
            if (it.requested.id.getNamespace() == 'com.huawei.agconnect') {
                if (it.requested.id.id == 'com.huawei.agconnect.agcp') {
                    it.useModule('com.huawei.agconnect:agcp:1.9.1.300')
                }
            }
        }
    }
}

plugins {
    // ...
    id "com.huawei.agconnect.agcp" version "1.9.1.300" apply false
}
```

**Root `android/build.gradle`** — put the Huawei Maven repo on the
buildscript classpath and add the AGC Gradle plugin classpath:

```groovy
buildscript {
    repositories {
        // ...
        maven { url 'https://developer.huawei.com/repo/' }
    }
    dependencies {
        classpath 'com.huawei.agconnect:agcp:1.9.1.300'
    }
}
```

**`android/app/build.gradle`** — apply the plugin in the app module:

```groovy
plugins {
    id "com.android.application"
    // ...
    id "com.huawei.agconnect"
}
```

**`android/app/agconnect-services.json`** — download this from AppGallery
Connect (Project settings → General information → App) and place it at
`android/app/agconnect-services.json`. This is what actually provides the
per-app AGC project ID that `agconnect-remoteconfig` fetches against.

### 3. (Optional) ProGuard / R8

If the host app enables minification, this plugin's own
`consumer-rules.pro` already keeps the required `com.huawei.agconnect.**`
and `com.huawei.hmf.**` classes — no extra ProGuard rules needed in the app.

## Usage

```dart
import 'package:huawei_remote_config/huawei_remote_config.dart';

final huaweiRemoteConfig = HuaweiRemoteConfig.instance;

// Seed defaults, then fetch and activate remote values in one call.
await huaweiRemoteConfig.applyDefaults({'greeting': 'hello'});

try {
  final values = await huaweiRemoteConfig.fetchAndApply();
  final greeting = values.getString('greeting');
} on HuaweiRemoteConfigException catch (e) {
  // e.code is one of: fetch_failed, no_pending_fetch, unsupported_platform,
  // native_error. Decide your own fallback here — this package has none.
}
```

Prefer to fetch and activate separately (e.g. to check for a fetch error
before touching any currently active values)?

```dart
await huaweiRemoteConfig.fetch();
// fetched values are not yet readable here — `fetch()`'s native
// `ConfigValues` handle only supports look-up by a key you already know,
// not enumeration, so there is nothing meaningful to return until `apply()`.
await huaweiRemoteConfig.apply();
final values = await huaweiRemoteConfig.getAll();
```

## API

| Method | Native equivalent |
| --- | --- |
| `applyDefaults(Map<String, Object>)` | `applyDefault(Map)` |
| `fetch({Duration? interval})` | `fetch()` / `fetch(long)` |
| `apply()` | `apply(ConfigValues)` (applies the last `fetch()`) |
| `fetchAndApply({Duration? interval})` | `fetch()` + `apply()` combined |
| `getAll()` | `getMergedAll()` |
| `getString`/`getBool`/`getInt`/`getDouble` | `getValueAsString`/`Boolean`/`Long`/`Double` |
| `getSource(String)` | `getSource(String)` |
| `clearAll()` | `clearAll()` |
| `setDeveloperMode({required bool})` | `setDeveloperMode(boolean)` |
| `setCustomAttributes`/`getCustomAttributes` | same |
| `diagnostics()` | `AGConnectServicesConfig` reads + `getMergedAll().keys` |

## Troubleshooting: fetch succeeds but returns an empty map

`fetchAndApply()` completing without throwing means the native `fetch()`
succeeded — AGC simply returned no parameters. Work through these, in order:

1. **Are the parameters released?** In the AGC console, saving a parameter
   leaves it *to be released*; the SDK only sees it after you hit **Release**
   on the Remote Configuration → Parameters tab.
2. **Are you fetching as the app you edited?** Call `diagnostics()` and compare
   `appId`/`packageName` against the app selected in the console. A multi-app
   `agconnect-services.json` (one file, several flavours, `appInfos[]`) must
   override *all* per-app credentials for each flavour — `app_id`,
   `client_id`, `client_secret` and `api_key`. An entry carrying only `app_id`
   leaves the SDK authenticating as whichever app owns the root credentials,
   so the fetch returns *that* app's (usually empty) configuration, with no
   error. `apiKeySuffix`/`clientSecretSuffix` are reported so you can diff
   against the console without printing the credentials.
3. **Was the response a cache hit?** Without an `interval`, the SDK throttles
   to roughly 12 hours, so a fetch that happened before you published the
   parameter keeps being replayed. Pass `interval: Duration.zero` (and/or
   `setDeveloperMode(enabled: true)`) in development builds.

Every fetch logs to logcat, so you can tell a network round trip from a cache
hit by its elapsed time:

```sh
adb logcat -s HuaweiRemoteConfig:V
```

```text
I HuaweiRemoteConfig: fetchAndApply starting — SDK default interval (~12h cache), {packageName=com.example.app, appId=115308197, …}
I HuaweiRemoteConfig: fetchAndApply succeeded in 3ms, mergedAll keys=[]
W HuaweiRemoteConfig: AGC returned no parameters. Check that the parameters are RELEASED …
```

`3ms` is the throttle cache; a real round trip takes tens to hundreds of
milliseconds.

## Testing

`HuaweiRemoteConfig`'s constructor accepts an injectable `MethodChannel`, so
host apps can stub it in tests with
`TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler`
without any native platform involvement.
# huawei_remote_config
