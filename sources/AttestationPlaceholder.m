#include "Attestation.h"

#if ATTESTATION_ENABLED
__attribute__((section("__TEXT,__attestation"), used))
const unsigned char AttestationPlaceholder[ATTESTATION_SECTION_SIZE] = {0};
#endif
