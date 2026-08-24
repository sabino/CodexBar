#include "CPlatformTray.h"

#if defined(__linux__) && defined(CODEXBAR_CROSS_PLATFORM_APP)

#include <gio/gio.h>
#include <glib.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

enum {
    CODEXBAR_MENU_ROOT = 0,
    CODEXBAR_MENU_HEADER = 1,
    CODEXBAR_MENU_SHOW = 2,
    CODEXBAR_MENU_REFRESH = 3,
    CODEXBAR_MENU_SETTINGS = 4,
    CODEXBAR_MENU_ABOUT = 5,
    CODEXBAR_MENU_SEPARATOR = 6,
    CODEXBAR_MENU_QUIT = 7,
};

typedef struct {
    GDBusConnection *connection;
    GDBusNodeInfo *node_info;
    guint item_registration_id;
    guint menu_registration_id;
    guint owner_id;
    char *bus_name;
    char *icon_path;
    char *tooltip;
    CodexBarTrayActionCallback callback;
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
    "    <signal name='NewIcon'/>"
    "    <signal name='NewToolTip'/>"
    "    <signal name='NewStatus'><arg type='s'/></signal>"
    "  </interface>"
    "  <interface name='com.canonical.dbusmenu'>"
    "    <method name='GetLayout'>"
    "      <arg name='parentId' type='i' direction='in'/>"
    "      <arg name='recursionDepth' type='i' direction='in'/>"
    "      <arg name='propertyNames' type='as' direction='in'/>"
    "      <arg name='revision' type='u' direction='out'/>"
    "      <arg name='layout' type='(ia{sv}av)' direction='out'/>"
    "    </method>"
    "    <method name='GetGroupProperties'>"
    "      <arg name='ids' type='ai' direction='in'/>"
    "      <arg name='propertyNames' type='as' direction='in'/>"
    "      <arg name='properties' type='a(ia{sv})' direction='out'/>"
    "    </method>"
    "    <method name='GetProperty'>"
    "      <arg name='id' type='i' direction='in'/>"
    "      <arg name='name' type='s' direction='in'/>"
    "      <arg name='value' type='v' direction='out'/>"
    "    </method>"
    "    <method name='Event'>"
    "      <arg name='id' type='i' direction='in'/>"
    "      <arg name='eventId' type='s' direction='in'/>"
    "      <arg name='data' type='v' direction='in'/>"
    "      <arg name='timestamp' type='u' direction='in'/>"
    "    </method>"
    "    <method name='EventGroup'>"
    "      <arg name='events' type='a(isvu)' direction='in'/>"
    "      <arg name='idErrors' type='ai' direction='out'/>"
    "    </method>"
    "    <method name='AboutToShow'>"
    "      <arg name='id' type='i' direction='in'/>"
    "      <arg name='needUpdate' type='b' direction='out'/>"
    "    </method>"
    "    <method name='AboutToShowGroup'>"
    "      <arg name='ids' type='ai' direction='in'/>"
    "      <arg name='updatesNeeded' type='ai' direction='out'/>"
    "      <arg name='idErrors' type='ai' direction='out'/>"
    "    </method>"
    "    <property name='Version' type='u' access='read'/>"
    "    <property name='TextDirection' type='s' access='read'/>"
    "    <property name='Status' type='s' access='read'/>"
    "    <property name='IconThemePath' type='as' access='read'/>"
    "    <signal name='ItemsPropertiesUpdated'>"
    "      <arg name='updatedProps' type='a(ia{sv})'/>"
    "      <arg name='removedProps' type='a(ias)'/>"
    "    </signal>"
    "    <signal name='LayoutUpdated'><arg name='revision' type='u'/><arg name='parent' type='i'/></signal>"
    "  </interface>"
    "</node>";

static const char *menu_label(gint32 id)
{
    switch (id) {
    case CODEXBAR_MENU_HEADER: return "CodexBar";
    case CODEXBAR_MENU_SHOW: return "Show CodexBar";
    case CODEXBAR_MENU_REFRESH: return "Refresh";
    case CODEXBAR_MENU_SETTINGS: return "Settings...";
    case CODEXBAR_MENU_ABOUT: return "About CodexBar";
    case CODEXBAR_MENU_QUIT: return "Quit";
    default: return NULL;
    }
}

static gboolean menu_item_is_valid(gint32 id)
{
    return id >= CODEXBAR_MENU_ROOT && id <= CODEXBAR_MENU_QUIT;
}

static GVariant *menu_property(gint32 id, const char *name)
{
    const char *label = menu_label(id);
    if (g_strcmp0(name, "label") == 0 && label != NULL) return g_variant_new_string(label);
    if (g_strcmp0(name, "enabled") == 0) {
        return g_variant_new_boolean(id != CODEXBAR_MENU_HEADER && id != CODEXBAR_MENU_SEPARATOR);
    }
    if (g_strcmp0(name, "visible") == 0) return g_variant_new_boolean(menu_item_is_valid(id));
    if (g_strcmp0(name, "type") == 0 && id == CODEXBAR_MENU_SEPARATOR) {
        return g_variant_new_string("separator");
    }
    return NULL;
}

static GVariant *menu_properties(gint32 id)
{
    GVariantBuilder properties;
    g_variant_builder_init(&properties, G_VARIANT_TYPE("a{sv}"));
    const char *label = menu_label(id);
    if (label != NULL) {
        g_variant_builder_add(&properties, "{sv}", "label", g_variant_new_string(label));
    }
    if (id != CODEXBAR_MENU_ROOT) {
        g_variant_builder_add(
            &properties,
            "{sv}",
            "enabled",
            g_variant_new_boolean(id != CODEXBAR_MENU_HEADER && id != CODEXBAR_MENU_SEPARATOR));
        g_variant_builder_add(&properties, "{sv}", "visible", g_variant_new_boolean(TRUE));
    }
    if (id == CODEXBAR_MENU_SEPARATOR) {
        g_variant_builder_add(&properties, "{sv}", "type", g_variant_new_string("separator"));
    }
    return g_variant_builder_end(&properties);
}

static GVariant *menu_layout(gint32 parent_id)
{
    GVariantBuilder children;
    g_variant_builder_init(&children, G_VARIANT_TYPE("av"));
    if (parent_id == CODEXBAR_MENU_ROOT) {
        for (gint32 id = CODEXBAR_MENU_HEADER; id <= CODEXBAR_MENU_QUIT; id++) {
            GVariantBuilder grandchildren;
            g_variant_builder_init(&grandchildren, G_VARIANT_TYPE("av"));
            GVariant *child = g_variant_new(
                "(i@a{sv}@av)",
                id,
                menu_properties(id),
                g_variant_builder_end(&grandchildren));
            g_variant_builder_add(&children, "v", child);
        }
    }
    return g_variant_new(
        "(i@a{sv}@av)",
        parent_id,
        menu_properties(parent_id),
        g_variant_builder_end(&children));
}

static GVariant *empty_int_array(void)
{
    GVariantBuilder values;
    g_variant_builder_init(&values, G_VARIANT_TYPE("ai"));
    return g_variant_builder_end(&values);
}

static void invoke_action_for_menu_item(gint32 id)
{
    if (tray.callback == NULL) return;
    switch (id) {
    case CODEXBAR_MENU_SHOW:
        tray.callback(CODEXBAR_TRAY_ACTION_SHOW, tray.context);
        break;
    case CODEXBAR_MENU_REFRESH:
        tray.callback(CODEXBAR_TRAY_ACTION_REFRESH, tray.context);
        break;
    case CODEXBAR_MENU_SETTINGS:
        tray.callback(CODEXBAR_TRAY_ACTION_SETTINGS, tray.context);
        break;
    case CODEXBAR_MENU_ABOUT:
        tray.callback(CODEXBAR_TRAY_ACTION_ABOUT, tray.context);
        break;
    case CODEXBAR_MENU_QUIT:
        tray.callback(CODEXBAR_TRAY_ACTION_QUIT, tray.context);
        break;
    default:
        break;
    }
}

static void handle_menu_method_call(
    const gchar *method_name,
    GVariant *parameters,
    GDBusMethodInvocation *invocation)
{
    if (g_strcmp0(method_name, "GetLayout") == 0) {
        gint32 parent_id = CODEXBAR_MENU_ROOT;
        gint32 recursion_depth = 0;
        GVariant *property_names = NULL;
        g_variant_get(parameters, "(ii@as)", &parent_id, &recursion_depth, &property_names);
        (void)recursion_depth;
        g_variant_unref(property_names);
        if (!menu_item_is_valid(parent_id)) parent_id = CODEXBAR_MENU_ROOT;
        g_dbus_method_invocation_return_value(
            invocation,
            g_variant_new("(u@(ia{sv}av))", 1u, menu_layout(parent_id)));
        return;
    }
    if (g_strcmp0(method_name, "GetGroupProperties") == 0) {
        GVariant *ids = NULL;
        GVariant *property_names = NULL;
        g_variant_get(parameters, "(@ai@as)", &ids, &property_names);
        GVariantBuilder result;
        g_variant_builder_init(&result, G_VARIANT_TYPE("a(ia{sv})"));
        GVariantIter iterator;
        gint32 id = 0;
        g_variant_iter_init(&iterator, ids);
        while (g_variant_iter_next(&iterator, "i", &id)) {
            if (menu_item_is_valid(id)) {
                g_variant_builder_add(&result, "(i@a{sv})", id, menu_properties(id));
            }
        }
        g_variant_unref(ids);
        g_variant_unref(property_names);
        g_dbus_method_invocation_return_value(
            invocation,
            g_variant_new("(@a(ia{sv}))", g_variant_builder_end(&result)));
        return;
    }
    if (g_strcmp0(method_name, "GetProperty") == 0) {
        gint32 id = 0;
        const gchar *name = NULL;
        g_variant_get(parameters, "(i&s)", &id, &name);
        GVariant *value = menu_property(id, name);
        if (value == NULL) value = g_variant_new_string("");
        g_dbus_method_invocation_return_value(invocation, g_variant_new("(v)", value));
        return;
    }
    if (g_strcmp0(method_name, "Event") == 0) {
        gint32 id = 0;
        const gchar *event_name = NULL;
        GVariant *data = NULL;
        guint32 timestamp = 0;
        g_variant_get(parameters, "(i&s@vu)", &id, &event_name, &data, &timestamp);
        (void)timestamp;
        if (g_strcmp0(event_name, "clicked") == 0) invoke_action_for_menu_item(id);
        g_variant_unref(data);
        g_dbus_method_invocation_return_value(invocation, NULL);
        return;
    }
    if (g_strcmp0(method_name, "EventGroup") == 0) {
        GVariant *events = g_variant_get_child_value(parameters, 0);
        gsize event_count = g_variant_n_children(events);
        for (gsize index = 0; index < event_count; index++) {
            GVariant *event = g_variant_get_child_value(events, index);
            gint32 id = 0;
            const gchar *event_name = NULL;
            GVariant *data = NULL;
            guint32 timestamp = 0;
            g_variant_get(event, "(i&s@vu)", &id, &event_name, &data, &timestamp);
            (void)timestamp;
            if (g_strcmp0(event_name, "clicked") == 0) invoke_action_for_menu_item(id);
            g_variant_unref(data);
            g_variant_unref(event);
        }
        g_variant_unref(events);
        g_dbus_method_invocation_return_value(
            invocation,
            g_variant_new("(@ai)", empty_int_array()));
        return;
    }
    if (g_strcmp0(method_name, "AboutToShow") == 0) {
        g_dbus_method_invocation_return_value(invocation, g_variant_new("(b)", FALSE));
        return;
    }
    if (g_strcmp0(method_name, "AboutToShowGroup") == 0) {
        g_dbus_method_invocation_return_value(
            invocation,
            g_variant_new("(@ai@ai)", empty_int_array(), empty_int_array()));
        return;
    }
    g_dbus_method_invocation_return_dbus_error(
        invocation,
        "com.canonical.dbusmenu.Error.UnknownMethod",
        "Unknown dbusmenu method");
}

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
    (void)user_data;
    if (g_strcmp0(interface_name, "com.canonical.dbusmenu") == 0) {
        handle_menu_method_call(method_name, parameters, invocation);
        return;
    }
    if (g_strcmp0(method_name, "Activate") == 0
        || g_strcmp0(method_name, "SecondaryActivate") == 0) {
        if (tray.callback != NULL) {
            tray.callback(CODEXBAR_TRAY_ACTION_ACTIVATE, tray.context);
        }
    }
    /* ContextMenu deliberately returns without toggling the window. The host opens /MenuBar. */
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
    (void)error;
    (void)user_data;
    if (g_strcmp0(interface_name, "com.canonical.dbusmenu") == 0) {
        if (g_strcmp0(property_name, "Version") == 0) return g_variant_new_uint32(3);
        if (g_strcmp0(property_name, "TextDirection") == 0) return g_variant_new_string("ltr");
        if (g_strcmp0(property_name, "Status") == 0) return g_variant_new_string("normal");
        if (g_strcmp0(property_name, "IconThemePath") == 0) return g_variant_new_strv(NULL, 0);
        return NULL;
    }
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
    if (g_strcmp0(property_name, "Menu") == 0) return g_variant_new_object_path("/MenuBar");
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
    if (tray.connection == NULL || tray.item_registration_id == 0) return;
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
    CodexBarTrayActionCallback callback,
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
    tray.item_registration_id = g_dbus_connection_register_object(
        tray.connection,
        "/StatusNotifierItem",
        tray.node_info->interfaces[0],
        &interface_vtable,
        NULL,
        NULL,
        &error);
    if (tray.item_registration_id == 0) {
        if (error != NULL) g_error_free(error);
        codexbar_tray_remove();
        return false;
    }
    tray.menu_registration_id = g_dbus_connection_register_object(
        tray.connection,
        "/MenuBar",
        tray.node_info->interfaces[1],
        &interface_vtable,
        NULL,
        NULL,
        &error);
    if (tray.menu_registration_id == 0) {
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
    if (tray.connection != NULL && tray.item_registration_id != 0) {
        g_dbus_connection_unregister_object(tray.connection, tray.item_registration_id);
    }
    if (tray.connection != NULL && tray.menu_registration_id != 0) {
        g_dbus_connection_unregister_object(tray.connection, tray.menu_registration_id);
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
#include <shellapi.h>
#include <stdlib.h>
#include <windows.h>

#define CODEXBAR_TRAY_MESSAGE (WM_APP + 42)
#define CODEXBAR_MENU_COMMAND_SHOW 1001
#define CODEXBAR_MENU_COMMAND_REFRESH 1002
#define CODEXBAR_MENU_COMMAND_SETTINGS 1003
#define CODEXBAR_MENU_COMMAND_ABOUT 1004
#define CODEXBAR_MENU_COMMAND_QUIT 1005

static HWND tray_window = NULL;
static HICON tray_icon = NULL;
static CodexBarTrayActionCallback tray_callback = NULL;
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

static void show_context_menu(void)
{
    HMENU menu = CreatePopupMenu();
    if (menu == NULL) return;
    AppendMenuW(menu, MF_STRING, CODEXBAR_MENU_COMMAND_SHOW, L"Show CodexBar");
    AppendMenuW(menu, MF_STRING, CODEXBAR_MENU_COMMAND_REFRESH, L"Refresh");
    AppendMenuW(menu, MF_STRING, CODEXBAR_MENU_COMMAND_SETTINGS, L"Settings...");
    AppendMenuW(menu, MF_STRING, CODEXBAR_MENU_COMMAND_ABOUT, L"About CodexBar");
    AppendMenuW(menu, MF_SEPARATOR, 0, NULL);
    AppendMenuW(menu, MF_STRING, CODEXBAR_MENU_COMMAND_QUIT, L"Quit");
    POINT point;
    GetCursorPos(&point);
    SetForegroundWindow(tray_window);
    UINT command = TrackPopupMenu(
        menu,
        TPM_RETURNCMD | TPM_RIGHTBUTTON,
        point.x,
        point.y,
        0,
        tray_window,
        NULL);
    DestroyMenu(menu);
    if (tray_callback == NULL) return;
    switch (command) {
    case CODEXBAR_MENU_COMMAND_SHOW:
        tray_callback(CODEXBAR_TRAY_ACTION_SHOW, tray_context);
        break;
    case CODEXBAR_MENU_COMMAND_REFRESH:
        tray_callback(CODEXBAR_TRAY_ACTION_REFRESH, tray_context);
        break;
    case CODEXBAR_MENU_COMMAND_SETTINGS:
        tray_callback(CODEXBAR_TRAY_ACTION_SETTINGS, tray_context);
        break;
    case CODEXBAR_MENU_COMMAND_ABOUT:
        tray_callback(CODEXBAR_TRAY_ACTION_ABOUT, tray_context);
        break;
    case CODEXBAR_MENU_COMMAND_QUIT:
        tray_callback(CODEXBAR_TRAY_ACTION_QUIT, tray_context);
        break;
    default:
        break;
    }
}

static LRESULT CALLBACK tray_window_proc(HWND window, UINT message, WPARAM wparam, LPARAM lparam)
{
    (void)wparam;
    if (message == CODEXBAR_TRAY_MESSAGE) {
        UINT event = LOWORD(lparam);
        if (event == WM_LBUTTONUP && tray_callback != NULL) {
            tray_callback(CODEXBAR_TRAY_ACTION_ACTIVATE, tray_context);
        } else if (event == WM_RBUTTONUP || event == WM_CONTEXTMENU) {
            show_context_menu();
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
    CodexBarTrayActionCallback callback,
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
    CodexBarTrayActionCallback callback,
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
