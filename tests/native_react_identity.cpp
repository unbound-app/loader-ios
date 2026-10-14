#include "NativeReactIdentity.h"

#include <cassert>

int main()
{
    NativeReactIdentity fiber(1424, 4);
    assert(fiber.valid(1424, 4));
    assert(!fiber.valid(1425, 4));
    assert(!fiber.valid(1424, 5));

    NativeReactIdentity invalidTag(0, 4);
    assert(!invalidTag.valid(0, 4));

    fiber.invalidate();
    assert(!fiber.active());
    assert(!fiber.valid(1424, 4));
}
