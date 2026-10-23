package app.unbound.android

import java.lang.ref.WeakReference
import java.lang.reflect.Method

object ReactRuntime {
    private val lock = Any()
    private var instance: WeakReference<Any>? = null
    private val pending = ArrayList<(Long) -> Unit>()

    private var javaScriptContextMethod: Method? = null
    private var queueConfigurationMethod: Method? = null

    fun attach(reactInstance: Any) {
        val queued: List<(Long) -> Unit>
        synchronized(lock) {
            instance = WeakReference(reactInstance)
            javaScriptContextMethod = reactInstance.javaClass.findMethod("getJavaScriptContext")
            queueConfigurationMethod = reactInstance.javaClass.findMethod("getReactQueueConfiguration")
            queued = ArrayList(pending)
            pending.clear()
        }
        queued.forEach { post(it) }
    }

    fun post(work: (Long) -> Unit) {
        val target = synchronized(lock) {
            val current = instance?.get()
            if (current == null) {
                pending.add(work)
                return
            }
            current
        }

        val queueThread = runCatching {
            val configuration = queueConfigurationMethod!!.invoke(target)!!
            configuration.javaClass.findMethod("getJSQueueThread")!!.invoke(configuration)!!
        }.onFailure { Logger.error("runtime", "JS queue thread is unavailable", it) }.getOrNull() ?: return

        val runnable = Runnable {
            val pointer = runCatching { javaScriptContextMethod!!.invoke(target) as Long }
                .onFailure { Logger.error("runtime", "JS runtime pointer is unavailable", it) }
                .getOrNull() ?: return@Runnable
            work(pointer)
        }

        runCatching {
            queueThread.javaClass.findMethod("runOnQueue", Runnable::class.java)!!.invoke(queueThread, runnable)
        }.onFailure { Logger.error("runtime", "Failed to schedule work on the JS thread", it) }
    }

    private fun Class<*>.findMethod(name: String, vararg parameters: Class<*>): Method? {
        var current: Class<*>? = this
        while (current != null) {
            runCatching { current.getDeclaredMethod(name, *parameters) }.getOrNull()?.let {
                it.isAccessible = true
                return it
            }
            current = current.superclass
        }
        return interfaces.firstNotNullOfOrNull { candidate ->
            runCatching { candidate.getMethod(name, *parameters) }.getOrNull()
        }
    }
}
