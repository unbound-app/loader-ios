#include "AndroidLoader.h"

#include "JniEnvironment.h"
#include "LoaderAddons.h"
#include "LoaderFiles.h"
#include "LoaderLog.h"
#include "NativePlatformBridge.h"

#include <chrono>
#include <thread>

namespace unbound::android
{
    namespace jsi = facebook::jsi;

    static std::mutex                     gLoaderMutex;
    static std::shared_ptr<AndroidLoader> gLoader;

    std::shared_ptr<AndroidLoader> currentLoader()
    {
        std::lock_guard<std::mutex> lock(gLoaderMutex);
        return gLoader;
    }

    void setCurrentLoader(std::shared_ptr<AndroidLoader> loader)
    {
        std::lock_guard<std::mutex> lock(gLoaderMutex);
        gLoader = std::move(loader);
    }

    AndroidLoader::AndroidLoader(LoaderConfiguration configuration, JavaCallbacks callbacks)
        : configuration_(std::move(configuration)), callbacks_(callbacks),
          settings_(loader::joinPath(configuration_.documents, "settings.json"))
    {
    }

    void AndroidLoader::start()
    {
        loader::createDirectories(configuration_.documents);
        settings_.load();

        updater_ = std::make_unique<loader::BundleUpdater>(
            configuration_.documents, loader::updaterSettings(settings_),
            [this](const std::string &url, double timeout) { return fetchText(url, timeout); },
            [this](const std::string &url, const std::string &destination,
                   const std::map<std::string, std::string> &headers) {
                return download(url, destination, headers);
            });
        pipeline_ = std::make_unique<loader::LoaderPipeline>(shared_from_this(), settings_, *updater_);
    }

    loader::SettingsStore &AndroidLoader::settings()
    {
        return settings_;
    }

    void AndroidLoader::onLoadJSBundle()
    {
        settings_.load();
        pipeline_->prepare();
        runOnRuntime([this](jsi::Runtime &runtime) { pipeline_->injectModulesPatch(runtime); });
    }

    void AndroidLoader::onJSBundleLoaded()
    {
        pipeline_->enqueueBundle();
    }

    void AndroidLoader::drainRuntimeWork(jsi::Runtime &runtime)
    {
        std::deque<std::function<void(jsi::Runtime &)>> work;
        {
            std::lock_guard<std::mutex> lock(queueMutex_);
            work.swap(queue_);
        }

        for (auto &item : work)
        {
            try
            {
                item(runtime);
            }
            catch (const std::exception &error)
            {
                loader::log(loader::LogLevel::Error, "default",
                            std::string("Runtime work failed: ") + error.what());
            }
            catch (...)
            {
                loader::log(loader::LogLevel::Error, "default", "Runtime work failed.");
            }
        }
    }

    void AndroidLoader::runOnRuntime(std::function<void(jsi::Runtime &)> work)
    {
        {
            std::lock_guard<std::mutex> lock(queueMutex_);
            queue_.push_back(std::move(work));
        }

        JNIEnv *env = currentEnvironment();
        if (!env)
        {
            return;
        }
        env->CallStaticVoidMethod(callbacks_.bridgeClass, callbacks_.scheduleRuntime);
        clearPendingException(env);
    }

    void AndroidLoader::runAfter(double seconds, std::function<void()> work)
    {
        std::thread([seconds, work = std::move(work)]() {
            std::this_thread::sleep_for(std::chrono::duration<double>(seconds));
            work();
        }).detach();
    }

    void AndroidLoader::runInBackground(std::function<void()> work)
    {
        std::thread(std::move(work)).detach();
    }

    std::optional<std::string> AndroidLoader::resource(const std::string &name)
    {
        if (name == "modules")
        {
            return configuration_.modulesScript;
        }
        if (name == "devtools")
        {
            return configuration_.devtoolsScript;
        }
        return std::nullopt;
    }

    std::optional<std::string> AndroidLoader::resolveUpdateURL()
    {
        std::optional<nlohmann::json> configured = settings_.get("unbound", "loader.update.url");
        if (configured && configured->is_string() && !configured->get<std::string>().empty())
        {
            return configured->get<std::string>();
        }

        JNIEnv *env = currentEnvironment();
        if (!env)
        {
            return std::nullopt;
        }

        auto url = static_cast<jstring>(
            env->CallStaticObjectMethod(callbacks_.bridgeClass, callbacks_.devServerURL));
        if (clearPendingException(env) || !url)
        {
            return std::nullopt;
        }

        std::string value = toStdString(env, url);
        env->DeleteLocalRef(url);
        return value;
    }

    uint32_t AndroidLoader::runtimeBytecodeVersion()
    {
        return configuration_.bytecodeVersion;
    }

    loader::PreloadPayload AndroidLoader::preloadPayload()
    {
        loader::PreloadPayload payload;
        payload.settings = settings_.serialize();
        {
            std::lock_guard<std::mutex> lock(addonsMutex_);
            payload.plugins = loader::toJSON(plugins_);
            payload.themes  = loader::toJSON(themes_);
            payload.fonts   = loader::toJSON(fonts_);
        }
        payload.availableFonts = loader::toJSON(availableFonts());
        payload.origin         = configuration_.origin;
        payload.version        = UNBOUND_VERSION;
        return payload;
    }

    void AndroidLoader::installNativeModules(jsi::Runtime &runtime)
    {
        const nlohmann::json info = configuration_.platformInfo;
        auto                 text = [info](const char *key) {
            return [info, key]() { return info.value(key, std::string()); };
        };
        auto flag = [info](const char *key) { return [info, key]() { return info.value(key, false); }; };

        auto provider                 = std::make_shared<loader::NativePlatformProvider>();
        provider->platform            = "android";
        provider->deviceModel         = text("deviceModel");
        provider->osVersion           = text("osVersion");
        provider->isJailbroken        = flag("isRooted");
        provider->isSystemApp         = flag("isSystemApp");
        provider->isVerifiedBuild     = flag("isVerifiedBuild");
        provider->entitlements        = []() { return nlohmann::json::object(); };
        provider->entitlementsAsPlist = []() { return std::string(); };
        provider->appSource           = text("appSource");
        loader::installNativePlatform(runtime, provider);
    }

    void AndroidLoader::onAddonsPrepared()
    {
        nlohmann::json plugins = loader::scanPlugins(configuration_.documents);
        nlohmann::json themes  = loader::scanThemes(configuration_.documents);
        nlohmann::json fonts   = loader::scanFonts(configuration_.documents, nullptr);

        std::lock_guard<std::mutex> lock(addonsMutex_);
        plugins_ = std::move(plugins);
        themes_  = std::move(themes);
        fonts_   = std::move(fonts);
    }

    void AndroidLoader::onBundleExecuted()
    {
        JNIEnv *env = currentEnvironment();
        if (!env)
        {
            return;
        }
        env->CallStaticVoidMethod(callbacks_.bridgeClass, callbacks_.onBundleExecuted);
        clearPendingException(env);
    }

    void AndroidLoader::alert(const std::string &message)
    {
        JNIEnv *env = currentEnvironment();
        if (!env)
        {
            return;
        }
        jstring text = toJavaString(env, message);
        env->CallStaticVoidMethod(callbacks_.bridgeClass, callbacks_.alert, text);
        clearPendingException(env);
        env->DeleteLocalRef(text);
    }

    std::optional<std::string> AndroidLoader::fetchText(const std::string &url, double timeoutSeconds)
    {
        JNIEnv *env = currentEnvironment();
        if (!env)
        {
            return std::nullopt;
        }

        jstring javaURL = toJavaString(env, url);
        auto    result  = static_cast<jstring>(env->CallStaticObjectMethod(
            callbacks_.bridgeClass, callbacks_.fetchText, javaURL,
            static_cast<jint>(timeoutSeconds * 1000)));
        env->DeleteLocalRef(javaURL);
        if (clearPendingException(env) || !result)
        {
            return std::nullopt;
        }

        std::string text = toStdString(env, result);
        env->DeleteLocalRef(result);
        return text;
    }

    std::optional<loader::DownloadResult> AndroidLoader::download(
        const std::string &url, const std::string &destination,
        const std::map<std::string, std::string> &headers)
    {
        JNIEnv *env = currentEnvironment();
        if (!env)
        {
            return std::nullopt;
        }

        std::vector<std::string> keys;
        std::vector<std::string> values;
        for (const auto &[key, value] : headers)
        {
            keys.push_back(key);
            values.push_back(value);
        }

        jstring      javaURL         = toJavaString(env, url);
        jstring      javaDestination = toJavaString(env, destination);
        jobjectArray javaKeys        = toJavaStringArray(env, keys);
        jobjectArray javaValues      = toJavaStringArray(env, values);

        auto response = static_cast<jobjectArray>(env->CallStaticObjectMethod(
            callbacks_.bridgeClass, callbacks_.download, javaURL, javaDestination, javaKeys,
            javaValues));

        env->DeleteLocalRef(javaURL);
        env->DeleteLocalRef(javaDestination);
        env->DeleteLocalRef(javaKeys);
        env->DeleteLocalRef(javaValues);

        if (clearPendingException(env) || !response || env->GetArrayLength(response) < 2)
        {
            return std::nullopt;
        }

        auto status = static_cast<jstring>(env->GetObjectArrayElement(response, 0));
        auto etag   = static_cast<jstring>(env->GetObjectArrayElement(response, 1));

        loader::DownloadResult result;
        result.status = std::stoi(toStdString(env, status));
        result.etag   = toStdString(env, etag);

        env->DeleteLocalRef(status);
        env->DeleteLocalRef(etag);
        env->DeleteLocalRef(response);
        return result;
    }

    nlohmann::json AndroidLoader::availableFonts()
    {
        nlohmann::json families = nlohmann::json::array();
        JNIEnv        *env      = currentEnvironment();
        if (!env)
        {
            return families;
        }

        auto names = static_cast<jobjectArray>(
            env->CallStaticObjectMethod(callbacks_.bridgeClass, callbacks_.availableFonts));
        if (clearPendingException(env) || !names)
        {
            return families;
        }

        jsize count = env->GetArrayLength(names);
        for (jsize index = 0; index < count; index++)
        {
            auto name = static_cast<jstring>(env->GetObjectArrayElement(names, index));
            families.push_back(toStdString(env, name));
            env->DeleteLocalRef(name);
        }
        env->DeleteLocalRef(names);
        return families;
    }
}
