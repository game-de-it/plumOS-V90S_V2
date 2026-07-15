#ifndef PLUMOS_PICOARCH_V90S_HOST_H
#define PLUMOS_PICOARCH_V90S_HOST_H

#include <stdbool.h>

bool v90s_get_perf_interface(void *data);
bool v90s_get_vfs_interface(void *data, const char *core_path);

#endif
