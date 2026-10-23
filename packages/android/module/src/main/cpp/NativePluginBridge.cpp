#include "NativePluginBridge.h"

#include "JniEnvironment.h"
#include "NativePlatformBridge.h"
#include "NativePluginVersion.h"

#include <algorithm>
#include <cmath>
#include <memory>
#include <stdexcept>

namespace unbound::android
{
    namespace jsi = facebook::jsi;

    static constexpr size_t kMaximumQueryBytes = 8192;
    static constexpr size_t kMaximumQueryAttributes = 32;
    static constexpr size_t kMaximumQueryStringBytes = 256;

    static int boundedInteger(jsi::Runtime &runtime, const jsi::Object &query, const char *name,
                              int fallback, int maximum)
    {
        jsi::Value value = query.getProperty(runtime, name);
        if (!value.isNumber())
        {
            return fallback;
        }

        double number = value.getNumber();
        if (!std::isfinite(number) || std::floor(number) != number)
        {
            throw std::invalid_argument(std::string(name) + " must be a finite integer");
        }

        if (number < 1)
        {
            return 1;
        }
        if (number > maximum)
        {
            return maximum;
        }
        return static_cast<int>(number);
    }

    static nlohmann::json scalarAttributes(jsi::Runtime &runtime, const jsi::Object &query)
    {
        jsi::Value value = query.getProperty(runtime, "attributes");
        if (!value.isObject() || value.isNull())
        {
            return nlohmann::json::object();
        }

        jsi::Object object = value.asObject(runtime);
        if (object.isArray(runtime))
        {
            throw std::invalid_argument("attributes must be a plain object");
        }

        jsi::Array names = object.getPropertyNames(runtime);
        if (names.size(runtime) > kMaximumQueryAttributes)
        {
            throw std::invalid_argument("attributes exceeds the maximum number of entries");
        }

        nlohmann::json result = nlohmann::json::object();
        for (size_t index = 0; index < names.size(runtime); index++)
        {
            jsi::Value nameValue = names.getValueAtIndex(runtime, index);
            if (!nameValue.isString())
            {
                throw std::invalid_argument("attribute names must be strings");
            }

            std::string name = nameValue.getString(runtime).utf8(runtime);
            if (name.empty() || name.size() > 64)
            {
                throw std::invalid_argument("attribute names must be 1 to 64 bytes");
            }

            jsi::Value attribute = object.getProperty(runtime, name.c_str());
            if (attribute.isString())
            {
                std::string text = attribute.getString(runtime).utf8(runtime);
                if (text.size() > kMaximumQueryStringBytes)
                {
                    throw std::invalid_argument("attribute strings exceed 256 bytes");
                }
                result[name] = std::move(text);
            }
            else if (attribute.isBool())
            {
                result[name] = attribute.getBool();
            }
            else if (attribute.isNumber() && std::isfinite(attribute.getNumber()))
            {
                result[name] = attribute.getNumber();
            }
            else if (attribute.isNull())
            {
                result[name] = nullptr;
            }
            else
            {
                throw std::invalid_argument("attribute values must be scalar");
            }
        }

        return result;
    }

    static std::string serializeQuery(jsi::Runtime &runtime, const jsi::Value &value)
    {
        if (!value.isObject() || value.isNull())
        {
            throw std::invalid_argument("a native UI query object is required");
        }

        jsi::Object input = value.asObject(runtime);
        if (input.isArray(runtime))
        {
            throw std::invalid_argument("a native UI query must be a plain object");
        }

        jsi::Value roleValue = input.getProperty(runtime, "role");
        if (!roleValue.isString())
        {
            throw std::invalid_argument("a native UI query requires a role string");
        }

        std::string role = roleValue.getString(runtime).utf8(runtime);
        if (role.empty() || role.size() > 128)
        {
            throw std::invalid_argument("the native UI query role must be 1 to 128 bytes");
        }

        nlohmann::json query = nlohmann::json::object();
        query["role"]      = std::move(role);
        query["attributes"] = scalarAttributes(runtime, input);
        query["maxDepth"]   = boundedInteger(runtime, input, "maxDepth", 16, 64);
        query["maxNodes"]   = boundedInteger(runtime, input, "maxNodes", 512, 2000);
        query["maxResults"] = boundedInteger(runtime, input, "maxResults", 128, 500);

        jsi::Value rootValue = input.getProperty(runtime, "root");
        if (rootValue.isObject() && !rootValue.isNull())
        {
            jsi::Object root = rootValue.asObject(runtime);
            jsi::Value  id   = root.getProperty(runtime, "id");
            if (!id.isString())
            {
                throw std::invalid_argument("a native UI root handle must contain a string id");
            }
            query["root"] = { { "id", id.getString(runtime).utf8(runtime) } };
        }

        std::string serialized = query.dump();
        if (serialized.size() > kMaximumQueryBytes)
        {
            throw std::invalid_argument("the native UI query exceeds 8192 bytes");
        }

        return serialized;
    }

    static std::string serializeHandle(jsi::Runtime &runtime, const jsi::Value &value)
    {
        if (!value.isObject() || value.isNull())
        {
            throw std::invalid_argument("a native UI handle is required");
        }

        jsi::Object handle = value.asObject(runtime);
        if (handle.isArray(runtime))
        {
            throw std::invalid_argument("a native UI handle must be a plain object");
        }

        jsi::Value id = handle.getProperty(runtime, "id");
        if (!id.isString())
        {
            throw std::invalid_argument("a native UI handle must contain a string id");
        }

        std::string identifier = id.getString(runtime).utf8(runtime);
        if (identifier.empty() || identifier.size() > 128)
        {
            throw std::invalid_argument("a native UI handle id must be 1 to 128 bytes");
        }

        return nlohmann::json({ { "id", identifier } }).dump();
    }

    static std::string serializeFrame(jsi::Runtime &runtime, const jsi::Value &value)
    {
        if (!value.isObject() || value.isNull())
        {
            throw std::invalid_argument("a native UI frame object is required");
        }

        jsi::Object input = value.asObject(runtime);
        if (input.isArray(runtime))
        {
            throw std::invalid_argument("a native UI frame must be a plain object");
        }

        nlohmann::json frame = nlohmann::json::object();
        for (const char *field : { "x", "y", "width", "height" })
        {
            jsi::Value coordinate = input.getProperty(runtime, field);
            if (!coordinate.isNumber() || !std::isfinite(coordinate.getNumber()))
            {
                throw std::invalid_argument(std::string("native UI frame ") + field +
                                            " must be a finite number");
            }

            double      number = coordinate.getNumber();
            std::string name(field);
            if ((name == "width" || name == "height") && (number <= 0 || number > 32768))
            {
                throw std::invalid_argument(std::string("native UI frame ") + field +
                                            " must be greater than zero and at most 32768");
            }
            if ((name == "x" || name == "y") && (number < -100000 || number > 100000))
            {
                throw std::invalid_argument(std::string("native UI frame ") + field +
                                            " must be between -100000 and 100000");
            }

            frame[field] = number;
        }

        return frame.dump();
    }

    static std::string callQuery(const JavaCallbacks &callbacks, jmethodID method,
                                 const std::string &query)
    {
        JNIEnv *env = currentEnvironment();
        if (!env || !callbacks.bridgeClass || !method)
        {
            throw std::runtime_error("The Android native UI adapter is unavailable");
        }

        jstring input = toJavaString(env, query);
        auto    output = static_cast<jstring>(
            env->CallStaticObjectMethod(callbacks.bridgeClass, method, input));
        bool failed = clearPendingException(env);
        env->DeleteLocalRef(input);
        if (failed || !output)
        {
            if (output)
            {
                env->DeleteLocalRef(output);
            }
            throw std::runtime_error("The Android native UI query failed");
        }

        std::string result = toStdString(env, output);
        env->DeleteLocalRef(output);
        return result;
    }

    static std::string callMeasure(const JavaCallbacks &callbacks, jmethodID method,
                                   const std::string &handle)
    {
        JNIEnv *env = currentEnvironment();
        if (!env || !callbacks.bridgeClass || !method)
        {
            throw std::runtime_error("The Android native UI adapter is unavailable");
        }

        jstring input = toJavaString(env, handle);
        auto    output = static_cast<jstring>(
            env->CallStaticObjectMethod(callbacks.bridgeClass, method, input));
        bool failed = clearPendingException(env);
        env->DeleteLocalRef(input);
        if (failed || !output)
        {
            if (output)
            {
                env->DeleteLocalRef(output);
            }
            throw std::runtime_error("The Android native UI measurement failed");
        }

        std::string result = toStdString(env, output);
        env->DeleteLocalRef(output);
        return result;
    }

    static void callSetFrame(const JavaCallbacks &callbacks, jmethodID method,
                             const std::string &handle, const std::string &frame)
    {
        JNIEnv *env = currentEnvironment();
        if (!env || !callbacks.bridgeClass || !method)
        {
            throw std::runtime_error("The Android native UI adapter is unavailable");
        }

        jstring inputHandle = toJavaString(env, handle);
        jstring inputFrame  = toJavaString(env, frame);
        env->CallStaticVoidMethod(callbacks.bridgeClass, method, inputHandle, inputFrame);
        bool failed = clearPendingException(env);
        env->DeleteLocalRef(inputFrame);
        env->DeleteLocalRef(inputHandle);
        if (failed)
        {
            throw std::runtime_error("The Android native UI frame update failed");
        }
    }

    static jsi::Value queryUI(jsi::Runtime &runtime, const jsi::Value *args, size_t count,
                              const JavaCallbacks &callbacks, jmethodID method)
    {
        if (count != 1)
        {
            loader::native::throwCoded(runtime, "NATIVE_BRIDGE_ERROR",
                                       "Native UI queries require exactly one argument");
        }

        std::string query = serializeQuery(runtime, args[0]);
        auto        response = std::make_shared<std::string>();
        return loader::native::executeMainAsynchronously(
            runtime,
            [callbacks, method, query = std::move(query), response]() {
                *response = callQuery(callbacks, method, query);
            },
            [response](jsi::Runtime &completion) -> jsi::Value {
                nlohmann::json result = nlohmann::json::parse(*response, nullptr, false);
                if (result.is_discarded())
                {
                    throw std::runtime_error("The Android native UI adapter returned invalid data");
                }
                return loader::toJSIValue(completion, result);
            });
    }

    static jsi::Value measureUI(jsi::Runtime &runtime, const jsi::Value *args, size_t count,
                                const JavaCallbacks &callbacks)
    {
        if (count != 1)
        {
            loader::native::throwCoded(runtime, "NATIVE_BRIDGE_ERROR",
                                       "Native UI measurement requires exactly one argument");
        }

        std::string handle = serializeHandle(runtime, args[0]);
        auto        response = std::make_shared<std::string>();
        return loader::native::executeMainAsynchronously(
            runtime,
            [callbacks, handle = std::move(handle), response]() {
                *response = callMeasure(callbacks, callbacks.measureView, handle);
            },
            [response](jsi::Runtime &completion) -> jsi::Value {
                nlohmann::json result = nlohmann::json::parse(*response, nullptr, false);
                if (result.is_discarded() || !result.is_object())
                {
                    throw std::runtime_error("The Android native UI adapter returned invalid data");
                }
                return loader::toJSIValue(completion, result);
            });
    }

    static jsi::Value setFrameUI(jsi::Runtime &runtime, const jsi::Value *args, size_t count,
                                 const JavaCallbacks &callbacks)
    {
        if (count != 2)
        {
            loader::native::throwCoded(runtime, "NATIVE_BRIDGE_ERROR",
                                       "Native UI frame updates require exactly two arguments");
        }

        std::string handle = serializeHandle(runtime, args[0]);
        std::string frame  = serializeFrame(runtime, args[1]);
        return loader::native::executeMainAsynchronously(
            runtime,
            [callbacks, handle = std::move(handle), frame = std::move(frame)]() {
                callSetFrame(callbacks, callbacks.setViewFrame, handle, frame);
            },
            [](jsi::Runtime &) -> jsi::Value { return jsi::Value::undefined(); });
    }

    void registerNativePluginBridge(jsi::Runtime &runtime, const JavaCallbacks &callbacks)
    {
        jsi::Object bridge(runtime);
        bridge.setProperty(runtime, "apiVersion",
                           jsi::String::createFromUtf8(runtime, loader::kNativePluginApiVersion));
        bridge.setProperty(runtime, "abiVersion",
                           jsi::String::createFromUtf8(runtime, loader::kNativePluginAbiVersion));

        jsi::Array capabilities(runtime, 2);
        capabilities.setValueAtIndex(runtime, 0,
                                     jsi::String::createFromUtf8(runtime, "native.ui.lookup"));
        capabilities.setValueAtIndex(runtime, 1,
                                     jsi::String::createFromUtf8(runtime, "native.ui.layout"));
        bridge.setProperty(runtime, "capabilities", std::move(capabilities));

        jsi::Object ui(runtime);
        ui.setProperty(
            runtime, "lookup",
            loader::native::makeFunction(runtime, "lookup", 1,
                                         [callbacks](jsi::Runtime &rt, const jsi::Value &,
                                                     const jsi::Value *args,
                                                     size_t count) -> jsi::Value {
                                             return queryUI(rt, args, count, callbacks,
                                                            callbacks.lookupViews);
                                         }));
        ui.setProperty(
            runtime, "snapshot",
            loader::native::makeFunction(runtime, "snapshot", 1,
                                         [callbacks](jsi::Runtime &rt, const jsi::Value &,
                                                     const jsi::Value *args,
                                                     size_t count) -> jsi::Value {
                                             return queryUI(rt, args, count, callbacks,
                                                            callbacks.snapshotViews);
                                         }));
        ui.setProperty(
            runtime, "measure",
            loader::native::makeFunction(runtime, "measure", 1,
                                         [callbacks](jsi::Runtime &rt, const jsi::Value &,
                                                     const jsi::Value *args,
                                                     size_t count) -> jsi::Value {
                                             return measureUI(rt, args, count, callbacks);
                                         }));
        ui.setProperty(
            runtime, "setFrame",
            loader::native::makeFunction(runtime, "setFrame", 2,
                                         [callbacks](jsi::Runtime &rt, const jsi::Value &,
                                                     const jsi::Value *args,
                                                     size_t count) -> jsi::Value {
                                             return setFrameUI(rt, args, count, callbacks);
                                         }));
        bridge.setProperty(runtime, "ui", std::move(ui));

        runtime.global().setProperty(runtime, "NativePlugin", std::move(bridge));
    }
}
