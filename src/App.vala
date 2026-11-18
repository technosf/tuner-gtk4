/**
 * SPDX-FileCopyrightText: Copyright © 2026 technosf <https://github.com/technosf>
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * @file App.vala
 *
 * @brief The GTK4 prototype application: a Host for the core.
 */

namespace TunerGtk4
{
    /**
     * @class App
     * @brief Creates the core, shows the main window, and answers the few requests the core makes (Host).
     */
    public class App : Gtk.Application, Tuner.Host
    {
        /** @brief The functional core: every service comes from here */
        public Tuner.CoreSession core { get; private set; }

        private MainWindow? _window = null;
        private uint _inhibit_cookie = 0;           // Suspend inhibitor while playing, or 0
        private bool _playing = false;
        private bool _system_prefers_dark = false;
        private bool _theme_ready = false;


        public App ()
        {
            // GTK finds icons by name (tuner:...) under the application's resource base path. That is normally derived from the
            // application id, which now varies (app_id), so it is fixed here to where data/tuner-gtk4.gresource.xml puts them
            Object (application_id: APP_ID,
                    resource_base_path: "/io/github/tuner_labs/tuner/gtk4",
                    flags: ApplicationFlags.FLAGS_NONE);
        }


        construct
        {
            // The core downloads favicons; this lets it check that a download really is an image
            Tuner.Models.Favicon.image_check = Images.is_decodable;
            Tuner.UserAgent.configure (APP_VERSION, PACKAGING);     // Before the first request: what the directory sees of this build
            core = new Tuner.CoreSession (this, APP_ID);

            // Language: the saved choice (empty: the system's) must be in the environment before any text is looked up
            Intl.bindtextdomain (GETTEXT_PACKAGE, LOCALEDIR);
            Intl.bind_textdomain_codeset (GETTEXT_PACKAGE, "UTF-8");
            Intl.textdomain (GETTEXT_PACKAGE);
            if (core.settings.language != "")
                Environment.set_variable (Tuner.Locales.ENV_LANG, core.settings.language, true);

            // Keep the computer from suspending while a station plays, if the user wants that
            core.events.player_state_changed_sig.connect ((station, state) =>
            {
                _playing = state == Tuner.Models.StreamPlayer.State.PLAYING
                        || state == Tuner.Models.StreamPlayer.State.BUFFERING;
                update_inhibit ();
            });
            core.settings.notify["inhibit-sleep"].connect (() => { update_inhibit (); });
            core.settings.notify["theme-mode"].connect (() => { apply_theme (); });
        }


        /** Choose a language ("" is the system's), then restart, since text is looked up as it is built. */
        public void set_language (string code)
        {
            if (code != "" && !Tuner.Locales.found ().contains (code))
                return;
            if (core.settings.language == code)
                return;
            core.settings.language = code;
            core.settings.save ();
            Environment.set_variable (Tuner.Locales.ENV_LANG, code, true);
            if (_window != null)
                _window.hide ();
            restart ();
        } // set_language


        private void restart ()
        {
            try
            {
                // The arguments as started (NUL separated, so read as bytes), with the real path of the executable
                uint8[] raw;
                FileUtils.get_data ("/proc/self/cmdline", out raw);
                string[] argv = {};
                var part = new StringBuilder ();
                foreach (uint8 b in raw)
                {
                    if (b == 0)
                    {
                        argv += part.str;
                        part = new StringBuilder ();
                    }
                    else
                        part.append_c ((char) b);
                }
                if (argv.length == 0)
                    argv = { Environment.get_prgname () };
                string exe = FileUtils.read_link ("/proc/self/exe");
                if (exe != "")
                    argv[0] = exe;
                Pid pid;
                Process.spawn_async (null, argv, null, SpawnFlags.SEARCH_PATH, null, out pid);
            }
            catch (Error e)
            {
                warning ("Restart failed: %s", e.message);
            }
            quit ();
        } // restart


        protected override void activate ()
        {
            if (_window == null)
            {
                debug ("Tuner GTK4 %s, built with core %s (running core %s); User-Agent: %s", APP_VERSION, BUILT_WITH_CORE_VERSION, Tuner.CORE_VERSION, Tuner.user_agent ());
                apply_theme ();
                Style.load ();
                _window = new MainWindow (this);
                add_window (_window);
                core.start ();                  // Directory connection, MPRIS, starred stations, start-up flows
            }
            _window.present ();
        } // activate


        // ----------------------------------------------------------
        // Tuner.Host
        // ----------------------------------------------------------

        public void play_station_in_ui (Tuner.Models.Station station)
        {
            core.player.play_station (station);
        }

        public void present_window ()
        {
            if (_window != null)
                _window.present ();
        }

        public void choose_starred_stations ()
        {
            if (_window != null)
                _window.show_starred ();
        }

        public bool render_icon (string resource, int size_px, string png_path)
        {
            return false;       // No MPRIS in the prototype, so no stock icon files are needed
        }

        public string? startup_sound_uri ()
        {
            return "resource:///io/github/tuner_labs/tuner/gtk4/sounds/tuner_startup.mp3";
        }

        public void save_view_state ()
        {
            if (_window != null)
                _window.remember_size ();
        }

        /** Holds a suspend inhibitor while a station plays and the preference is on. */
        private void update_inhibit ()
        {
            bool wanted = _playing && core.settings.inhibit_sleep;
            if (wanted && _inhibit_cookie == 0)
            {
                _inhibit_cookie = inhibit (_window, Gtk.ApplicationInhibitFlags.SUSPEND, _("Playing radio"));
            }
            else if (!wanted && _inhibit_cookie != 0)
            {
                uninhibit (_inhibit_cookie);
                _inhibit_cookie = 0;
            }
        } // update_inhibit


        /** Applies the saved theme: "light", "dark", or "system" for whatever the desktop uses. */
        private void apply_theme ()
        {
            var gtk_settings = Gtk.Settings.get_default ();

            // GTK 4.20 and later: gtk-interface-color-scheme replaces gtk-application-prefer-dark-theme (which now
            // warns). Set by name so that this builds against older GTK, which still has the old property.
            bool new_property = gtk_settings.get_class ().find_property ("gtk-interface-color-scheme") != null;
            const int SCHEME_DEFAULT = 1;       // Gtk.InterfaceColorScheme: follow the desktop
            const int SCHEME_DARK    = 2;
            const int SCHEME_LIGHT   = 3;

            if (new_property)
            {
                int scheme;
                switch (core.settings.theme_mode)
                {
                    case "dark":
                        scheme = SCHEME_DARK;
                        break;
                    case "light":
                        scheme = SCHEME_LIGHT;
                        break;
                    default:
                        scheme = SCHEME_DEFAULT;
                        break;
                }
                gtk_settings.set ("gtk-interface-color-scheme", scheme);
                return;
            }

            if (!_theme_ready)
            {
                _system_prefers_dark = gtk_settings.gtk_application_prefer_dark_theme;
                _theme_ready = true;
            }

            switch (core.settings.theme_mode)
            {
                case "dark":
                    gtk_settings.gtk_application_prefer_dark_theme = true;
                    break;
                case "light":
                    gtk_settings.gtk_application_prefer_dark_theme = false;
                    break;
                default:
                    gtk_settings.gtk_application_prefer_dark_theme = _system_prefers_dark;
                    break;
            }
        } // apply_theme


        public void quit_application ()
        {
            quit ();
        }
    } // App
} // TunerGtk4
