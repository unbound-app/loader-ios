#include "LoaderJSI.h"

#include "HermesBytecodeHeader.h"
#include "LoaderLog.h"

namespace loader
{
    namespace jsi = facebook::jsi;

    static const char *const kRuntimeReadinessSource =
        "(()=>{const map=globalThis.modules??globalThis.__c?.();if(!globalThis.modules&&map)"
        "globalThis.modules=map;if(!map||typeof map.values!=='function')return false;let rn=false;"
        "let react=false;for(const m of map.values()){const e=m?.publicModule?.exports??m?.exports??m;"
        "const values=[e,e?.default,e?.default?.default];for(const value of values){if(!value)"
        "continue;if(!rn&&value.AppState&&value.NativeModules)rn=true;if(!react&&typeof "
        "value.createElement==='function')react=true;}}return rn&&react;})()";

    OwnedBuffer::OwnedBuffer(std::string data) : data_(std::move(data)) {}

    size_t OwnedBuffer::size() const
    {
        return data_.size();
    }

    const uint8_t *OwnedBuffer::data() const
    {
        return reinterpret_cast<const uint8_t *>(data_.data());
    }

    bool evaluateScript(jsi::Runtime &runtime, const std::string &script, const std::string &tag)
    {
        if (script.empty())
        {
            return false;
        }

        try
        {
            if (isHermesBytecode(script.data(), script.size()))
            {
                auto prepared =
                    runtime.prepareJavaScript(std::make_shared<OwnedBuffer>(script), tag);
                runtime.evaluatePreparedJavaScript(prepared);
            }
            else
            {
                runtime.evaluateJavaScript(std::make_shared<jsi::StringBuffer>(script), tag);
            }
            return true;
        }
        catch (const jsi::JSError &error)
        {
            log(LogLevel::Error, "default",
                "JSI eval of '" + tag + "' threw JSError: " + error.what());
        }
        catch (const std::exception &error)
        {
            log(LogLevel::Error, "default",
                "JSI eval of '" + tag + "' threw exception: " + error.what());
        }
        catch (...)
        {
            log(LogLevel::Error, "default", "JSI eval of '" + tag + "' threw an unknown error");
        }
        return false;
    }

    jsi::Value evaluateSource(jsi::Runtime &runtime, const std::string &source,
                              const std::string &tag)
    {
        if (source.empty())
        {
            return jsi::Value();
        }

        try
        {
            return runtime.evaluateJavaScript(std::make_shared<jsi::StringBuffer>(source), tag);
        }
        catch (const jsi::JSError &error)
        {
            log(LogLevel::Error, "default",
                "JSI source eval of '" + tag + "' threw JSError: " + error.what());
        }
        catch (const std::exception &error)
        {
            log(LogLevel::Error, "default",
                "JSI source eval of '" + tag + "' threw exception: " + error.what());
        }
        catch (...)
        {
            log(LogLevel::Error, "default",
                "JSI source eval of '" + tag + "' threw an unknown error");
        }
        return jsi::Value();
    }

    jsi::Value evaluateBytecode(jsi::Runtime &runtime, std::string bytecode, const std::string &tag)
    {
        if (bytecode.empty())
        {
            throw jsi::JSError(runtime, "evaluateBytecode: bytecode is empty");
        }

        if (!isHermesBytecode(bytecode.data(), bytecode.size()))
        {
            throw jsi::JSError(runtime, "evaluateBytecode: data is not Hermes bytecode");
        }

        auto prepared =
            runtime.prepareJavaScript(std::make_shared<OwnedBuffer>(std::move(bytecode)), tag);
        return runtime.evaluatePreparedJavaScript(prepared);
    }

    bool runtimeHasRequiredModules(jsi::Runtime &runtime)
    {
        jsi::Value result = evaluateSource(runtime, kRuntimeReadinessSource, "unbound:runtime-readiness");
        return result.isBool() && result.getBool();
    }
}
