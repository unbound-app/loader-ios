#pragma once

#include <cstdint>
#include <functional>
#include <map>
#include <optional>
#include <string>

#include "LoaderSettings.h"

namespace loader
{
    struct DownloadResult
    {
        int         status = 0;
        std::string etag;
    };

    using TextFetcher =
        std::function<std::optional<std::string>(const std::string &url, double timeoutSeconds)>;
    using FileDownloader = std::function<std::optional<DownloadResult>(
        const std::string &url, const std::string &destination,
        const std::map<std::string, std::string> &headers)>;

    constexpr const char *kDefaultBundleBaseURL = "https://builds.unbound.rip/";

    class BundleUpdater
    {
    public:
        BundleUpdater(std::string documents, SettingsStore &settings, TextFetcher fetchText,
                      FileDownloader download);

        std::string resolveBundlePath();
        std::string downloadBundle(const std::string &preferredPath,
                                   const std::optional<std::string> &updateURL,
                                   uint32_t bytecodeVersion);
        std::string downloadURL(const std::optional<std::string> &updateURL,
                                uint32_t bytecodeVersion);

        bool markBundleAttempted(const std::string &path);
        bool acceptBundle(const std::string &path);
        void rejectBundle(const std::string &path);

    private:
        std::string bundlePath(const std::string &extension) const;

        std::string     documents_;
        SettingsStore  &settings_;
        TextFetcher     fetchText_;
        FileDownloader  download_;
    };
}
