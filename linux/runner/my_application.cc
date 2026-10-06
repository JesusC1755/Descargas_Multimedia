#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  // Use a modern CSD HeaderBar with custom dark styling to integrate seamlessly
  // with the application's cyber / dark theme across all desktop environments (including Cinnamon).
  GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
  gtk_widget_show(GTK_WIDGET(header_bar));
  gtk_header_bar_set_title(header_bar, "Media Downloader");
  gtk_header_bar_set_show_close_button(header_bar, TRUE);
  gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  gtk_window_set_title(window, "Media Downloader");

  // Apply custom dark cyber styling for the window headerbar and title buttons
  GtkCssProvider* provider = gtk_css_provider_new();
  const gchar* custom_css =
      "headerbar, headerbar:backdrop {"
      "  background: #090812;"
      "  background-image: none;"
      "  border-bottom: 1px solid rgba(56, 189, 248, 0.22);"
      "  box-shadow: 0 2px 10px rgba(0, 0, 0, 0.55);"
      "  min-height: 38px;"
      "  padding: 0 8px;"
      "}"
      "headerbar .title, headerbar:backdrop .title {"
      "  color: #ffffff;"
      "  font-weight: 700;"
      "  font-size: 13px;"
      "  letter-spacing: 0.4px;"
      "}"
      "headerbar button.titlebutton, headerbar:backdrop button.titlebutton {"
      "  color: #94a3b8;"
      "  background: transparent;"
      "  border: none;"
      "  border-radius: 6px;"
      "  padding: 4px 6px;"
      "}"
      "headerbar button.titlebutton:hover {"
      "  color: #ffffff;"
      "  background-color: rgba(255, 255, 255, 0.08);"
      "}"
      "headerbar button.titlebutton.close:hover {"
      "  color: #ffffff;"
      "  background-color: #ef4444;"
      "}";
  gtk_css_provider_load_from_data(provider, custom_css, -1, nullptr);
  gtk_style_context_add_provider_for_screen(
      gdk_screen_get_default(),
      GTK_STYLE_PROVIDER(provider),
      GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);
  g_object_unref(provider);

  gtk_window_set_default_size(window, 1280, 720);

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  // Configure window icon for Linux taskbar, dock, and window manager
  const gchar* assets_path = fl_dart_project_get_assets_path(project);
  g_autofree gchar* exe_link = g_file_read_link("/proc/self/exe", nullptr);
  g_autofree gchar* exe_dir = exe_link != nullptr ? g_path_get_dirname(exe_link) : nullptr;

  GList* icon_list = nullptr;
  const gchar* icon_filenames[] = {
      "app_icon_32.png", "app_icon_64.png", "app_icon_128.png",
      "app_icon_256.png", "app_icon.png", nullptr};

  for (int i = 0; icon_filenames[i] != nullptr; i++) {
    g_autofree gchar* icon_file = g_build_filename(
        assets_path, "assets", "icons", icon_filenames[i], nullptr);
    const gchar* resolved_path = icon_file;
    g_autofree gchar* exe_bundle_file = nullptr;
    g_autofree gchar* exe_assets_file = nullptr;
    g_autofree gchar* cwd_file = nullptr;

    if (!g_file_test(resolved_path, G_FILE_TEST_EXISTS) && exe_dir != nullptr) {
      exe_bundle_file = g_build_filename(
          exe_dir, "data", "flutter_assets", "assets", "icons", icon_filenames[i], nullptr);
      if (g_file_test(exe_bundle_file, G_FILE_TEST_EXISTS)) {
        resolved_path = exe_bundle_file;
      }
    }

    if (!g_file_test(resolved_path, G_FILE_TEST_EXISTS) && exe_dir != nullptr) {
      exe_assets_file = g_build_filename(
          exe_dir, "assets", "icons", icon_filenames[i], nullptr);
      if (g_file_test(exe_assets_file, G_FILE_TEST_EXISTS)) {
        resolved_path = exe_assets_file;
      }
    }

    if (!g_file_test(resolved_path, G_FILE_TEST_EXISTS)) {
      cwd_file = g_build_filename("assets", "icons", icon_filenames[i], nullptr);
      if (g_file_test(cwd_file, G_FILE_TEST_EXISTS)) {
        resolved_path = cwd_file;
      }
    }

    if (g_file_test(resolved_path, G_FILE_TEST_EXISTS)) {
      GError* err = nullptr;
      GdkPixbuf* pixbuf = gdk_pixbuf_new_from_file(resolved_path, &err);
      if (pixbuf != nullptr) {
        icon_list = g_list_append(icon_list, pixbuf);
      } else if (err != nullptr) {
        g_clear_error(&err);
      }
    }
  }

  if (icon_list != nullptr) {
    gtk_window_set_icon_list(window, icon_list);
    gtk_window_set_default_icon_list(icon_list);
    g_list_free_full(icon_list, g_object_unref);
  } else {
    g_autofree gchar* fallback_icon = g_build_filename(
        assets_path, "assets", "icons", "app_icon.png", nullptr);
    if (g_file_test(fallback_icon, G_FILE_TEST_EXISTS)) {
      gtk_window_set_icon_from_file(window, fallback_icon, nullptr);
      gtk_window_set_default_icon_from_file(fallback_icon, nullptr);
    }
  }

  gtk_window_set_default_icon_name("com.example.media_downloader");
  gtk_window_set_icon_name(window, "com.example.media_downloader");

  FlView* view = fl_view_new(project);
  GdkRGBA background_color;
  // Background defaults to black, override it here if necessary, e.g. #00000000
  // for transparent.
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  // Show the window when Flutter renders.
  // Requires the view to be realized so we can start rendering.
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;

  return TRUE;
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application startup.

  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application shutdown.

  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {}

MyApplication* my_application_new() {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_NON_UNIQUE, nullptr));
}
