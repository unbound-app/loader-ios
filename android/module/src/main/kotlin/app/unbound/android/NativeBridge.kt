package app.unbound.android

import android.graphics.fonts.SystemFonts
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.widget.Toast
import java.io.File
import java.net.HttpURLConnection
import java.net.URL

object NativeBridge {
    private const val DEV_SERVER_PORT = 3000
    private const val DEV_SERVER_PROBE = "manifest.json"
    private const val EMULATOR_HOST = "10.0.2.2"
    private const val DEV_SERVER_PROBE_TIMEOUT_MS = 1500

    @JvmStatic
    external fun nativeInitialize(
        documents: String,
        modulesScript: String?,
        devtoolsScript: String?,
        origin: String,
        bytecodeVersion: Int,
        platformInfo: String,
    )

    @JvmStatic
    external fun nativeOnLoadJSBundle()

    @JvmStatic
    external fun nativeOnJSBundleLoaded()

    @JvmStatic
    external fun nativeDrainRuntimeWork(runtimePointer: Long)

    @JvmStatic
    external fun nativeGetBoolean(store: String, key: String, fallback: Boolean): Boolean

    @JvmStatic
    external fun nativeSetBoolean(store: String, key: String, value: Boolean)

    @JvmStatic
    fun scheduleRuntimeWork() {
        ReactRuntime.post { runtimePointer -> nativeDrainRuntimeWork(runtimePointer) }
    }

    @JvmStatic
    fun fetchText(url: String, timeoutMs: Int): String? = runCatching {
        val connection = URL(url).openConnection() as HttpURLConnection
        connection.connectTimeout = timeoutMs
        connection.readTimeout = timeoutMs
        connection.useCaches = false
        try {
            if (connection.responseCode != HttpURLConnection.HTTP_OK) return null
            connection.inputStream.bufferedReader().use { it.readText() }
        } finally {
            connection.disconnect()
        }
    }.getOrNull()

    @JvmStatic
    fun download(
        url: String,
        destination: String,
        headerKeys: Array<String>,
        headerValues: Array<String>,
    ): Array<String>? = runCatching {
        val connection = URL(url).openConnection() as HttpURLConnection
        connection.connectTimeout = 15_000
        connection.readTimeout = 30_000
        connection.useCaches = false
        headerKeys.zip(headerValues).forEach { (key, value) -> connection.setRequestProperty(key, value) }

        try {
            val status = connection.responseCode
            if (status == HttpURLConnection.HTTP_OK) {
                val target = File(destination)
                target.parentFile?.mkdirs()
                val staging = File("$destination.download")
                connection.inputStream.use { input -> staging.outputStream().use { input.copyTo(it) } }
                if (!staging.renameTo(target)) {
                    staging.delete()
                    return null
                }
            } else if (status != HttpURLConnection.HTTP_NOT_MODIFIED) {
                Logger.error("updater", "Bundle download returned HTTP $status for $url")
                return null
            }
            arrayOf(status.toString(), connection.getHeaderField("etag") ?: "")
        } finally {
            connection.disconnect()
        }
    }.onFailure { Logger.error("updater", "Bundle download failed: $it") }.getOrNull()

    @JvmStatic
    fun devServerURL(): String? {
        if (!isEmulator()) return null

        val url = "http://$EMULATOR_HOST:$DEV_SERVER_PORT/"
        val serving = runCatching {
            val connection = URL(url + DEV_SERVER_PROBE).openConnection() as HttpURLConnection
            connection.requestMethod = "HEAD"
            connection.connectTimeout = DEV_SERVER_PROBE_TIMEOUT_MS
            connection.readTimeout = DEV_SERVER_PROBE_TIMEOUT_MS
            try {
                connection.responseCode == HttpURLConnection.HTTP_OK
            } finally {
                connection.disconnect()
            }
        }.getOrDefault(false)

        if (!serving) {
            Logger.info("updater", "Emulator: $url is not reachable; using the default update URL.")
            return null
        }

        Logger.info("updater", "Emulator: using $url.")
        return url
    }

    @JvmStatic
    fun availableFonts(): Array<String> = runCatching {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return emptyArray()
        SystemFonts.getAvailableFonts()
            .mapNotNull { it.file?.nameWithoutExtension }
            .distinct()
            .sorted()
            .toTypedArray()
    }.getOrDefault(emptyArray())

    @JvmStatic
    fun alert(message: String) {
        Handler(Looper.getMainLooper()).post {
            val context = Platform.application() ?: return@post
            Toast.makeText(context, message, Toast.LENGTH_LONG).show()
        }
    }

    @JvmStatic
    fun onBundleExecuted() {
        Recovery.bundleExecuted = true
        Logger.info("default", "Bundle executed.")
    }

    private fun isEmulator(): Boolean =
        Build.HARDWARE.contains("ranchu") ||
            Build.HARDWARE.contains("goldfish") ||
            Build.FINGERPRINT.contains("generic") ||
            Build.PRODUCT.contains("sdk")
}
