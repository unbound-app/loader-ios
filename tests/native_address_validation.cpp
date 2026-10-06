#include "NativeAddressValidation.h"

#include <cassert>
#include <limits>

static int nativeData = 7;

static int nativeFunction()
{
    return nativeData;
}

int main()
{
    assert(addressWithinRegion(0x1000, 0x1000, 0x100));
    assert(addressWithinRegion(0x10ff, 0x1000, 0x100));
    assert(!addressWithinRegion(0x1100, 0x1000, 0x100));
    assert(!addressWithinRegion(0x0fff, 0x1000, 0x100));
    assert(!addressWithinRegion(0x1000, 0x1000, 0));
    assert(!addressWithinRegion(0, std::numeric_limits<std::uintptr_t>::max() - 2, 4));
#ifdef __APPLE__
    assert(nativeFunction() == 7);
    assert(isExecutableImageAddress(reinterpret_cast<void *>(&nativeFunction)));
    assert(!isExecutableImageAddress(&nativeData));
    assert(!isExecutableImageAddress(nullptr));
#endif
}
