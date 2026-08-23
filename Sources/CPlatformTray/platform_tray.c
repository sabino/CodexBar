#include "CPlatformTray.h"

#if defined(__linux__)

#include <gio/gio.h>
#include <glib.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

typedef struct {
    GDBusConnection *connection;
    GDBusNodeInfo *node_info;
    guint registration_id;
    guint owner_id;
    char *bus_name;
    char *icon_path;
    char *tooltip;
    CodexBarTrayActivationCallback callback;
    void *context;
} CodexBarLinuxTray;

static CodexBarLinuxTray tray = {0};

static const gchar introspection_xml[] =
    "<node>"
    "  <interface name='org.kde.StatusNotifierItem'>"
    "    <method name='ContextMenu'><arg type='i' direction='in'/><arg type='i' direction='in'/></method>"
    "    <method name='Activate'><arg type='i' direction='in'/><arg type='i' direction='in'/></method>"
    "    <method name='SecondaryActivate'><arg type='i' direction='in'/><arg type='i' direction='in'/></method>"
    "    <method name='Scroll'><arg type='i' direction='in'/><arg type='s' direction='in'/></method>"
    "    <property name='Category' type='s' access='read'/>"
    "    <property name='Id' type='s' access='read'/>"
    "    <property name='Title' type='s' access='read'/>"
    "    <property name='Status' type='s' access='read'/>"
    "    <property name='WindowId' type='u' access='read'/>"
    "    <property name='IconName' type='s' access='read'/>"
    "    <property name='AttentionIconName' type='s' access='read'/>"
    "    <property name='Menu' type='o' access='read'/>"
    "    <property name='ItemIsMenu' type='b' access='read'/>"
    "    <signal name='NewIcon'/><signal name='NewToolTip'/><signal name='NewStatus'><arg type='s'/></signal>"
    "  </interface>"
    "</node>";

static void handle_method_call(
    GDBusConnection *connection,
    const gchar *sender,
    const gchar *object_path,
    const gchar *interface_name,
    const gchar *method_name,
    GVariant *parameters,
    GDBusMethodInvocation *invocation,
    gpointer user_data)
{
    (void)connection;
    (void)sender;
    (void)object_path;
    (void)interface_name;
    (void)parameters;
    (void)user_data;
    if (g_strcmp0(method_name, "Activate") == 0
        || g_strcmp0(method_name, "SecondaryActivate") == 0
        || g_strcmp0(method_name, "ContextMenu") == 0) {
        if (tray.callback != NULL) {
            tray.callback(tray.context);
        }
    }
    g_dbus_method_invocation_return_value(invocation, NULL);
}

static GVariant *handle_get_property(
    GDBusConnection *connection,
    const gchar *sender,
    const gchar *object_path,
    const gchar *interface_name,
    const gchar *property_name,
    GError **error,
    gpointer user_data)
{
    (void)connection;
    (void)sender;
    (void)object_path;
    (void)interface_name;
    (void)error;
    (void)user_data;
    if (g_strcmp0(property_name, "Category") == 0) return g_variant_new_string("ApplicationStatus");
    if (g_strcmp0(property_name, "Id") == 0) return g_variant_new_string("codexbar");
    if (g_strcmp0(property_name, "Title") == 0) {
        return g_variant_new_string(tray.tooltip != NULL ? tray.tooltip : "CodexBar");
    }
    if (g_strcmp0(property_name, "Status") == 0) return g_variant_new_string("Active");
    if (g_strcmp0(property_name, "WindowId") == 0) return g_variant_new_uint32(0);
    if (g_strcmp0(property_name, "IconName") == 0) {
        return g_variant_new_string(tray.icon_path != NULL ? tray.icon_path : "");
    }
    if (g_strcmp0(property_name, "AttentionIconName") == 0) return g_variant_new_string("");
    if (g_strcmp0(property_name, "Menu") == 0) return g_variant_new_object_path("/NO_DBUSMENU");
    if (g_strcmp0(property_name, "ItemIsMenu") == 0) return g_variant_new_boolean(FALSE);
    return NULL;
}

static const GDBusInterfaceVTable interface_vtable = {
    .method_call = handle_method_call,
    .get_property = handle_get_property,
    .set_property = NULL,
};

static void register_with_watcher(
    GDBusConnection *connection,
    const gchar *name,
    gpointer user_data)
{
    (void)user_data;
    g_dbus_connection_call(
        connection,
        "org.kde.StatusNotifierWatcher",
        "/StatusNotifierWatcher",
        "org.kde.StatusNotifierWatcher",
        "RegisterStatusNotifierItem",
        g_variant_new("(s)", name),
        NULL,
        G_DBUS_CALL_FLAGS_NONE,
        3000,
        NULL,
        NULL,
        NULL);
}

static void emit_signal(const char *name, GVariant *parameters)
{
    if (tray.connection == NULL || tray.registration_id == 0) return;
    g_dbus_connection_emit_signal(
        tray.connection,
        NULL,
        "/StatusNotifierItem",
        "org.kde.StatusNotifierItem",
        name,
        parameters,
        NULL);
}

bool codexbar_tray_install(
    const char *icon_path,
    const char *tooltip,
    CodexBarTrayActivationCallback callback,
    void *context)
{
    codexbar_tray_remove();
    GError *error = NULL;
    tray.connection = g_bus_get_sync(G_BUS_TYPE_SESSION, NULL, &error);
    if (tray.connection == NULL) {
        if (error != NULL) g_error_free(error);
        return false;
    }
    tray.node_info = g_dbus_node_info_new_for_xml(introspection_xml, &error);
    if (tray.node_info == NULL) {
        if (error != NULL) g_error_free(error);
        codexbar_tray_remove();
        return false;
    }
    tray.icon_path = g_strdup(icon_path != NULL ? icon_path : "");
    tray.tooltip = g_strdup(tooltip != NULL ? tooltip : "CodexBar");
    tray.callback = callback;
    tray.context = context;
    tray.registration_id = g_dbus_connection_register_object(
        tray.connection,
        "/StatusNotifierItem",
        tray.node_info->interfaces[0],
        &interface_vtable,
        NULL,
        NULL,
        &error);
    if (tray.registration_id == 0) {
        if (error != NULL) g_error_free(error);
        codexbar_tray_remove();
        return false;
    }
    char name[96];
    snprintf(name, sizeof(name), "org.kde.StatusNotifierItem-%ld-1", (long)getpid());
    tray.bus_name = g_strdup(name);
    tray.owner_id = g_bus_own_name_on_connection(
        tray.connection,
        tray.bus_name,
        G_BUS_NAME_OWNER_FLAGS_NONE,
        register_with_watcher,
        NULL,
        NULL,
        NULL);
    return tray.owner_id != 0;
}

void codexbar_tray_update(const char *icon_path, const char *tooltip)
{
    g_free(tray.icon_path);
    g_free(tray.tooltip);
    tray.icon_path = g_strdup(icon_path != NULL ? icon_path : "");
    tray.tooltip = g_strdup(tooltip != NULL ? tooltip : "CodexBar");
    emit_signal("NewIcon", NULL);
    emit_signal("NewToolTip", NULL);
}

void codexbar_tray_remove(void)
{
    if (tray.owner_id != 0) g_bus_unown_name(tray.owner_id);
    if (tray.connection != NULL && tray.registration_id != 0) {
        g_dbus_connection_unregister_object(tray.connection, tray.registration_id);
    }
    if (tray.node_info != NULL) g_dbus_node_info_unref(tray.node_info);
    if (tray.connection != NULL) g_object_unref(tray.connection);
    g_free(tray.bus_name);
    g_free(tray.icon_path);
    g_free(tray.tooltip);
    memset(&tray, 0, sizeof(tray));
}

#elif defined(_WIN32)

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <shellapi.h>
#include <stdlib.h>

#define CODEXBAR_TRAY_MESSAGE (WM_APP + 42)

static HWND tray_window = NULL;
static HICON tray_icon = NULL;
static CodexBarTrayActivationCallback tray_callback = NULL;
static void *tray_context = NULL;

static wchar_t *utf8_to_wide(const char *value)
{
    if (value == NULL) return NULL;
    int count = MultiByteToWideChar(CP_UTF8, 0, value, -1, NULL, 0);
    if (count <= 0) return NULL;
    wchar_t *wide = (wchar_t *)calloc((size_t)count, sizeof(wchar_t));
    if (wide != NULL) MultiByteToWideChar(CP_UTF8, 0, value, -1, wide, count);
    return wide;
}

static LRESULT CALLBACK tray_window_proc(HWND window, UINT message, WPARAM wparam, LPARAM lparam)
{
    (void)wparam;
    if (message == CODEXBAR_TRAY_MESSAGE) {
        UINT event = LOWORD(lparam);
        if ((event == WM_LBUTTONUP || event == WM_RBUTTONUP || event == WM_CONTEXTMENU)
            && tray_callback != NULL) {
            tray_callback(tray_context);
        }
        return 0;
    }
    return DefWindowProcW(window, message, wparam, lparam);
}

static void fill_notification(NOTIFYICONDATAW *data, const char *tooltip)
{
    ZeroMemory(data, sizeof(*data));
    data->cbSize = sizeof(*data);
    data->hWnd = tray_window;
    data->uID = 1;
    data->uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP;
    data->uCallbackMessage = CODEXBAR_TRAY_MESSAGE;
    data->hIcon = tray_icon;
    wchar_t *wide_tooltip = utf8_to_wide(tooltip != NULL ? tooltip : "CodexBar");
    if (wide_tooltip != NULL) {
        wcsncpy_s(data->szTip, ARRAYSIZE(data->szTip), wide_tooltip, _TRUNCATE);
        free(wide_tooltip);
    }
}

static HICON load_icon(const char *icon_path)
{
    wchar_t *wide_path = utf8_to_wide(icon_path);
    if (wide_path == NULL) return NULL;
    HICON icon = (HICON)LoadImageW(
        NULL,
        wide_path,
        IMAGE_ICON,
        0,
        0,
        LR_LOADFROMFILE | LR_DEFAULTSIZE);
    free(wide_path);
    return icon;
}

bool codexbar_tray_install(
    const char *icon_path,
    const char *tooltip,
    CodexBarTrayActivationCallback callback,
    void *context)
{
    codexbar_tray_remove();
    HINSTANCE instance = GetModuleHandleW(NULL);
    WNDCLASSW window_class = {0};
    window_class.lpfnWndProc = tray_window_proc;
    window_class.hInstance = instance;
    window_class.lpszClassName = L"CodexBarCrossTrayWindow";
    RegisterClassW(&window_class);
    tray_window = CreateWindowExW(
        0,
        window_class.lpszClassName,
        L"CodexBar",
        0,
        0,
        0,
        0,
        0,
        HWND_MESSAGE,
        NULL,
        instance,
        NULL);
    if (tray_window == NULL) return false;
    tray_icon = load_icon(icon_path);
    tray_callback = callback;
    tray_context = context;
    NOTIFYICONDATAW data;
    fill_notification(&data, tooltip);
    if (!Shell_NotifyIconW(NIM_ADD, &data)) {
        codexbar_tray_remove();
        return false;
    }
    data.uVersion = NOTIFYICON_VERSION_4;
    Shell_NotifyIconW(NIM_SETVERSION, &data);
    return true;
}

void codexbar_tray_update(const char *icon_path, const char *tooltip)
{
    HICON replacement = load_icon(icon_path);
    if (replacement != NULL) {
        if (tray_icon != NULL) DestroyIcon(tray_icon);
        tray_icon = replacement;
    }
    if (tray_window != NULL) {
        NOTIFYICONDATAW data;
        fill_notification(&data, tooltip);
        Shell_NotifyIconW(NIM_MODIFY, &data);
    }
}

void codexbar_tray_remove(void)
{
    if (tray_window != NULL) {
        NOTIFYICONDATAW data;
        ZeroMemory(&data, sizeof(data));
        data.cbSize = sizeof(data);
        data.hWnd = tray_window;
        data.uID = 1;
        Shell_NotifyIconW(NIM_DELETE, &data);
        DestroyWindow(tray_window);
    }
    if (tray_icon != NULL) DestroyIcon(tray_icon);
    tray_window = NULL;
    tray_icon = NULL;
    tray_callback = NULL;
    tray_context = NULL;
}

#else

bool codexbar_tray_install(
    const char *icon_path,
    const char *tooltip,
    CodexBarTrayActivationCallback callback,
    void *context)
{
    (void)icon_path;
    (void)tooltip;
    (void)callback;
    (void)context;
    return false;
}

void codexbar_tray_update(const char *icon_path, const char *tooltip)
{
    (void)icon_path;
    (void)tooltip;
}

void codexbar_tray_remove(void) {}

#endif
