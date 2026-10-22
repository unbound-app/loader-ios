#pragma once

#include <string>

#include "../third_party/nlohmann/json.hpp"

namespace loader
{
    struct PreloadPayload
    {
        std::string    settings;
        nlohmann::json plugins        = nlohmann::json::array();
        nlohmann::json themes         = nlohmann::json::array();
        nlohmann::json fonts          = nlohmann::json::array();
        nlohmann::json availableFonts = nlohmann::json::array();
        std::string    origin;
        std::string    version;
    };

    std::string toJSON(const nlohmann::json &value);
    std::string buildPreloadScript(const PreloadPayload &payload);
}
