#ifndef CODEXBAR_PLATFORM_TRAY_H
#define CODEXBAR_PLATFORM_TRAY_H

#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef void (*CodexBarTrayActivationCallback)(void *context);

bool codexbar_tray_install(
    const char *icon_path,
    const char *tooltip,
    CodexBarTrayActivationCallback callback,
    void *context);
void codexbar_tray_update(const char *icon_path, const char *tooltip);
void codexbar_tray_remove(void);

#ifdef __cplusplus
}
#endif

#endif
