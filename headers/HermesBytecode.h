#pragma once

#import <stddef.h>
#import <stdint.h>

// Hermes bytecode (HBC) helpers for the loader.
//
// We need the runtime's accepted bytecode version to fetch the matching remote
// bundle. Rather than read it out of the runtime (hidden symbols, internal C++
// ABI), we read it from Discord's shipped HBC bundle: Discord.app/main.jsbundle is
// compiled by the same hermesc that built the bundled hermes.framework, so its
// header version IS the version this runtime accepts. See
// +[Utilities getHermesBytecodeVersion].

// Magic prefixing every HBC file (little-endian on disk).
static const uint64_t HERMES_MAGIC = 0x1F1903C103BC1FC6ULL;

#pragma pack(push, 1)
typedef struct
{
    uint64_t magic;
    uint32_t version;
} HermesBytecodeFileHeaderPrefix;
#pragma pack(pop)

// YES if `data`/`length` begins with the Hermes bytecode magic.
static inline BOOL HermesDataIsBytecode(const void *data, size_t length)
{
    if (!data || length < sizeof(HermesBytecodeFileHeaderPrefix))
        return NO;
    return ((const HermesBytecodeFileHeaderPrefix *) data)->magic == HERMES_MAGIC;
}

// Version stamped into an HBC blob (0 if it isn't HBC or is too short).
static inline uint32_t HermesDataBytecodeVersion(const void *data, size_t length)
{
    if (!HermesDataIsBytecode(data, length))
        return 0;
    return ((const HermesBytecodeFileHeaderPrefix *) data)->version;
}
