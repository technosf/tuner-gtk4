/**
 * SPDX-FileCopyrightText: Copyright © 2026 technosf <https://github.com/technosf>
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * @file PreferencesWindow.vala
 *
 * @brief The core's settings that a frontend may show.
 */

namespace TunerGtk4
{
    /**
     * @class PreferencesWindow
     * @brief Switches bound to the core's settings, and the theme.
     *
     * The settings object is the core's; binding the switches to its properties is all the window does. Changes
     * take effect at once and are saved by GSettings.
     */
    public class PreferencesWindow : Gtk.Window
    {
        private const string[] THEMES = { "system", "light", "dark" };

        public PreferencesWindow (Gtk.Window parent, Tuner.Settings settings)
        {
            Object (transient_for: parent, modal: true, title: _("Preferences"));
            Fade.window_in (this);
            default_width = 460;

            var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 10);
            box.margin_top = 16;
            box.margin_bottom = 16;
            box.margin_start = 16;
            box.margin_end = 16;

            add_switch (box, settings, "auto-play", _("Play the last station when Tuner starts"));
            add_switch (box, settings, "start-on-starred", _("Start on the starred stations"));
            add_switch (box, settings, "inhibit-sleep", _("Keep the computer from suspending while playing"));
            add_switch (box, settings, "play-restart", _("Restart playback when the network returns"));
            add_switch (box, settings, "do-not-vote", _("Do not send listens and votes to the directory"));
            add_switch (box, settings, "save-all-time-hearted", _("Keep hearted tracks for All Time"));

            // Theme
            // A StringList, not from_strings(): that wants a NULL-terminated array, which a Vala const array is not
            var names = new Gtk.StringList (null);
            foreach (var name in THEMES)
                names.append (name);
            var dropdown = new Gtk.DropDown (names, null);
            for (uint i = 0; i < THEMES.length; i++)
            {
                if (THEMES[i] == settings.theme_mode)
                    dropdown.selected = i;
            }
            dropdown.notify["selected"].connect (() =>
            {
                if (dropdown.selected < THEMES.length)
                    settings.theme_mode = THEMES[dropdown.selected];
            });
            var theme_label = new Gtk.Label (_("Theme"));
            theme_label.xalign = 0;
            theme_label.hexpand = true;
            var theme_row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12);
            theme_row.append (theme_label);
            theme_row.append (dropdown);
            box.append (theme_row);

            var note = new Gtk.Label (_("These settings are shared with the GTK3 app."));
            note.xalign = 0;
            note.add_css_class ("dim-label");
            box.append (note);

            var close_button = new Gtk.Button.with_label (C_("button", "Close"));
            close_button.halign = Gtk.Align.END;
            close_button.clicked.connect (() => { close (); });
            box.append (close_button);

            child = box;
        } // PreferencesWindow


        private static void add_switch (Gtk.Box box, Tuner.Settings settings, string property, string text)
        {
            var label = new Gtk.Label (text);
            label.xalign = 0;
            label.hexpand = true;
            label.wrap = true;

            var toggle = new Gtk.Switch ();
            toggle.valign = Gtk.Align.CENTER;
            settings.bind_property (property, toggle, "active", BindingFlags.BIDIRECTIONAL | BindingFlags.SYNC_CREATE);

            var row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12);
            row.append (label);
            row.append (toggle);
            box.append (row);
        } // add_switch
    } // PreferencesWindow
} // TunerGtk4
