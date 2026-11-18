/**
 * SPDX-FileCopyrightText: Copyright © 2026 technosf <https://github.com/technosf>
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * @file StationRow.vala
 *
 * @brief One station in the list.
 */

namespace TunerGtk4
{
    /**
     * @class StationRow
     * @brief A station as the GTK3 list shows it: favicon, name, a codec badge and the country code.
     *
     * The star and the other actions are on the right-click menu, as in the GTK3 app. The star sends the change to
     * the station; the core's directory controller saves it. The row follows the station's star and favicon, so a
     * change made anywhere shows here.
     *
     * The rows are recycled by the list view: one is made empty, then bound to a station as it scrolls into view and
     * unbound as it leaves.
     */
    public class StationRow : Gtk.Box
    {
        private const string STAR_CHAR = "\u2605 ";
        private const string EXCLAIM_CHAR = "\u26A0 ";

        /** @brief The station shown, or null while the row is not bound to one */
        public Tuner.Models.Station? station { get; private set; default = null; }

        /** @brief The user asked to edit the station's note */
        public signal void note_requested (Tuner.Models.Station station);

        /** @brief The user asked to refresh the station from the provider's index */
        public signal void update_requested (Tuner.Models.Station station);

        /** @brief The user asked for the station's details */

        /** @brief The user asked to move the station up (-1) or down (+1) in the starred order */
        public signal void move_requested (Tuner.Models.Station station, int direction);

        /** @brief Another starred station (by uuid) was dropped on this row: it should take this row's place */
        public signal void station_dropped (string from_uuid, Tuner.Models.Station onto);

        /** @brief The star was changed from this row's menu */
        public signal void star_toggled ();

        private delegate void MenuAction ();

        private Gtk.Image _icon;
        private Gtk.Label _title;
        private Gtk.Label _tag;
        private Gtk.Label _description;
        private Gtk.Box _mover;
        private bool _reorderable = false;
        private Gtk.Popover? _menu = null;
        /** @brief The core's star store, for the menu to tell "Add Note" from "Edit Note" (optional) */
        public Tuner.Services.StarStore? stars { get; set; default = null; }

        private Tuner.Models.StationSession? _session = null;
        private ulong _broken_handler = 0;
        private ulong _recovered_handler = 0;
        private ulong _favicon_handler = 0;
        private ulong _star_handler = 0;


        public StationRow (Tuner.Models.StationSession? session = null)
        {
            Object (orientation: Gtk.Orientation.HORIZONTAL, spacing: 0);
            add_css_class ("station-button");

            _icon = new Gtk.Image ();
            _icon.pixel_size = 48;
            _icon.halign = Gtk.Align.CENTER;
            _icon.valign = Gtk.Align.CENTER;
            _icon.add_css_class ("station-icon");

            _title = new Gtk.Label (null);
            _title.max_width_chars = 25;
            _title.halign = Gtk.Align.START;
            _title.valign = Gtk.Align.END;
            _title.ellipsize = Pango.EllipsizeMode.END;

            _tag = new Gtk.Label ("");
            _tag.halign = Gtk.Align.START;
            _tag.valign = Gtk.Align.START;
            _tag.add_css_class ("tag");
            _tag.add_css_class ("keycap");

            _description = new Gtk.Label ("");
            _description.halign = Gtk.Align.START;
            _description.valign = Gtk.Align.CENTER;
            _description.hexpand = true;
            _description.ellipsize = Pango.EllipsizeMode.MIDDLE;
            _description.add_css_class ("station-button-description");

            // Up and down, for the starred list, whose order the user sets (the GTK3 app drags instead)
            var up = new Gtk.Button.from_icon_name ("go-up-symbolic");
            up.add_css_class ("flat");
            up.add_css_class ("mover-button");
            up.clicked.connect (() => { if (station != null) move_requested (station, -1); });
            var down = new Gtk.Button.from_icon_name ("go-down-symbolic");
            down.add_css_class ("flat");
            down.add_css_class ("mover-button");
            down.clicked.connect (() => { if (station != null) move_requested (station, 1); });
            _mover = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);       // the arrows one above the other, close together
            _mover.valign = Gtk.Align.CENTER;
            _mover.visible = false;
            _mover.append (up);
            _mover.append (down);

            var grid = new Gtk.Grid ();
            grid.column_spacing = 6;
            grid.hexpand = true;
            grid.attach (_icon, 0, 0, 1, 2);
            grid.attach (_title, 1, 0, 2, 1);
            grid.attach (_tag, 1, 1, 1, 1);
            grid.attach (_description, 2, 1, 1, 1);

            margin_top = 0;
            margin_bottom = 0;
            margin_start = 6;
            margin_end = 6;
            append (grid);
            append (_mover);

            // Right click: the station's menu
            var secondary = new Gtk.GestureClick ();
            secondary.button = 3;
            // The menu opens on release: a popover that grabs the pointer in the press leaves the row's press unfinished,
            // which GTK reports as "broken accounting of active state"
            secondary.pressed.connect ((n, x, y) =>
            {
                if (station != null)
                    secondary.set_state (Gtk.EventSequenceState.CLAIMED);
            });
            secondary.released.connect ((n, x, y) =>
            {
                if (station != null)
                    show_menu (x, y);
            });
            add_controller (secondary);

            // Drag this row onto another to move it there (as in the GTK3 app); only while the list can be reordered
            var source = new Gtk.DragSource ();
            source.actions = Gdk.DragAction.MOVE;
            source.prepare.connect ((x, y) =>
            {
                if (!_reorderable || station == null)
                    return null;
                return new Gdk.ContentProvider.for_value (station.stationuuid);
            });
            source.drag_begin.connect ((drag) =>
            {
                Gtk.DragIcon.set_from_paintable (drag, new Gtk.WidgetPaintable (this), 0, 0);
            });
            add_controller (source);

            var target = new Gtk.DropTarget (typeof (string), Gdk.DragAction.MOVE);
            target.enter.connect ((x, y) =>
            {
                if (!_reorderable)
                    return (Gdk.DragAction) 0;
                add_css_class ("drop-over");
                return Gdk.DragAction.MOVE;
            });
            target.leave.connect (() => { remove_css_class ("drop-over"); });
            target.drop.connect ((value, x, y) =>
            {
                remove_css_class ("drop-over");
                string? from_uuid = value.get_string ();
                if (!_reorderable || station == null || from_uuid == null || from_uuid == station.stationuuid)
                    return false;
                station_dropped (from_uuid, station);
                return true;
            });
            add_controller (target);

            // A station that failed to play this session is marked; it clears if the station plays again
            // The session outlives its rows, so its handlers hold the row only weakly
            _session = session;
            if (_session != null)
            {
                var weak = WeakRef (this);
                _broken_handler = _session.station_marked_broken_sig.connect ((s, reason) =>
                {
                    var self = weak.get () as StationRow;
                    if (self != null && s == self.station)
                        self.show_title ();
                });
                _recovered_handler = _session.station_recovered_sig.connect ((s) =>
                {
                    var self = weak.get () as StationRow;
                    if (self != null && s == self.station)
                        self.show_title ();
                });
            }
        } // StationRow


        /**
         * @brief Shows a station in this row.
         *
         * @param reorderable True in the whole starred list, whose order the user can change: the arrows show and the row can be dragged
         */
        public void bind (Tuner.Models.Station station, bool reorderable)
        {
            unbind ();
            this.station = station;

            var codec = station.codec ?? "";
            _tag.label = station.bitrate > 0 ? "%s %dk".printf (codec.up (), station.bitrate) : codec.up ();
            _tag.visible = codec != "";
            _description.label = station.countrycode ?? "";

            _reorderable = reorderable;
            _mover.visible = reorderable;

            // The station outlives its rows, so its handlers hold the row only weakly
            var weak = WeakRef (this);
            _star_handler = station.station_star_changed_sig.connect ((starred) =>
            {
                var self = weak.get () as StationRow;
                if (self != null)
                    self.show_title ();
            });
            _favicon_handler = station.favicon_sig.connect (() =>
            {
                var self = weak.get () as StationRow;
                if (self != null)
                    self.show_favicon (true);       // The picture arrived after the row: the stock icon fades out first
            });

            show_title ();
            show_favicon ();

            if (Tuner.debug_enabled () && _sizes_logged < 3)
            {
                _sizes_logged++;
                var weak_row = WeakRef (this);
                Idle.add (() =>
                {
                    var self = weak_row.get () as StationRow;
                    if (self != null)
                        self.log_sizes ();
                    return Source.REMOVE;
                });
            }
        } // bind


        private static int _sizes_logged = 0;

        /** Debug: the heights of the row and its parts, to see what makes the grid rows tall. */
        private void log_sizes ()
        {
            Gtk.Widget[] parts = { this, _icon, _title, _tag, _description, _mover, get_parent () };
            string[] names = { "row", "icon", "title", "tag", "description", "mover", "parent" };
            var sb = new StringBuilder ("[sizes]");
            for (int i = 0; i < parts.length; i++)
            {
                if (parts[i] == null)
                    continue;
                int min, nat;
                parts[i].measure (Gtk.Orientation.VERTICAL, -1, out min, out nat, null, null);
                sb.append (" %s: min %d nat %d alloc %d;".printf (names[i], min, nat, parts[i].get_height ()));
            }
            debug (sb.str);
        } // log_sizes


        /** @brief The row leaves its station, for the list view to use it for another */
        public void unbind ()
        {
            if (_menu != null)
                _menu.popdown ();
            remove_css_class ("drop-over");
            Fade.cancel (_icon);

            if (station != null)
            {
                if (_star_handler != 0)
                    SignalHandler.disconnect (station, _star_handler);
                if (_favicon_handler != 0)
                    SignalHandler.disconnect (station, _favicon_handler);
            }
            _star_handler = 0;
            _favicon_handler = 0;
            station = null;
        } // unbind


        /** The name, led by a star for a starred station or a warning for one that failed to play. */
        private void show_title ()
        {
            if (station == null)
                return;

            bool broken = _session != null && _session.is_broken (station);
            _title.label = (broken ? EXCLAIM_CHAR : (station.starred ? STAR_CHAR : "")) + station.name;
            if (broken)
            {
                var record = _session.lookup (station);
                _title.tooltip_text = (record != null && record.broken_reason != null)
                    // TRANSLATORS: Followed by the reason the station could not be played
                    ? _("Could not play: ") + record.broken_reason : _("Could not play");
            }
            else
                _title.tooltip_text = null;
        } // show_title


        private void show_menu (double x, double y)
        {
            // One popover for the row's whole life: it is parented once, and only its content changes. Parenting and
            // unparenting popovers as menus come and go upsets GTK's accounting of their state.
            if (_menu == null)
            {
                _menu = new Gtk.Popover ();
                _menu.add_css_class ("menu");
                _menu.add_css_class ("station-menu");
                _menu.has_arrow = false;
                _menu.set_parent (this);
            }
            else
                _menu.popdown ();

            var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);

            box.append (menu_label (station.name));
            var locale = station.locale ();
            if (locale != null && locale != "")
                box.append (menu_label (locale));
            box.append (new Gtk.Separator (Gtk.Orientation.HORIZONTAL));
            box.append (menu_label (station.popularity ()));
            box.append (new Gtk.Separator (Gtk.Orientation.HORIZONTAL));

            // The provider's index has changed since the station was saved
            if (station.starred && !station.is_up_to_date)
            {
                var changes = menu_label (_("Station info updated Online - View changes"));
                changes.sensitive = true;
                changes.tooltip_text = station.up_to_date_difference;
                box.append (changes);
                var update = menu_item (_("Update Station from Online"), () => { update_requested (station); });
                update.sensitive = station.is_in_index;
                box.append (update);
                box.append (new Gtk.Separator (Gtk.Orientation.HORIZONTAL));
            }

            var website = menu_item (_("Visit Website"), () =>
            {
                new Gtk.UriLauncher (station.homepage).launch.begin (get_root () as Gtk.Window, null);
            });
            website.sensitive = station.homepage != null && station.homepage != "";
            box.append (website);

            box.append (menu_item (_("Share stream URI"), () =>
            {
                new ShareStreamWindow (get_root () as Gtk.Window, station).present ();
            }));

            if (station.starred)
            {
                bool has_note = stars != null && stars.has_note (station.stationuuid);
                box.append (menu_item (has_note ? _("Edit Note") : _("Add Note"), () => { note_requested (station); }));
            }

            box.append (new Gtk.Separator (Gtk.Orientation.HORIZONTAL));
            box.append (menu_item (station.starred ? _("\u2606 Unstar this station") : _("\u2605 Star this station"), () =>
            {
                station.toggle_starred ();
                star_toggled ();
            }));

            box.width_request = 260;
            _menu.child = box;
            _menu.set_pointing_to ({ (int) x, (int) y, 1, 1 });
            _menu.popup ();
        } // show_menu


        private const int MENU_MAX_CHARS = 32;     // longer station names in the context menu end in an ellipsis

        private static Gtk.Widget menu_label (string text)
        {
            var label = new Gtk.Label (text);
            label.xalign = 0;
            label.sensitive = false;
            label.ellipsize = Pango.EllipsizeMode.END;
            label.max_width_chars = MENU_MAX_CHARS;
            label.add_css_class ("station-menu-head");
            return label;
        } // menu_label


        private Gtk.Button menu_item (string text, owned MenuAction action)
        {
            var label = new Gtk.Label (text);
            label.xalign = 0;
            var button = new Gtk.Button ();
            button.child = label;
            label.hexpand = true;
            button.hexpand = true;
            button.halign = Gtk.Align.FILL;
            button.valign = Gtk.Align.FILL;
            button.add_css_class ("flat");
            button.add_css_class ("station-menu-item");
            button.clicked.connect (() =>
            {
                _menu.popdown ();
                Idle.add_once (() => { action (); });     // once the menu has let go of the pointer, not in its click
            });
            return button;
        } // menu_item


        public override void dispose ()
        {
            if (_menu != null)
            {
                _menu.popdown ();
                _menu.unparent ();
                _menu = null;
            }
            unbind ();
            if (_session != null)
            {
                if (_broken_handler != 0)
                    SignalHandler.disconnect (_session, _broken_handler);
                if (_recovered_handler != 0)
                    SignalHandler.disconnect (_session, _recovered_handler);
                _broken_handler = 0;
                _recovered_handler = 0;
                _session = null;
            }
            base.dispose ();
        } // dispose


        /** Shows the favicon the core has cached, or the stock station icon until there is one. */
        private const uint FADE_MS = 400;      // As the GTK3 app: the old picture fades out, the new one fades in

        /**
         * Shows the favicon the core has cached, or the stock station icon until there is one.
         *
         * @param fade_swap The row already shows a picture: fade that out before the new one fades in
         */
        private void show_favicon (bool fade_swap = false)
        {
            if (station == null)
                return;

            string? path = station.favicon_failing () ? null : station.favicon_image_file ();
            if (path == null)
            {
                Fade.cancel (_icon);
                _icon.icon_name = "tuner:internet-radio";
                _icon.opacity = 1.0;
                return;
            }

            var shown = station;
            Fade.to (_icon, 0.0, fade_swap ? FADE_MS : 0, () =>
            {
                if (station != shown)       // The row was rebound while it faded
                    return;
                _icon.set_from_file (path);
                Fade.to (_icon, 1.0, FADE_MS);
            });
        } // show_favicon
    } // StationRow


    /**
     * @class SearchRow
     * @brief A saved search, with a button to remove it.
     */
    public class SearchRow : Gtk.Box
    {
        private Gtk.Label _label;

        /** @brief The saved search shown, or "" while the row is not bound to one */
        public string search_text { get; private set; default = ""; }

        /** @brief The user asked to remove this saved search */
        public signal void remove_requested (string search_text);

        public SearchRow ()
        {
            Object (orientation: Gtk.Orientation.HORIZONTAL, spacing: 12);

            _label = new Gtk.Label ("");
            _label.xalign = 0;
            _label.hexpand = true;
            _label.ellipsize = Pango.EllipsizeMode.END;

            // TRANSLATORS: Button that removes a saved search from the list
            var remove = new Gtk.Button.with_label (C_("saved search", "Remove"));
            remove.clicked.connect (() => { remove_requested (search_text); });

            margin_top = 8;
            margin_bottom = 8;
            margin_start = 12;
            margin_end = 12;
            append (_label);
            append (remove);
        } // SearchRow


        /** @brief Shows a saved search in this row */
        public void bind (string search_text)
        {
            this.search_text = search_text;
            _label.label = search_text;
        } // bind
    } // SearchRow
} // TunerGtk4
