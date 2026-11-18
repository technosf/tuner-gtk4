/**
 * SPDX-FileCopyrightText: Copyright © 2026 technosf <https://github.com/technosf>
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * @file NoteWindow.vala
 *
 * @brief Edit the note on a starred station.
 */

namespace TunerGtk4
{
    /**
     * @class NoteWindow
     * @brief A small modal window to read and change a starred station's note. The core trims and limits the text.
     */
    public class NoteWindow : Gtk.Window
    {
        public NoteWindow (Gtk.Window parent, Tuner.CoreSession core, Tuner.Models.Station station)
        {
            Object (transient_for: parent, modal: true, title: station.name);
            Fade.window_in (this);
            default_width = 420;
            default_height = 240;

            var view = new Gtk.TextView ();
            view.wrap_mode = Gtk.WrapMode.WORD_CHAR;
            view.buffer.text = core.stars.get_note (station.stationuuid);
            view.top_margin = 6;
            view.bottom_margin = 6;
            view.left_margin = 6;
            view.right_margin = 6;

            var scroller = new Gtk.ScrolledWindow ();
            scroller.vexpand = true;
            scroller.child = view;

            // TRANSLATORS: %d is the longest note allowed
            var hint = new Gtk.Label (_("Up to %d characters. Empty removes the note.").printf (Tuner.Services.StarStore.NOTE_MAX_CHARS));
            hint.xalign = 0;
            hint.add_css_class ("dim-label");

            var cancel = new Gtk.Button.with_label (C_("button", "Cancel"));
            cancel.clicked.connect (() => { close (); });

            var save = new Gtk.Button.with_label (C_("button", "Save"));
            save.add_css_class ("suggested-action");
            save.clicked.connect (() =>
            {
                core.stars.set_note (station.stationuuid, view.buffer.text);
                close ();
            });

            var buttons = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
            buttons.halign = Gtk.Align.END;
            buttons.append (cancel);
            buttons.append (save);

            var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 8);
            box.margin_top = 12;
            box.margin_bottom = 12;
            box.margin_start = 12;
            box.margin_end = 12;
            box.append (scroller);
            box.append (hint);
            box.append (buttons);

            child = box;
        } // NoteWindow
    } // NoteWindow
} // TunerGtk4
