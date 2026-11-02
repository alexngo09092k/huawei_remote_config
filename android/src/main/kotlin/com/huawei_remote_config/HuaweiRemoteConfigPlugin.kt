package com.huawei_remote_config

import android.content.Context
import android.util.Log
import androidx.annotation.NonNull
import com.huawei.agconnect.config.AGConnectServicesConfig
import com.huawei.agconnect.remoteconfig.AGConnectConfig
import com.huawei.agconnect.remoteconfig.ConfigValues
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/**
 * Flutter plugin bridging to Huawei AppGallery Connect's native Remote
 * Config SDK (`AGConnectConfig`).
 *
 * `fetch()`'s native `ConfigValues` result only supports look-up by a key
 * you already know (`containKey`/`getValueAsX`) — it cannot be enumerated —
 * so it is kept here as [pendingFetch] until `apply` (or `fetchAndApply`)
 * activates it; only [AGConnectConfig.getMergedAll] can ever be enumerated
 * and sent back to Dart as a full map.
 *
 * Every fetch logs to logcat under the [TAG] tag, including how long the
 * native call took and how many keys came back. Filter with:
 * `adb logcat -s HuaweiRemoteConfig:V`. A zero-key fetch that returns in a
 * couple of milliseconds is the SDK's throttle serving a cached (empty)
 * response, not a round trip to AGC — see the `diagnostics` method and the
 * README's troubleshooting section.
 */
class HuaweiRemoteConfigPlugin : FlutterPlugin, MethodCallHandler {
    private var channel: MethodChannel? = null
    private var applicationContext: Context? = null
    private var pendingFetch: ConfigValues? = null

    private val config: AGConnectConfig
        get() = AGConnectConfig.getInstance()

    override fun onAttachedToEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        applicationContext = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL_NAME)
        channel?.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        applicationContext = null
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        try {
            when (call.method) {
                "applyDefaults" -> applyDefaults(call, result)
                "fetch" -> fetch(call, result)
                "apply" -> apply(result)
                "fetchAndApply" -> fetchAndApply(call, result)
                "diagnostics" -> result.success(diagnostics())
                "getAll" -> result.success(config.mergedAll)
                "getString" -> result.success(config.getValueAsString(requireKey(call)))
                "getBool" -> result.success(config.getValueAsBoolean(requireKey(call)))
                "getInt" -> result.success(config.getValueAsLong(requireKey(call)))
                "getDouble" -> result.success(config.getValueAsDouble(requireKey(call)))
                "getSource" -> result.success(config.getSource(requireKey(call)).name)
                "clearAll" -> {
                    config.clearAll()
                    result.success(null)
                }
                "setDeveloperMode" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    config.setDeveloperMode(enabled)
                    Log.i(TAG, "developerMode=$enabled (throttling ${if (enabled) "disabled" else "enabled"})")
                    result.success(null)
                }
                "setCustomAttributes" -> {
                    @Suppress("UNCHECKED_CAST")
                    val attributes = call.argument<Map<String, String>>("attributes") ?: emptyMap()
                    config.setCustomAttributes(attributes)
                    result.success(null)
                }
                "getCustomAttributes" -> result.success(config.customAttributes)
                else -> result.notImplemented()
            }
        } catch (error: Exception) {
            Log.e(TAG, "${call.method} threw ${error.javaClass.name}: ${error.message}", error)
            result.error("native_error", error.message, describe(error))
        }
    }

    private fun applyDefaults(call: MethodCall, result: Result) {
        @Suppress("UNCHECKED_CAST")
        val defaults = call.argument<Map<String, Any>>("defaults") ?: emptyMap()
        config.applyDefault(defaults)
        Log.i(TAG, "applyDefaults keys=${defaults.keys.sorted()}")
        result.success(null)
    }

    private fun fetch(call: MethodCall, result: Result) {
        val interval = intervalSeconds(call)
        val startedAt = System.currentTimeMillis()
        logFetchStart("fetch", interval)
        val task = interval?.let { config.fetch(it) } ?: config.fetch()
        task
            .addOnSuccessListener { configValues ->
                pendingFetch = configValues
                Log.i(TAG, "fetch succeeded in ${elapsed(startedAt)}ms (pending apply)")
                result.success(null)
            }
            .addOnFailureListener { error ->
                logFetchFailure(error, startedAt)
                result.error("fetch_failed", error.message, describe(error))
            }
    }

    private fun apply(result: Result) {
        val fetched = pendingFetch ?: run {
            Log.w(TAG, "apply called with no pending fetch")
            result.error("no_pending_fetch", "Call fetch() before apply().", null)
            return
        }
        config.apply(fetched)
        pendingFetch = null
        Log.i(TAG, "apply done, mergedAll keys=${mergedKeys()}")
        result.success(null)
    }

    private fun fetchAndApply(call: MethodCall, result: Result) {
        val interval = intervalSeconds(call)
        val startedAt = System.currentTimeMillis()
        logFetchStart("fetchAndApply", interval)
        val task = interval?.let { config.fetch(it) } ?: config.fetch()
        task
            .addOnSuccessListener { configValues ->
                val fetchedIn = elapsed(startedAt)
                config.apply(configValues)
                pendingFetch = null
                val merged = config.mergedAll
                Log.i(TAG, "fetchAndApply succeeded in ${fetchedIn}ms, mergedAll keys=${merged.keys.sorted()}")
                if (merged.isEmpty()) {
                    Log.w(
                        TAG,
                        "AGC returned no parameters. Check that the parameters are RELEASED in the AGC console, " +
                            "that agconnect-services.json belongs to the app below, and that the fetch was not " +
                            "served from the SDK's throttle cache (pass a zero interval to force a round trip). " +
                            "Resolved app: ${diagnostics()}",
                    )
                }
                result.success(merged)
            }
            .addOnFailureListener { error ->
                logFetchFailure(error, startedAt)
                result.error("fetch_failed", error.message, describe(error))
            }
    }

    /**
     * A snapshot of which AGC app this process actually authenticates as,
     * read from the `agconnect-services.json` baked into the APK, plus the
     * keys currently applied.
     *
     * This is the fastest way to tell "the fetch worked but the console app I
     * edited is a different app" apart from "the fetch never reached AGC" —
     * the `appId`/`packageName` pair here must match the app selected in the
     * AGC console's Remote Configuration page.
     *
     * `api_key`/`client_secret` are credentials, so only a short suffix is
     * reported — enough to diff against the console, not enough to reuse.
     */
    private fun diagnostics(): Map<String, Any?> {
        val context = applicationContext
        val agc = context?.let { agcString(it) }
        return mapOf(
            "packageName" to context?.packageName,
            "appId" to agc?.invoke("client/app_id"),
            "clientId" to agc?.invoke("client/client_id"),
            "projectId" to agc?.invoke("client/project_id"),
            "productId" to agc?.invoke("client/product_id"),
            "configuredPackageName" to agc?.invoke("client/package_name"),
            "region" to agc?.invoke("region"),
            "gatewayUrl" to agc?.invoke("agcgw/url"),
            "apiKeySuffix" to agc?.invoke("client/api_key")?.takeLast(CREDENTIAL_SUFFIX_LENGTH),
            "clientSecretSuffix" to agc?.invoke("client/client_secret")?.takeLast(CREDENTIAL_SUFFIX_LENGTH),
            "appliedKeys" to mergedKeys(),
        )
    }

    /**
     * Reads a path out of `agconnect-services.json`, tolerating a missing
     * key or an AGC SDK that never initialised (an uninitialised AGC is
     * itself a finding worth logging, not a crash).
     */
    private fun agcString(context: Context): (String) -> String? {
        val servicesConfig = runCatching { AGConnectServicesConfig.fromContext(context) }
            .onFailure { Log.e(TAG, "AGConnectServicesConfig unavailable: ${it.javaClass.name}: ${it.message}") }
            .getOrNull()
        return { path -> servicesConfig?.let { runCatching { it.getString(path) }.getOrNull() } }
    }

    private fun mergedKeys(): List<String> = runCatching { config.mergedAll.keys.sorted() }.getOrDefault(emptyList())

    private fun logFetchStart(method: String, intervalSeconds: Long?) {
        val throttling = intervalSeconds?.let { "intervalSeconds=$it" } ?: "SDK default interval (~12h cache)"
        Log.i(TAG, "$method starting — $throttling, ${diagnostics()}")
    }

    private fun logFetchFailure(error: Throwable, startedAt: Long) {
        Log.e(
            TAG,
            "fetch failed after ${elapsed(startedAt)}ms: ${error.javaClass.name}: ${error.message}" +
                (error.cause?.let { " (cause: ${it.javaClass.name}: ${it.message})" } ?: ""),
            error,
        )
    }

    /** Native error metadata, forwarded to Dart as the platform error details. */
    private fun describe(error: Throwable): Map<String, String?> = mapOf(
        "type" to error.javaClass.name,
        "message" to error.message,
        "cause" to error.cause?.let { "${it.javaClass.name}: ${it.message}" },
    )

    private fun elapsed(startedAt: Long): Long = System.currentTimeMillis() - startedAt

    private fun intervalSeconds(call: MethodCall): Long? = call.argument<Int>("intervalSeconds")?.toLong()

    private fun requireKey(call: MethodCall): String =
        call.argument<String>("key") ?: throw IllegalArgumentException("Missing required argument 'key'.")

    companion object {
        private const val CHANNEL_NAME = "huawei_remote_config"

        /** logcat tag — filter with `adb logcat -s HuaweiRemoteConfig:V`. */
        private const val TAG = "HuaweiRemoteConfig"

        /** How many trailing characters of a credential are safe to log. */
        private const val CREDENTIAL_SUFFIX_LENGTH = 6
    }
}
