package app.unbound.android

import android.content.ContentResolver
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.widget.ImageView
import java.io.ByteArrayOutputStream
import java.io.InputStream
import java.lang.ref.WeakReference
import java.net.URL
import java.util.LinkedHashMap
import java.util.WeakHashMap
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.ThreadFactory
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit
import javax.net.ssl.HttpsURLConnection

internal object NativeImageLoader {
    private const val MAX_SOURCE_LENGTH = 2048
    private const val MAX_IMAGE_BYTES = 16 * 1024 * 1024
    private const val MAX_SOURCE_DIMENSION = 65_536
    private const val MAX_IMAGE_DIMENSION = 2048
    private const val MAX_CACHE_BYTES = 24 * 1024 * 1024

    private val lock = Any()
    private val requests = WeakHashMap<ImageView, Long>()
    private val cache = LinkedHashMap<String, Bitmap>(16, 0.75f, true)
    private var nextRequest = 0L
    private var cachedBytes = 0
    private val executor = ThreadPoolExecutor(
        2,
        2,
        30,
        TimeUnit.SECONDS,
        ArrayBlockingQueue(64),
        ThreadFactory { task -> Thread(task, "unbound-native-image").apply { isDaemon = true } },
        ThreadPoolExecutor.DiscardPolicy(),
    )

    fun load(view: ImageView, source: String) {
        require(source.length <= MAX_SOURCE_LENGTH)
        if (source.isEmpty()) {
            clear(view)
            return
        }
        require(isSupportedSource(source))

        val request = synchronized(lock) {
            val identifier = ++nextRequest
            requests[view] = identifier
            identifier
        }
        val cached = synchronized(lock) { cache[source] }
        if (cached != null) {
            view.setImageBitmap(cached)
            return
        }

        view.setImageDrawable(null)
        val imageReference = WeakReference(view)
        val resolver = view.context.applicationContext.contentResolver
        executor.execute {
            val bitmap = try {
                readBitmap(resolver, Uri.parse(source))
            } catch (_: Exception) {
                null
            } ?: return@execute
            synchronized(lock) {
                cache.put(source, bitmap)?.let { cachedBytes -= it.byteCount }
                cachedBytes += bitmap.byteCount
                trimCache()
            }
            imageReference.get()?.post {
                val image = imageReference.get() ?: return@post
                val current = synchronized(lock) { requests[image] == request }
                if (current) image.setImageBitmap(bitmap)
            }
        }
    }

    fun clear(view: ImageView) {
        synchronized(lock) {
            requests[view] = ++nextRequest
        }
        view.setImageDrawable(null)
    }

    internal fun isSupportedSource(source: String): Boolean {
        if (source.isEmpty() || source.length > MAX_SOURCE_LENGTH) return false
        val uri = Uri.parse(source)
        return when (uri.scheme?.lowercase()) {
            "content" -> !uri.authority.isNullOrEmpty()
            "file" -> !uri.path.isNullOrEmpty()
            "https" -> {
                val host = uri.host?.lowercase() ?: return false
                val trustedHost = host == "discord.com" ||
                    host.endsWith(".discord.com") ||
                    host == "discordapp.com" ||
                    host.endsWith(".discordapp.com") ||
                    host == "discordapp.net" ||
                    host.endsWith(".discordapp.net")
                trustedHost && (uri.port == -1 || uri.port == 443)
            }
            else -> false
        }
    }

    private fun readBitmap(resolver: ContentResolver, uri: Uri): Bitmap? {
        val bytes = when (uri.scheme?.lowercase()) {
            "content", "file" -> resolver.openInputStream(uri)?.use(::readBounded)
            "https" -> readHttps(uri)
            else -> null
        } ?: return null
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
        if (bounds.outWidth > MAX_SOURCE_DIMENSION || bounds.outHeight > MAX_SOURCE_DIMENSION) return null
        val sample = sampleSize(bounds.outWidth, bounds.outHeight)
        return BitmapFactory.decodeByteArray(
            bytes,
            0,
            bytes.size,
            BitmapFactory.Options().apply { inSampleSize = sample },
        )
    }

    private fun readHttps(uri: Uri): ByteArray? {
        if (!isSupportedSource(uri.toString())) return null
        val connection = URL(uri.toString()).openConnection() as? HttpsURLConnection ?: return null
        connection.connectTimeout = 5_000
        connection.readTimeout = 8_000
        connection.useCaches = true
        connection.instanceFollowRedirects = false
        return try {
            if (connection.responseCode != HttpsURLConnection.HTTP_OK) return null
            if (connection.contentLengthLong > MAX_IMAGE_BYTES) return null
            connection.inputStream.use(::readBounded)
        } finally {
            connection.disconnect()
        }
    }

    private fun readBounded(input: InputStream): ByteArray? {
        val output = ByteArrayOutputStream()
        val buffer = ByteArray(8192)
        var total = 0
        while (true) {
            val count = input.read(buffer)
            if (count < 0) break
            total += count
            if (total > MAX_IMAGE_BYTES) return null
            output.write(buffer, 0, count)
        }
        return output.toByteArray()
    }

    private fun sampleSize(width: Int, height: Int): Int {
        var sample = 1
        while (width / sample > MAX_IMAGE_DIMENSION || height / sample > MAX_IMAGE_DIMENSION) {
            sample *= 2
        }
        return sample
    }

    private fun trimCache() {
        val iterator = cache.entries.iterator()
        while (cachedBytes > MAX_CACHE_BYTES && iterator.hasNext()) {
            cachedBytes -= iterator.next().value.byteCount
            iterator.remove()
        }
    }
}
