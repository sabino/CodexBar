#ifndef CODEXBAR_PLATFORM_TRAY_H
#define CODEXBAR_PLATFORM_TRAY_H

#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

enum {
    CODEXBAR_TRAY_ACTION_ACTIVATE = 0,
    CODEXBAR_TRAY_ACTION_REFRESH = 1,
    CODEXBAR_TRAY_ACTION_SETTINGS = 2,
    CODEXBAR_TRAY_ACTION_ABOUT = 3,
    CODEXBAR_TRAY_ACTION_QUIT = 4,
    CODEXBAR_TRAY_ACTION_SHOW = 5,
};

typedef void (*CodexBarTrayActionCallback)(int action, void *context);

bool codexbar_tray_install(
    const char *icon_path,
    const char *tooltip,
    CodexBarTrayActionCallback callback,
    void *context);
void codexbar_tray_update(const char *icon_path, const char *tooltip);
void codexbar_tray_remove(void);

#ifdef __cplusplus
}
#endif

#endif
