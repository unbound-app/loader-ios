#include "NativeAddressValidation.h"

#ifdef __APPLE__
#include <mach-o/dyld.h>
#include <mach-o/loader.h>
#include <mach/vm_prot.h>
#endif

bool addressWithinRegion(std::uintptr_t address, std::uintptr_t base, std::size_t size)
{
    return address >= base && address - base < size;
}

bool isExecutableImageAddress(void *address)
{
#ifdef __APPLE__
    std::uintptr_t target = reinterpret_cast<std::uintptr_t>(address);
    uint32_t imageCount = _dyld_image_count();
    for (uint32_t image = 0; image < imageCount; image++)
    {
        const mach_header *header = _dyld_get_image_header(image);
        if (!header || header->magic != MH_MAGIC_64)
        {
            continue;
        }

        const auto *header64 = reinterpret_cast<const mach_header_64 *>(header);
        if (header64->ncmds > 4096 || header64->sizeofcmds > 16 * 1024 * 1024)
        {
            continue;
        }
        const auto *commandBytes = reinterpret_cast<const uint8_t *>(header64 + 1);
        size_t remaining = header64->sizeofcmds;
        intptr_t slide = _dyld_get_image_vmaddr_slide(image);
        for (uint32_t commandIndex = 0; commandIndex < header64->ncmds; commandIndex++)
        {
            if (remaining < sizeof(load_command))
            {
                break;
            }
            const auto *command = reinterpret_cast<const load_command *>(commandBytes);
            if (command->cmdsize < sizeof(load_command) || command->cmdsize > remaining)
            {
                break;
            }
            if (command->cmd == LC_SEGMENT_64 && command->cmdsize >= sizeof(segment_command_64))
            {
                const auto *segment = reinterpret_cast<const segment_command_64 *>(commandBytes);
                __int128 start = static_cast<__int128>(segment->vmaddr) + slide;
                if ((segment->initprot & VM_PROT_EXECUTE) != 0 && start >= 0 &&
                    start <= UINTPTR_MAX &&
                    addressWithinRegion(target, static_cast<std::uintptr_t>(start), segment->vmsize))
                {
                    return true;
                }
            }
            commandBytes += command->cmdsize;
            remaining -= command->cmdsize;
        }
    }
#endif
    return false;
}
