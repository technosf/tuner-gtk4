/**
 * SPDX-FileCopyrightText: Copyright © 2020-2024 Louis Brauer <louis@brauer.family>
 * SPDX-FileCopyrightText: Copyright © 2024 technosf <https://github.com/technosf>
 * SPDX-FileCopyrightText: Copyright © 2026 technosf <https://github.com/technosf>
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * @file HistoryButton.vala
 *
 * @brief The header bar's history button and its popover, ported from the GTK3 HistoryButton: summary tiles,
 * copy and clear, the session history, and the All Time list behind the All Time tile.
 */

namespace TunerGtk4
{
    public class HistoryButton : Gtk.Box
    {
        private const int MIN_LIST_WIDTH_PX = 340;
        private const int MAX_LIST_WIDTH_PX = 620;     // The popover widens to fit the longest entry, up to this
        private const uint LIST_FADE_MS = 400;        // Switching between the session and All Time lists
        private const int MAX_ROW_TEXT_CHARS = 48;
        private const uint CLOSE_DELAY_MS = 300;

        /** @brief A row of the session history was clicked: play its station */
        public signal void station_selected (Tuner.Models.Station station);

        /** @brief A row of the All Time list was clicked: play its station */
        public signal void station_uuid_selected (string station_uuid);

        private Tuner.Models.History _history;
        private Tuner.Models.HeartedArchive _archive;
        private Gtk.MenuButton _button;           // GtkMenuButton is final in GTK4: this box holds one
        private Gtk.Popover _popover;
        private Gtk.ScrolledWindow _scroller;
        private Gtk.Stack _stack;
        private Gtk.ListBox _session_list;
        private Gtk.ListBox _all_time_list;
        private Gtk.Label _plays_value;
        private Gtk.Label _changes_value;
        private Gtk.Label _hearted_value;
        private Gtk.Label _all_time_value;
        private Gtk.Label _total_time;
        private Gtk.Widget _all_time_tile;
        private Gtk.Button _copy_button;
        private Gtk.Button _clear_button;
        private Gtk.Popover? _row_menu = null;
        private Gee.HashMap<Tuner.Models.HistoryEntry, Gtk.ListBoxRow> _rows =
            new Gee.HashMap<Tuner.Models.HistoryEntry, Gtk.ListBoxRow> ();
        private bool _showing_all_time = false;
        private bool _all_time_stale = true;


        public HistoryButton (Tuner.CoreSession core)
        {
            Object (orientation: Gtk.Orientation.HORIZONTAL, spacing: 0);
            _history = core.history;
            _archive = core.all_time;

            _button = new Gtk.MenuButton ();
            _button.icon_name = "mark-location-symbolic";
            _button.valign = Gtk.Align.CENTER;
            _button.tooltip_text = _("History");
            _button.add_css_class ("raised");
            append (_button);

            build_popover ();
            _button.popover = _popover;
            new FadingPopover (_popover);

            _popover.show.connect (() =>
            {
                // Always open on the session history; All Time is one click away on the summary tile
                set_all_time_view (false);
                refresh_summary ();
                refresh_rows ();
                refresh_all_time ();      // both lists are built, so the popover is sized for the longer of them from the start
            });

            _history.entry_added_sig.connect ((entry) => { add_row (entry); });
            _history.entry_removed_sig.connect ((entry) => { remove_row (entry); });
            _history.entry_changed_sig.connect ((entry) => { rebuild_row_for (entry); refresh_summary (); });
            _history.cleared_sig.connect (() => { clear_rows (); });
            _archive.changed_sig.connect (() =>
            {
                _all_time_stale = true;
                if (_showing_all_time)
                    refresh_all_time ();
                refresh_summary ();
            });
            core.events.playback_time_tick_sig.connect ((station, total, here) =>
            {
                if (!_popover.visible)
                    return;
                refresh_summary ();
                if (_row_menu != null && _row_menu.visible)
                    return;                  // leave the rows alone while one has its menu open
                foreach (var entry in _history.entries)
                {
                    if (entry.playing)
                        rebuild_row_for (entry);
                }
            });

            foreach (var entry in _history.entries)
                add_row (entry);
            refresh_summary ();
        } // HistoryButton


        private void build_popover ()
        {
            _popover = new Gtk.Popover ();
            _popover.position = Gtk.PositionType.BOTTOM;
            _popover.add_css_class ("history-popover");

            var content = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            content.margin_top = 10;
            content.margin_bottom = 10;
            content.margin_start = 10;
            content.margin_end = 10;

            // Summary tiles; All Time is a button that switches the list
            var summary = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
            summary.homogeneous = true;
            summary.add_css_class ("history-summary-box");
            // TRANSLATORS: History summary tile: the number of tracks played this session
            summary.append (create_tile (_("Tracks"), out _plays_value));
            // TRANSLATORS: History summary tile: the number of stations played this session
            summary.append (create_tile (C_("history summary", "Stations"), out _changes_value));
            // TRANSLATORS: History summary tile: the number of tracks marked with a heart this session
            summary.append (create_tile (_("Hearted"), out _hearted_value));
            // The same kind of tile as the other three, so it is the same size; a click switches the list
            // TRANSLATORS: History summary tile that shows the hearted tracks kept for all time
            _all_time_tile = create_tile (_("All Time ♥"), out _all_time_value);
            _all_time_tile.tooltip_text = _("Hearted tracks saved for All Time");
            _all_time_tile.cursor = new Gdk.Cursor.from_name ("pointer", null);
            var all_time_click = new Gtk.GestureClick ();
            all_time_click.button = Gdk.BUTTON_PRIMARY;
            all_time_click.released.connect ((n_press, x, y) => { set_all_time_view (!_showing_all_time); });
            _all_time_tile.add_controller (all_time_click);
            summary.append (_all_time_tile);
            content.append (summary);

            // Copy, clear and the total time
            var action_row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
            action_row.margin_top = 10;
            action_row.margin_bottom = 10;
            action_row.add_css_class ("history-action-row");

            _copy_button = new Gtk.Button.from_icon_name ("edit-copy-symbolic");
            _copy_button.tooltip_text = _("Copy history to clipboard");
            _copy_button.clicked.connect (() =>
            {
                get_clipboard ().set_text (_showing_all_time ? _archive.build_clipboard_text ()
                                                             : _history.build_clipboard_text ());
                Fade.close_popover (_popover);
            });
            _clear_button = new Gtk.Button.from_icon_name ("edit-clear-symbolic");
            _clear_button.tooltip_text = _("Clear history");
            _clear_button.clicked.connect (clear_all_items);

            var spacer = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            spacer.hexpand = true;

            _total_time = new Gtk.Label (Tuner.format_duration (_history.total_played_seconds));
            _total_time.width_chars = 7;
            _total_time.xalign = 1.0f;
            _total_time.margin_end = 12;
            _total_time.tooltip_text = _("Total play time");
            _total_time.add_css_class ("history-total-time");

            action_row.append (_copy_button);
            action_row.append (_clear_button);
            action_row.append (spacer);
            action_row.append (_total_time);
            content.append (action_row);

            // The two lists; only the visible one sizes the popover
            _session_list = make_list ();
            var empty = new Gtk.Label (_("No tracks yet this session. Click All Time ♥ above to see your hearted tracks."));
            empty.wrap = true;
            empty.max_width_chars = 32;
            empty.margin_top = empty.margin_bottom = empty.margin_start = empty.margin_end = 24;
            empty.sensitive = false;
            _session_list.set_placeholder (empty);
            _all_time_list = make_list ();

            _stack = new Gtk.Stack ();
            // As wide as the longest entry of either list, so the popover keeps its width, and the four tiles their
            // places, when the list is switched; the switch fades
            _stack.hhomogeneous = true;
            _stack.vhomogeneous = false;
            _stack.transition_type = Gtk.StackTransitionType.CROSSFADE;
            _stack.transition_duration = LIST_FADE_MS;
            _stack.add_named (_session_list, "history");
            _stack.add_named (_all_time_list, "all-time");

            _scroller = new Gtk.ScrolledWindow ();
            _scroller.hscrollbar_policy = Gtk.PolicyType.NEVER;
            _scroller.propagate_natural_width = true;
            _scroller.min_content_width = MIN_LIST_WIDTH_PX;
            _scroller.max_content_width = MAX_LIST_WIDTH_PX;
            _scroller.min_content_height = 320;
            _scroller.max_content_height = 420;
            _scroller.child = _stack;
            content.append (_scroller);

            _popover.child = content;
        } // build_popover


        private static Gtk.ListBox make_list ()
        {
            var list = new Gtk.ListBox ();
            list.selection_mode = Gtk.SelectionMode.NONE;
            list.activate_on_single_click = true;
            list.add_css_class ("history-list");
            return list;
        } // make_list


        private static Gtk.Widget create_tile (string caption, out Gtk.Label value_label)
        {
            var tile = new Gtk.Box (Gtk.Orientation.VERTICAL, 2);
            tile.hexpand = true;
            tile.margin_top = 4;
            tile.margin_bottom = 4;
            tile.margin_start = 6;
            tile.margin_end = 6;
            tile.add_css_class ("history-summary-tile");

            value_label = new Gtk.Label ("0");
            value_label.xalign = 0.5f;
            value_label.add_css_class ("history-summary-value");

            var caption_label = new Gtk.Label (caption);
            caption_label.xalign = 0.5f;
            caption_label.add_css_class ("history-summary-caption");

            tile.append (value_label);
            tile.append (caption_label);
            return tile;
        } // create_tile


        // ----------------------------------------------------------
        // Actions
        // ----------------------------------------------------------

        private void clear_all_items ()
        {
            if (!_showing_all_time)
            {
                _history.clear_preserving_last ();
                return;
            }
            if (_archive.count == 0)
                return;

            // The All Time list is permanent, so confirm before wiping it
            Fade.close_popover (_popover);
            var dialog = new Gtk.AlertDialog (_("Clear the All Time list?"));
            dialog.detail = _("This permanently removes all hearted tracks saved for All Time.");
            // TRANSLATORS: Buttons of the confirmation dialog
            dialog.buttons = { C_("button", "Cancel"), C_("button", "Clear") };
            dialog.cancel_button = 0;
            dialog.default_button = 0;
            dialog.choose.begin (get_root () as Gtk.Window, null, (obj, res) =>
            {
                try
                {
                    if (dialog.choose.end (res) == 1)
                        _archive.clear ();
                }
                catch (Error e)
                {
                    debug ("Clear All Time not confirmed: %s", e.message);
                }
            });
        } // clear_all_items


        private void set_all_time_view (bool all_time)
        {
            _showing_all_time = all_time;
            _stack.visible_child_name = all_time ? "all-time" : "history";

            if (all_time)
                _all_time_tile.add_css_class ("history-summary-tile-active");
            else
                _all_time_tile.remove_css_class ("history-summary-tile-active");

            _copy_button.tooltip_text = all_time ? _("Copy All Time list to clipboard") : _("Copy history to clipboard");
            _clear_button.tooltip_text = all_time ? _("Clear All Time list") : _("Clear history");
            _total_time.tooltip_text = all_time ? _("Total All Time play time") : _("Total play time");

            if (all_time)
                refresh_all_time ();
            refresh_summary ();
        } // set_all_time_view


        private void refresh_summary ()
        {
            _plays_value.label = _history.entries.size.to_string ();
            _changes_value.label = _history.station_change_count.to_string ();
            _hearted_value.label = _history.hearted_track_count.to_string ();
            _all_time_value.label = _archive.count.to_string ();
            _total_time.label = Tuner.format_duration (_showing_all_time ? _archive.total_played_seconds
                                                                          : _history.total_played_seconds);
            _button.sensitive = _history.entries.size > 0 || _archive.count > 0;
            _scroller.min_content_height = _history.entries.size > 12 ? 420 : 320;
        } // refresh_summary


        // ----------------------------------------------------------
        // The session history
        // ----------------------------------------------------------

        private void add_row (Tuner.Models.HistoryEntry entry)
        {
            var row = new Gtk.ListBoxRow ();
            row.activatable = true;
            row.selectable = false;
            row.add_css_class ("history-row");
            rebuild_row (row, entry);
            _rows.set (entry, row);
            _session_list.insert (row, 0);
            refresh_row_styles (_session_list);
            refresh_summary ();
        } // add_row


        private void remove_row (Tuner.Models.HistoryEntry entry)
        {
            var row = _rows.get (entry);
            if (row == null)
                return;
            _session_list.remove (row);
            _rows.unset (entry);
            refresh_row_styles (_session_list);
            refresh_summary ();
        } // remove_row


        private void clear_rows ()
        {
            foreach (var row in _rows.values)
                _session_list.remove (row);
            _rows.clear ();
            refresh_summary ();
        } // clear_rows


        private void refresh_rows ()
        {
            foreach (var entry in _history.entries)
                rebuild_row_for (entry);
        } // refresh_rows


        private void rebuild_row_for (Tuner.Models.HistoryEntry entry)
        {
            var row = _rows.get (entry);
            if (row != null)
                rebuild_row (row, entry);
        } // rebuild_row_for


        private void rebuild_row (Gtk.ListBoxRow row, Tuner.Models.HistoryEntry entry)
        {
            var meta = build_meta_box ();
            var time_label = new Gtk.Label (Tuner.format_duration (entry.get_total_played_seconds ()));
            time_label.width_chars = 7;
            time_label.xalign = 1.0f;
            time_label.add_css_class ("history-play-time");
            meta.append (time_label);

            if (entry.hearted)
            {
                var heart = new Gtk.Label ("♥");
                heart.valign = Gtk.Align.START;
                heart.halign = Gtk.Align.END;
                heart.add_css_class ("history-heart-badge");
                meta.append (heart);
                row.add_css_class ("history-row-hearted");
            }
            else
                row.remove_css_class ("history-row-hearted");

            var shell = build_row_content (entry.station.name, entry.get_display_title (), entry.hearted, meta);
            attach_clicks (shell,
                () => { station_selected (entry.station); close_soon (); },
                (x, y) =>
                {
                    show_row_menu (shell, x, y,
                        Tuner.Services.MusicBrainzSearch.build_term (entry.title, entry.station.name), null, null);
                });
            row.child = shell;
            row.tooltip_text = entry.get_display_title ();
        } // rebuild_row


        // ----------------------------------------------------------
        // The All Time list
        // ----------------------------------------------------------

        private void refresh_all_time ()
        {
            if (!_all_time_stale)
                return;

            Gtk.Widget? old;
            while ((old = _all_time_list.get_first_child ()) != null)
                _all_time_list.remove (old);

            var tracks = _archive.tracks;
            for (int index = tracks.size - 1; index >= 0; index--)
                _all_time_list.append (build_all_time_row (tracks[index]));

            refresh_row_styles (_all_time_list);
            _all_time_stale = false;
        } // refresh_all_time


        private Gtk.ListBoxRow build_all_time_row (Tuner.Models.ArchivedTrack track)
        {
            var row = new Gtk.ListBoxRow ();
            row.activatable = track.station_uuid != "";       // Tracks saved by older versions have no station to go to
            row.selectable = false;
            row.add_css_class ("history-row");
            row.add_css_class ("history-row-hearted");

            var meta = build_meta_box ();
            var time_label = new Gtk.Label (Tuner.format_duration (track.played_seconds));
            time_label.xalign = 1.0f;
            time_label.add_css_class ("history-play-time");
            var date_label = new Gtk.Label (track.format_played_at ());
            date_label.xalign = 1.0f;
            date_label.add_css_class ("history-play-time");
            meta.append (time_label);
            meta.append (date_label);

            var shell = build_row_content (track.station_name, track.title, true, meta);
            attach_clicks (shell,
                () =>
                {
                    if (track.station_uuid != "")
                    {
                        station_uuid_selected (track.station_uuid);
                        close_soon ();
                    }
                },
                (x, y) =>
                {
                    show_row_menu (shell, x, y,
                        Tuner.Services.MusicBrainzSearch.build_term (track.title, track.station_name),
                        _("Remove from All Time"), () => { _archive.remove (track); });
                });
            row.child = shell;
            row.tooltip_text = track.title;
            return row;
        } // build_all_time_row


        // ----------------------------------------------------------
        // Row building shared by both lists
        // ----------------------------------------------------------

        private delegate void ClickAction ();
        private delegate void MenuRequest (double x, double y);
        private delegate void MenuAction ();

        private static void refresh_row_styles (Gtk.ListBox list)
        {
            int index = 0;
            for (var child = list.get_first_child (); child != null; child = child.get_next_sibling ())
            {
                if (!(child is Gtk.ListBoxRow))
                    continue;
                if ((index % 2) == 1)
                    child.add_css_class ("history-row-alt");
                else
                    child.remove_css_class ("history-row-alt");
                index++;
            }
        } // refresh_row_styles


        private static Gtk.Box build_meta_box ()
        {
            var meta = new Gtk.Box (Gtk.Orientation.VERTICAL, 4);
            meta.valign = Gtk.Align.START;
            meta.halign = Gtk.Align.END;
            meta.margin_start = 8;
            return meta;
        } // build_meta_box


        private static Gtk.Box build_row_content (string station_name, string title, bool hearted, Gtk.Widget meta)
        {
            var shell = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 10);
            shell.margin_top = 8;
            shell.margin_bottom = 8;
            shell.margin_start = 10;
            shell.margin_end = 10;

            var text_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 3);
            text_box.hexpand = true;

            var station_label = new Gtk.Label (station_name);
            station_label.xalign = 0.0f;
            station_label.max_width_chars = MAX_ROW_TEXT_CHARS;
            station_label.ellipsize = Pango.EllipsizeMode.END;
            station_label.add_css_class ("history-row-station");

            var title_label = new Gtk.Label (title);
            title_label.xalign = 0.0f;
            title_label.wrap = true;
            title_label.wrap_mode = Pango.WrapMode.WORD_CHAR;
            title_label.max_width_chars = MAX_ROW_TEXT_CHARS;
            title_label.ellipsize = Pango.EllipsizeMode.END;
            title_label.tooltip_text = title;
            title_label.add_css_class ("history-row-title");
            if (hearted)
                title_label.add_css_class ("history-row-title-hearted");

            text_box.append (station_label);
            text_box.append (title_label);
            shell.append (text_box);
            shell.append (meta);
            return shell;
        } // build_row_content


        /** A click on a row plays its station; a right click opens its menu. */
        private static void attach_clicks (Gtk.Widget shell, owned ClickAction on_click, owned MenuRequest on_menu)
        {
            var primary = new Gtk.GestureClick ();
            primary.button = 1;
            primary.released.connect ((n, x, y) => { on_click (); });
            shell.add_controller (primary);

            var secondary = new Gtk.GestureClick ();
            secondary.button = 3;
            secondary.pressed.connect ((n, x, y) => { secondary.set_state (Gtk.EventSequenceState.CLAIMED); });
            secondary.released.connect ((n, x, y) => { on_menu (x, y); });     // on release, so the press is finished first
            shell.add_controller (secondary);
        } // attach_clicks


        private void show_row_menu (Gtk.Widget row, double x, double y, string term, string? extra_label,
                                    owned MenuAction? extra)
        {
            if (term == "" && extra == null)
                return;

            // One menu popover for the whole history popover, parented once; only its content changes
            if (_row_menu == null)
            {
                _row_menu = new Gtk.Popover ();
                _row_menu.has_arrow = false;
                _row_menu.set_parent (_popover.child);
            }
            else
                _row_menu.popdown ();

            var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            if (term != "")
            {
                var search = new Gtk.Button ();
                var label = new Gtk.Label (_("Search for track on MusicBrainz"));
                label.xalign = 0;
                search.child = label;
                search.add_css_class ("flat");
                search.clicked.connect (() =>
                {
                    _row_menu.popdown ();
                    new Gtk.UriLauncher (Tuner.Services.MusicBrainzSearch.build_url (term))
                        .launch.begin (get_root () as Gtk.Window, null);
                });
                box.append (search);
            }
            if (extra != null)
            {
                var item = new Gtk.Button ();
                var label = new Gtk.Label (extra_label);
                label.xalign = 0;
                item.child = label;
                item.add_css_class ("flat");
                item.clicked.connect (() =>
                {
                    _row_menu.popdown ();
                    Idle.add_once (() => { extra (); });     // once the menu has let go, not in its own click
                });
                box.append (item);
            }

            // The menu hangs from the popover's own content, not the row: rows are rebuilt as the history changes, and a
            // popover left on a row that is destroyed is orphaned ("broken accounting of active state") and stops working
            var anchor = _popover.child;
            Graphene.Point at;
            var from = Graphene.Point ();
            from.init ((float) x, (float) y);
            if (!row.compute_point (anchor, from, out at))
                at = from;
            double ax = at.x;
            double ay = at.y;

            _row_menu.child = box;
            _row_menu.set_pointing_to ({ (int) ax, (int) ay, 1, 1 });
            _row_menu.popup ();
        } // show_row_menu


        private void close_soon ()
        {
            Timeout.add_once (CLOSE_DELAY_MS, () => { Fade.close_popover (_popover); });
        } // close_soon
    } // HistoryButton
}
