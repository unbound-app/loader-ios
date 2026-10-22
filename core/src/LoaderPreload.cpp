#include "LoaderPreload.h"

namespace loader
{
    std::string toJSON(const nlohmann::json &value)
    {
        return value.dump(-1, ' ', false, nlohmann::json::error_handler_t::replace);
    }

    std::string buildPreloadScript(const PreloadPayload &payload)
    {
        std::string settings = payload.settings.empty() ? "{}" : payload.settings;

        return "this.UNBOUND_SETTINGS = " + settings + ";\n" +
               "this.UNBOUND_PLUGINS = " + toJSON(payload.plugins) + ";\n" +
               "this.UNBOUND_THEMES = " + toJSON(payload.themes) + ";\n" +
               "this.UNBOUND_FONTS = " + toJSON(payload.fonts) + ";\n" +
               "this.UNBOUND_AVAILABLE_FONTS = " + toJSON(payload.availableFonts) + ";\n\n" +
               "this.UNBOUND_LOADER = {\n" + "    origin: " + toJSON(payload.origin) + ",\n" +
               "    version: " + toJSON(payload.version) + ",\n" + "};";
    }
}
