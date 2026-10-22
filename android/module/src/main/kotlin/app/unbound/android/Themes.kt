package app.unbound.android

import io.github.libxposed.api.XposedInterface
import io.github.libxposed.api.XposedInterface.ExceptionMode
import org.json.JSONObject
import java.lang.reflect.Method

object Themes {
    private const val THEME_PACKAGE = "com.discord.theme"
    private val THEME_CLASSES = listOf(
        "DarkTheme",
        "LightTheme",
        "AshTheme",
        "OnyxTheme",
        "DarkThemeExperiment",
        "LightThemeExperiment",
        "AshThemeExperiment",
        "OnyxThemeExperiment",
    )

    fun install(xposed: XposedInterface, classLoader: ClassLoader) {
        if (Recovery.isEnabled()) return

        val applied = NativeBridge.nativeSettingJSON("themes", "applied")
            ?.let { runCatching { JSONObject("{\"id\":$it}").optString("id") }.getOrNull() }
            ?.takeIf { it.isNotEmpty() } ?: return

        NativeBridge.nativePrepareAddons()
        val colors = JSONObject(NativeBridge.nativeThemeColorsJSON(applied))
        if (colors.length() == 0) {
            Logger.info("themes", "Theme $applied has no native semantic colors.")
            return
        }

        val themeClasses = THEME_CLASSES.mapNotNull { name ->
            runCatching { classLoader.loadClass("$THEME_PACKAGE.$name") }.getOrNull()
        }

        var hooked = 0
        for (key in colors.keys()) {
            val color = colors.getLong(key).toInt()
            val getter = getterName(key)
            for (themeClass in themeClasses) {
                val method = themeClass.findColorGetter(getter) ?: continue
                xposed.hook(method)
                    .setExceptionMode(ExceptionMode.PROTECTIVE)
                    .intercept { color }
                hooked++
            }
        }

        Logger.info("themes", "Applied theme $applied to $hooked native color getters.")
    }

    private fun getterName(key: String): String =
        "get" + key.lowercase().split('_', '-', '.')
            .filter { it.isNotEmpty() }
            .joinToString("") { part -> part.replaceFirstChar { it.uppercase() } }

    private fun Class<*>.findColorGetter(name: String): Method? =
        runCatching { getDeclaredMethod(name) }.getOrNull()
            ?.takeIf { it.returnType == Integer.TYPE }
}
