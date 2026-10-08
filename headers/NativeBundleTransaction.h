#pragma once

#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

bool promoteNativeBundle(const char *candidatePath, const char *targetPath,
                         const char *backupPath);

#ifdef __cplusplus
}
#endif
