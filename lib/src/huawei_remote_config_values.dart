/// An immutable snapshot of Huawei AppGallery Connect Remote Config values,
/// as returned by [HuaweiRemoteConfig.fetch], [HuaweiRemoteConfig.fetchAndApply]
/// and [HuaweiRemoteConfig.getAll].
///
/// Native `AGConnectConfig.getMergedAll()` returns a
/// `Map<String, Object>` whose values are `Boolean`/`Double`/`Long`/`String`/
/// `byte[]`. Across the method channel these arrive as `bool`/`double`/`int`/
/// `String`/`Uint8List`. This class only keeps entries with a non-null key
/// and value, discarding the rest, so callers never have to null-check the
/// map itself.
class HuaweiRemoteConfigValues {
  /// Builds a snapshot from [raw], the `Map<Object?, Object?>` sent across
  /// the platform channel by `getMergedAll()`, keeping only entries with a
  /// non-null key and value.
  HuaweiRemoteConfigValues(Map<Object?, Object?> raw)
    : _values = {
        for (final entry in raw.entries)
          if (entry.key != null && entry.value != null) entry.key.toString(): entry.value as Object,
      };

  final Map<String, Object> _values;

  /// All keys known to this snapshot.
  Set<String> get keys => _values.keys.toSet();

  /// The raw values in this snapshot, keyed by remote config key.
  ///
  /// Value types are whichever of `bool`/`double`/`int`/`String`/`Uint8List`
  /// the native side sent for that key.
  Map<String, Object> asMap() => Map.unmodifiable(_values);

  /// Returns the value for [key] as a [String], or `null` if it is absent or
  /// not a [String].
  String? getString(String key) {
    final value = _values[key];
    return value is String ? value : null;
  }

  /// Returns the value for [key] as a [bool], or `null` if it is absent or
  /// not a [bool].
  bool? getBool(String key) {
    final value = _values[key];
    return value is bool ? value : null;
  }

  /// Returns the value for [key] as an [int], or `null` if it is absent or
  /// not numeric.
  ///
  /// Native values for integral keys are Java `Long`s, which arrive as Dart
  /// `int`; this also accepts a `double` with no fractional part, since a
  /// `String`-typed remote value coerced upstream could otherwise be lost.
  int? getInt(String key) {
    final value = _values[key];
    if (value is int) return value;
    if (value is double && value == value.roundToDouble()) return value.round();
    return null;
  }

  /// Returns the value for [key] as a [double], or `null` if it is absent or
  /// not numeric.
  double? getDouble(String key) {
    final value = _values[key];
    if (value is double) return value;
    if (value is int) return value.toDouble();
    return null;
  }

  @override
  String toString() => 'HuaweiRemoteConfigValues($_values)';
}
