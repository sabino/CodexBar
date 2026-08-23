#ifndef CODEXBAR_GDK_X11_SHIM_H
#define CODEXBAR_GDK_X11_SHIM_H

#include <gtk/gtk.h>
#include <gdk/x11/gdkx.h>
#include <X11/Xatom.h>

// GTK 4 deliberately removed the old cross-desktop utility-window hint. Set the
// standard EWMH role before the first map on X11 so tiling window managers treat
// the compact tray panel as a floating utility. Wayland and non-X11 backends
// simply keep GTK's normal window behavior.
static inline void codexbar_configure_compact_x11_window(GtkWindow *window) {
    gtk_window_set_decorated(window, FALSE);
    gtk_widget_realize(GTK_WIDGET(window));

    GdkSurface *surface = gtk_native_get_surface(GTK_NATIVE(window));
    if (surface == NULL || !GDK_IS_X11_SURFACE(surface)) {
        return;
    }

    gdk_x11_surface_set_skip_taskbar_hint(surface, TRUE);
    gdk_x11_surface_set_skip_pager_hint(surface, TRUE);

    GdkDisplay *display = gdk_surface_get_display(surface);
    Display *xdisplay = gdk_x11_display_get_xdisplay(display);
    Window xid = gdk_x11_surface_get_xid(surface);
    Atom property = XInternAtom(xdisplay, "_NET_WM_WINDOW_TYPE", False);
    Atom utility = XInternAtom(xdisplay, "_NET_WM_WINDOW_TYPE_UTILITY", False);
    XChangeProperty(
        xdisplay,
        xid,
        property,
        XA_ATOM,
        32,
        PropModeReplace,
        (const unsigned char *)&utility,
        1);
    XFlush(xdisplay);
}

#endif
