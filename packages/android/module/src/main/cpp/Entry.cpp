#include "AndroidLoader.h"
#include "JniEnvironment.h"
#include "LoaderLog.h"
#include "LoaderPreload.h"

#include <android/log.h>
#include <jni.h>

using namespace unbound::android;

static const char *const kBridgeClass = "app/unbound/android/NativeBridge";

static JavaCallbacks gCallbacks;

static int androidPriority(loader::LogLevel level)
{
    switch (level)
    {
        case loader::LogLevel::Debug:
            return ANDROID_LOG_DEBUG;
        case loader::LogLevel::Info:
            return ANDROID_LOG_INFO;
        case loader::LogLevel::Warning:
            return ANDROID_LOG_WARN;
        case loader::LogLevel::Error:
            return ANDROID_LOG_ERROR;
    }
    return ANDROID_LOG_INFO;
}

static void writeLog(loader::LogLevel level, const std::string &category, const std::string &message)
{
    __android_log_print(androidPriority(level), "Unbound", "[%s] %s", category.c_str(),
                        message.c_str());
}

static void nativeInitialize(JNIEnv *env, jclass, jstring documents, jstring modulesScript,
                             jstring devtoolsScript, jstring origin, jint bytecodeVersion,
                             jstring platformInfo)
{
    LoaderConfiguration configuration;
    configuration.documents       = toStdString(env, documents);
    configuration.modulesScript   = toOptionalString(env, modulesScript);
    configuration.devtoolsScript  = toOptionalString(env, devtoolsScript);
    configuration.origin          = toStdString(env, origin);
    configuration.bytecodeVersion = static_cast<uint32_t>(bytecodeVersion);

    nlohmann::json info = nlohmann::json::parse(toStdString(env, platformInfo), nullptr, false);
    if (info.is_object())
    {
        configuration.platformInfo = std::move(info);
    }

    auto loader = std::make_shared<AndroidLoader>(std::move(configuration), gCallbacks);
    loader->start();
    setCurrentLoader(loader);
    loader::log(loader::LogLevel::Info, "default", "Native loader initialized.");
}

static void nativeOnLoadJSBundle(JNIEnv *, jclass)
{
    if (auto loader = currentLoader())
    {
        loader->onLoadJSBundle();
    }
}

static void nativeOnJSBundleLoaded(JNIEnv *, jclass)
{
    if (auto loader = currentLoader())
    {
        loader->onJSBundleLoaded();
    }
}

static void nativeDrainRuntimeWork(JNIEnv *, jclass, jlong runtimePointer)
{
    auto loader = currentLoader();
    if (!loader || runtimePointer == 0)
    {
        return;
    }

    auto *runtime = reinterpret_cast<facebook::jsi::Runtime *>(runtimePointer);
    loader->drainRuntimeWork(*runtime);
}

static void nativeDrainMainWork(JNIEnv *, jclass)
{
    if (auto loader = currentLoader())
    {
        loader->drainMainWork();
    }
}

static jboolean nativeGetBoolean(JNIEnv *env, jclass, jstring store, jstring key, jboolean fallback)
{
    auto loader = currentLoader();
    if (!loader)
    {
        return fallback;
    }
    return loader->settings().getBoolean(toStdString(env, store), toStdString(env, key), fallback);
}

static void nativeSetBoolean(JNIEnv *env, jclass, jstring store, jstring key, jboolean value)
{
    auto loader = currentLoader();
    if (!loader)
    {
        return;
    }
    loader->settings().set(toStdString(env, store), toStdString(env, key), static_cast<bool>(value));
    loader->settings().save();
}

static jstring nativeSettingJSON(JNIEnv *env, jclass, jstring store, jstring key)
{
    auto loader = currentLoader();
    if (!loader)
    {
        return nullptr;
    }
    std::optional<nlohmann::json> value =
        loader->settings().get(toStdString(env, store), toStdString(env, key));
    return value ? toJavaString(env, loader::toJSON(*value)) : nullptr;
}

static jstring nativeFontsJSON(JNIEnv *env, jclass)
{
    auto loader = currentLoader();
    return toJavaString(env, loader ? loader->fontsJSON() : "[]");
}

static jstring nativeThemeColorsJSON(JNIEnv *env, jclass, jstring themeId)
{
    auto loader = currentLoader();
    return toJavaString(env, loader ? loader->themeColorsJSON(toStdString(env, themeId)) : "{}");
}

static void nativePrepareAddons(JNIEnv *, jclass)
{
    if (auto loader = currentLoader())
    {
        loader->onAddonsPrepared();
    }
}

static bool cacheCallbacks(JNIEnv *env, jclass bridge)
{
    gCallbacks.bridgeClass     = static_cast<jclass>(env->NewGlobalRef(bridge));
    gCallbacks.scheduleRuntime = env->GetStaticMethodID(bridge, "scheduleRuntimeWork", "()V");
    gCallbacks.scheduleMain    = env->GetStaticMethodID(bridge, "scheduleMainWork", "()V");
    gCallbacks.isMainThread    = env->GetStaticMethodID(bridge, "isMainThread", "()Z");
    gCallbacks.lookupViews = env->GetStaticMethodID(
        bridge, "lookupViews", "(Ljava/lang/String;)Ljava/lang/String;");
    gCallbacks.snapshotViews = env->GetStaticMethodID(
        bridge, "snapshotViews", "(Ljava/lang/String;)Ljava/lang/String;");
    gCallbacks.fetchText =
        env->GetStaticMethodID(bridge, "fetchText", "(Ljava/lang/String;I)Ljava/lang/String;");
    gCallbacks.download = env->GetStaticMethodID(
        bridge, "download",
        "(Ljava/lang/String;Ljava/lang/String;[Ljava/lang/String;[Ljava/lang/String;)[Ljava/lang/"
        "String;");
    gCallbacks.devServerURL = env->GetStaticMethodID(bridge, "devServerURL", "()Ljava/lang/String;");
    gCallbacks.availableFonts =
        env->GetStaticMethodID(bridge, "availableFonts", "()[Ljava/lang/String;");
    gCallbacks.alert = env->GetStaticMethodID(bridge, "alert", "(Ljava/lang/String;)V");
    gCallbacks.onBundleExecuted = env->GetStaticMethodID(bridge, "onBundleExecuted", "()V");

    return !clearPendingException(env) && gCallbacks.scheduleRuntime && gCallbacks.scheduleMain &&
           gCallbacks.isMainThread && gCallbacks.lookupViews && gCallbacks.snapshotViews &&
           gCallbacks.fetchText &&
           gCallbacks.download && gCallbacks.devServerURL && gCallbacks.availableFonts &&
           gCallbacks.alert && gCallbacks.onBundleExecuted;
}

extern "C" JNIEXPORT jint JNI_OnLoad(JavaVM *vm, void *)
{
    setJavaVM(vm);
    loader::setLogSink(writeLog);

    JNIEnv *env = nullptr;
    if (vm->GetEnv(reinterpret_cast<void **>(&env), JNI_VERSION_1_6) != JNI_OK)
    {
        return JNI_ERR;
    }

    LocalClass bridge(env, env->FindClass(kBridgeClass));
    if (!bridge.get())
    {
        clearPendingException(env);
        return JNI_ERR;
    }

    static const JNINativeMethod methods[] = {
        {"nativeInitialize",
         "(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;ILjava/lang/String;)V",
         reinterpret_cast<void *>(nativeInitialize)},
        {"nativeOnLoadJSBundle", "()V", reinterpret_cast<void *>(nativeOnLoadJSBundle)},
        {"nativeOnJSBundleLoaded", "()V", reinterpret_cast<void *>(nativeOnJSBundleLoaded)},
        {"nativeDrainRuntimeWork", "(J)V", reinterpret_cast<void *>(nativeDrainRuntimeWork)},
        {"nativeDrainMainWork", "()V", reinterpret_cast<void *>(nativeDrainMainWork)},
        {"nativeGetBoolean", "(Ljava/lang/String;Ljava/lang/String;Z)Z",
         reinterpret_cast<void *>(nativeGetBoolean)},
        {"nativeSetBoolean", "(Ljava/lang/String;Ljava/lang/String;Z)V",
         reinterpret_cast<void *>(nativeSetBoolean)},
        {"nativeSettingJSON", "(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;",
         reinterpret_cast<void *>(nativeSettingJSON)},
        {"nativeFontsJSON", "()Ljava/lang/String;", reinterpret_cast<void *>(nativeFontsJSON)},
        {"nativeThemeColorsJSON", "(Ljava/lang/String;)Ljava/lang/String;",
         reinterpret_cast<void *>(nativeThemeColorsJSON)},
        {"nativePrepareAddons", "()V", reinterpret_cast<void *>(nativePrepareAddons)},
    };

    if (env->RegisterNatives(bridge.get(), methods, sizeof(methods) / sizeof(methods[0])) != JNI_OK ||
        !cacheCallbacks(env, bridge.get()))
    {
        clearPendingException(env);
        return JNI_ERR;
    }

    return JNI_VERSION_1_6;
}
