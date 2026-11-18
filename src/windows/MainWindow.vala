/**
 * SPDX-FileCopyrightText: Copyright © 2026 technosf <https://github.com/technosf>
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * @file MainWindow.vala
 *
 * @brief Search and browse stations, play one, keep notes, saved searches, a history and the hearted tracks.
 */

namespace TunerGtk4
{
    /**
     * @class MainWindow
     * @brief The prototype's only window. It renders core state and sends core commands, nothing else.
     *
     * Reads: the connection state, the station and track playing, the player state, the volume, station lists,
     * the starred stations, saved searches, notes and the session history.
     * Sends: search, save search, play/pause, volume, star, note, heart.
     */
    public class MainWindow : Gtk.ApplicationWindow
    {
        private const uint PAGE_SIZE = 50;

        /** What the list is showing, so history changes can refresh it */
        private enum View
        {
            STATIONS,
            SAVED_SEARCHES
        }

        private App _app;
        private Gtk.SearchEntry _search;
        private Gtk.Button _save_search;
        private Gtk.Label _status;
        private Gtk.Label _loading;                 // The ellipsis after the heading while loading
        private Gtk.GridView _list;                 // Virtualised: only the rows in view exist
        private GLib.ListStore _store;               // What the list shows: stations, or saved-search strings
        private Gtk.SignalListItemFactory _station_factory;
        private Gtk.SignalListItemFactory _search_factory;
        private bool _list_revealing = false;       // The list is fading in
        private bool _list_reorderable = false;      // The whole starred list is on show: its order can be changed
        private MetadataImagePopup _image_popup;
        private NowPlaying _now;
        private Gtk.Popover? _meta_popover = null;
        private Gtk.Label? _meta_label = null;
        private uint _meta_hover_id = 0;
        private string _track_metadata = "";        // Everything the stream last said about itself
        private Gtk.Button _heart;
        private Gtk.Button _play;
        private Gtk.Scale _volume;
        private Gtk.Button _jukebox;
        private Gtk.Button _discover;
        private Gtk.Label _tape;
        private Gtk.Widget? _selected_item = null;
        private Gtk.Button _shuffle;
        private Gtk.Image _play_image;
        private Gtk.MenuButton _menu_button;
        private Gtk.MenuButton _volume_button;
        private TunerStatus _tuner_status;
        private Backdrop _backdrop;
        private Gtk.Label _starred_count;
        private Gtk.Revealer _search_revealer;
        private Gtk.ToggleButton _search_toggle;
        private Gtk.ToggleButton _star_head;
        private Tuner.Models.Station? _star_station = null;    // Station whose star the header star follows
        private ulong _star_handler = 0;
        private bool _setting_star = false;
        private const int EXPLORE_TAGS = 5;
        private const uint SEARCH_DELAY_MS = 333;    // As the GTK3 search controller
        private uint _search_timer = 0;             // The pending search after the last key
        private bool _tags_chosen = false;     // The Explore tags are drawn once per run
        private Gtk.Stack _tag_stack;          // The Explore tags: each new set cross-fades over the last
        private bool _loading_tags = false;
        private bool _showing_starred = false;
        private bool _clearing_search = false;
        private Gtk.DropDown _countries;
        private string _latest_query = "";
        private string[] _country_codes = {};          // Country codes in drop-down order, after "Country…"

        private View _view = View.STATIONS;
        private int _generation = 0;               // Newest list request; older answers are dropped
        private bool _trending_shown = false;
        private bool _setting_volume = false;
        private bool _resetting_pickers = false;
        private Tuner.StationSet? _set = null;         // The set on show
        private string _set_title = "";
        private Tuner.Models.Station? _track_station = null;   // The station and title last announced
        private string _track_title = "";


        private uint _heading_token = 0;           // Counts heading changes, so a late fade-out does not undo a newer heading
        private const string HEADING_COLON_GAP = "        ";   // A heading's colon is followed by this: a title, then its count a tab over
        private const int PREF_ROW_PAD_PX = 2;         // Space above and below each preference
        private const int PREF_DIVIDER_PAD_PX = 3;     // and above and below each divider
        private const int PANE_MIN_PX = 170;            // The sidebar can be dragged between these widths
        private const int PANE_MAX_PX = 420;
        private const int PANE_DEFAULT_PX = 230;
        private const uint STARTUP_FADE_MS = 600;     // How long the window takes to fade in at startup

        public MainWindow (App app)
        {
            Object (application: app);
            _app = app;
            title = "Tuner (GTK4 prototype)";
            var settings = app.core.settings;
            default_width = settings.window_width > 0 ? settings.window_width : 1000;
            default_height = settings.window_height > 0 ? settings.window_height : 700;

            _image_popup = new MetadataImagePopup (this);
            settings.bind_property ("stream-info-image-popup", _image_popup, "enabled", GLib.BindingFlags.SYNC_CREATE);
            settings.bind_property ("stream-info-image-popup-stay-back", _image_popup, "stay-back", GLib.BindingFlags.SYNC_CREATE);

            build ();
            connect_core ();
            add_shortcuts ();

            // The window fades in when it first appears, rather than popping up
            opacity = Fade.WINDOW_START_OPACITY;
            ulong shown = 0;
            shown = map.connect (() =>
            {
                disconnect (shown);
                Fade.to (this, 1.0, STARTUP_FADE_MS);
            });

            close_request.connect (() =>
            {
                _app.core.quit_cleanly ("window closed");
                return true;
            });
        } // MainWindow


        // ----------------------------------------------------------
        // Layout
        // ----------------------------------------------------------

        private void build ()
        {
            build_header ();

            // The sidebar width can be dragged, within limits, as in the GTK3 app
            var body = new Gtk.Paned (Gtk.Orientation.HORIZONTAL);
            body.start_child = build_sidebar ();
            body.end_child = build_content ();
            body.resize_start_child = false;
            body.shrink_start_child = false;
            body.resize_end_child = true;
            body.shrink_end_child = false;
            body.position = PANE_DEFAULT_PX;
            body.notify["position"].connect (() =>
            {
                if (body.position > PANE_MAX_PX)
                    body.position = PANE_MAX_PX;
            });
            child = body;
        } // build


        // ----------------------------------------------------------
        // Header bar: volume, star, play, heart | now playing | history, search, menu
        // ----------------------------------------------------------

        private void build_header ()
        {
            var header = new Gtk.HeaderBar ();

            // The volume slider is vertical, as the GTK3 volume button's popup is
            _volume = new Gtk.Scale.with_range (Gtk.Orientation.VERTICAL, 0.0, 1.0, 0.01);
            _volume.draw_value = false;
            _volume.inverted = true;
            _volume.set_size_request (-1, 160);
            _volume.value_changed.connect (() =>
            {
                if (!_setting_volume)
                    _app.core.player.volume = _volume.get_value ();
            });
            var volume_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            volume_box.margin_start = volume_box.margin_end = volume_box.margin_top = volume_box.margin_bottom = 6;
            volume_box.append (_volume);
            var volume_popover = new Gtk.Popover ();
            volume_popover.child = volume_box;
            var volume_button = new Gtk.MenuButton ();
            volume_button.icon_name = "audio-volume-high-symbolic";
            volume_button.popover = volume_popover;
            new FadingPopover (volume_popover);
            volume_button.valign = Gtk.Align.CENTER;
            volume_button.tooltip_text = _("Volume (Ctrl+Up, Ctrl+Down)");
            _tuner_status = new TunerStatus ();
            _tuner_status.has_tooltip = true;
            _tuner_status.query_tooltip.connect ((x, y, keyboard, tooltip) =>
            {
                if (_app.core.is_offline)
                    return false;
                // TRANSLATORS: Tooltip of the directory icon. %s is the directory name, the first %d how many stations it has, the second %d how many tags. Keep the line breaks and tab
                tooltip.set_text (_("Data Provider: %s\n\n%d Stations,\t%d Tags").printf (
                    _app.core.directory.provider (), _app.core.provider.available_stations (),
                    _app.core.provider.available_tags ()));
                return true;
            });
            header.pack_start (_tuner_status);
            _volume_button = volume_button;
            header.pack_start (volume_button);

            _star_head = new Gtk.ToggleButton ();
            _star_head.icon_name = "non-starred-symbolic";
            _star_head.valign = Gtk.Align.CENTER;
            _star_head.add_css_class ("raised");
            _star_head.sensitive = false;
            _star_head.tooltip_text = _("Star this station");
            _star_head.toggled.connect (() =>
            {
                if (!_setting_star && _star_station != null)
                    _star_station.starred = _star_head.active;
            });
            header.pack_start (_star_head);

            _play_image = new Gtk.Image.from_icon_name ("media-playback-start-symbolic");
            _play = new Gtk.Button ();
            _play.child = _play_image;
            _play.valign = Gtk.Align.CENTER;
            _play.add_css_class ("raised");
            _play.sensitive = true;
            _play.clicked.connect (() => { _app.core.player.play_pause (); });
            header.pack_start (_play);

            _heart = new Gtk.Button.from_icon_name ("emblem-favorite-symbolic");
            _heart.valign = Gtk.Align.CENTER;
            _heart.add_css_class ("raised");
            _heart.sensitive = false;
            _heart.tooltip_text = _("Heart current track in history");
            _heart.clicked.connect (toggle_heart);
            header.pack_start (_heart);

            // Centre: the station and track playing
            _now = new NowPlaying ();
            _app.core.settings.bind_property ("stream-info-dynamic-shrink", _now.track, "dynamic-shrink", GLib.BindingFlags.SYNC_CREATE);
            _app.core.settings.bind_property ("stream-info", _now.track, "show-metadata", GLib.BindingFlags.SYNC_CREATE);
            _app.core.settings.bind_property ("stream-info-fast", _now.track, "metadata-fast-cycle", GLib.BindingFlags.SYNC_CREATE);
            var now = _now;

            // Rest the pointer on it for a second and the station and the stream's metadata show, as in the GTK3 app
            var now_hover = new Gtk.EventControllerMotion ();
            now_hover.enter.connect ((x, y) =>
            {
                if (_meta_hover_id != 0 || (_meta_popover != null && _meta_popover.visible))
                    return;
                _meta_hover_id = Timeout.add (1000, () =>
                {
                    _meta_hover_id = 0;
                    show_metadata_popover ();
                    return Source.REMOVE;
                });
            });
            now_hover.leave.connect (() =>
            {
                if (_meta_hover_id != 0)
                {
                    Source.remove (_meta_hover_id);
                    _meta_hover_id = 0;
                }
            });
            now.add_controller (now_hover);
            header.title_widget = now;

            // Right: menu, history, search (rightmost first)
            var menu_popover = new Gtk.Popover ();
            menu_popover.child = build_preferences (menu_popover);
            _menu_button = new Gtk.MenuButton ();
            _menu_button.icon_name = "open-menu-symbolic";
            _menu_button.popover = menu_popover;
            new FadingPopover (menu_popover);
            _menu_button.valign = Gtk.Align.CENTER;
            _menu_button.add_css_class ("raised");
            _menu_button.tooltip_text = _("Preferences");
            header.pack_end (_menu_button);

            var history_button = new HistoryButton (_app.core);
            history_button.station_selected.connect ((station) => { play_clicked (station); });
            history_button.station_uuid_selected.connect ((uuid) => { _app.core.play_station_by_uuid_async.begin (uuid); });
            header.pack_end (history_button);

            _search_toggle = new Gtk.ToggleButton ();
            _search_toggle.icon_name = "system-search-symbolic";
            _search_toggle.valign = Gtk.Align.CENTER;
            _search_toggle.add_css_class ("raised");
            _search_toggle.tooltip_text = _("Search for Stations (Ctrl+F)");
            header.pack_end (_search_toggle);

            set_titlebar (header);
        } // build_header


        // ----------------------------------------------------------
        // Sidebar: Selections, Library, Explore, Genres, Subgenres, Eras, Talk
        // ----------------------------------------------------------

        private static Gtk.Box side_content (string label, string? icon)
        {
            var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            if (icon != null)
                box.append (new Gtk.Image.from_icon_name (icon));
            var text = new Gtk.Label (label);
            text.xalign = 0;
            text.hexpand = true;
            text.ellipsize = Pango.EllipsizeMode.END;
            box.append (text);
            return box;
        } // side_content


        private Gtk.Button side_item (string label, string? icon = null)
        {
            var button = new Gtk.Button ();
            button.child = side_content (label, icon);
            button.add_css_class ("flat");
            button.add_css_class ("sidebar-item");
            button.clicked.connect (() => { mark_selected (button); });
            return button;
        } // side_item


        /** Highlights the sidebar entry last chosen, as the GTK3 source list does. */
        private void mark_selected (Gtk.Widget item)
        {
            if (_selected_item != null)
                _selected_item.remove_css_class ("selected");
            _selected_item = item;
            item.add_css_class ("selected");
        } // mark_selected


        /**
         * A sidebar section. A plain heading is always open; one with a bit number has the arrow on the right and
         * remembers whether it is open between runs.
         */
        private delegate void SectionOpened ();

        private Gtk.Widget side_section (string title, Gtk.Widget body, int bit = -1, bool open = true,
                                         owned SectionOpened? on_open = null)
        {
            var heading = new Gtk.Label (title);
            heading.xalign = 0;
            heading.hexpand = true;
            heading.add_css_class ("sidebar-heading");

            var section = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            body.margin_start = 10;

            if (bit < 0)
            {
                heading.margin_start = 8;
                heading.margin_top = 6;
                heading.margin_bottom = 2;
                section.append (heading);
                section.append (body);
                return section;
            }

            var settings = _app.core.settings;
            bool expanded = settings.is_category_expanded (bit);

            var arrow = new Gtk.Image.from_icon_name (expanded ? "pan-down-symbolic" : "pan-end-symbolic");
            var head_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
            head_box.append (heading);
            head_box.append (arrow);
            var head = new Gtk.Button ();
            head.child = head_box;
            head.add_css_class ("flat");
            head.add_css_class ("sidebar-item");

            var revealer = new Gtk.Revealer ();
            revealer.child = body;
            revealer.reveal_child = expanded;

            head.clicked.connect (() =>
            {
                revealer.reveal_child = !revealer.reveal_child;
                arrow.icon_name = revealer.reveal_child ? "pan-down-symbolic" : "pan-end-symbolic";
                settings.set_category_expanded (bit, revealer.reveal_child);
                if (revealer.reveal_child && on_open != null)
                    on_open ();
            });

            section.append (head);
            section.append (revealer);
            return section;
        } // side_section


        private Gtk.Widget genre_section (string title, string[] genres, int bit)
        {
            var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            foreach (var genre in genres)
            {
                var name = genre;
                var item = side_item (name, "tuner:playlist-symbolic");
                item.clicked.connect (() => { reset_pickers (); show_tag (name); });
                box.append (item);
            }
            return side_section (title, box, bit, false);
        } // genre_section


        private Gtk.Widget build_sidebar ()
        {
            var column = new Gtk.Box (Gtk.Orientation.VERTICAL, 2);
            column.margin_top = 6;
            column.margin_bottom = 6;

            // Selections
            var selections = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            // TRANSLATORS: Side menu entry: a random selection of stations to discover
            var discover = side_item (_("Discover"), "face-smile");
            _discover = discover;
            discover.tooltip_text = _("Stations to discover");
            discover.clicked.connect (() => { show_random (); });
            // TRANSLATORS: Side menu entry: stations that are trending in the directory
            var trending = side_item (_("Trending"), "tuner:playlist-queue");
            trending.clicked.connect (() => { show_trending (); });
            // TRANSLATORS: Side menu entry: the most listened to stations
            var popular = side_item (_("Popular"), "tuner:playlist-similar");
            popular.clicked.connect (() => { show_popular (); });
            // Jukebox starts on a double click, as in the GTK3 app (a single click only selects it)
            // TRANSLATORS: Side menu entry: plays random stations one after another
            _jukebox = side_item (_("Jukebox"), "tuner:jukebox");
            _jukebox.tooltip_text = _("Double click to play random stations, one after another");
            var jukebox_click = new Gtk.GestureClick ();
            jukebox_click.propagation_phase = Gtk.PropagationPhase.CAPTURE;
            jukebox_click.pressed.connect ((n_press, x, y) =>
            {
                if (n_press == 2)
                    _app.core.jukebox.enable ();
            });
            _jukebox.add_controller (jukebox_click);
            selections.append (discover);
            selections.append (trending);
            selections.append (popular);
            selections.append (_jukebox);
            // TRANSLATORS: Side menu section heading
            column.append (side_section (_("Selections"), selections));

            // Library
            var library = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            // TRANSLATORS: Side menu entry: the stations the user has starred
            var starred = side_item (_("Starred by You"), "starred");
            _starred_count = new Gtk.Label ("");
            _starred_count.add_css_class ("dim-label");
            ((Gtk.Box) starred.child).append (_starred_count);
            starred.tooltip_text = _("Your starred stations; then type in the search box to filter them");
            starred.clicked.connect (() =>
            {
                _clearing_search = true;
                _search.text = "";
                _clearing_search = false;
                show_starred ();
            });
            var latest = side_item (_("Latest Search"), "system-search");
            latest.clicked.connect (show_latest_search);
            var saved = side_item (_("Saved Searches"), "folder-music");
            saved.clicked.connect (() => { show_saved_searches (); });
            library.append (starred);
            library.append (latest);
            library.append (saved);
            // TRANSLATORS: Side menu section heading
            column.append (side_section (_("Library"), library));

            // Explore: some tags drawn at random from the directory
            var explore = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            _tag_stack = new Gtk.Stack ();
            _tag_stack.transition_type = Gtk.StackTransitionType.CROSSFADE;
            _tag_stack.transition_duration = 250;
            _tag_stack.vhomogeneous = false;        // Take the height of the set on show
            _tag_stack.hhomogeneous = true;
            // Once a set has faded in, the one it replaced can go
            _tag_stack.notify["transition-running"].connect (() =>
            {
                if (_tag_stack.transition_running)
                    return;
                Gtk.Widget? page = _tag_stack.get_first_child ();
                while (page != null)
                {
                    var next = page.get_next_sibling ();
                    if (page != _tag_stack.visible_child)
                        _tag_stack.remove (page);
                    page = next;
                }
            });
            explore.append (_tag_stack);
            // TRANSLATORS: Side menu section heading: browsing stations by genre, era and so on
            column.append (side_section (_("Explore"), explore, 1, true, () => { load_tag_chips.begin (); }));

            // TRANSLATORS: Side menu section heading: music genres
            column.append (genre_section (_("Genres"), Tuner.Models.Genre.GENRES, 2));
            // TRANSLATORS: Side menu section heading: narrower music genres
            column.append (genre_section (_("Subgenres"), Tuner.Models.Genre.SUBGENRES, 3));
            // TRANSLATORS: Side menu section heading: stations by decade
            column.append (genre_section (_("Eras"), Tuner.Models.Genre.eras (), 4));
            column.append (genre_section (_("Talk, News, Sport"), Tuner.Models.Genre.TALK, 5));

            // Country: the drop-down itself is the heading, styled like the section headings
            var country = build_country_picker ();
            country.margin_bottom = 4;
            column.append (country);

            var scroller = new Gtk.ScrolledWindow ();
            scroller.hscrollbar_policy = Gtk.PolicyType.NEVER;
            scroller.min_content_width = PANE_MIN_PX;
            scroller.propagate_natural_width = false;
            scroller.hexpand = false;
            scroller.child = column;
            scroller.add_css_class ("sidebar-pane");
            return scroller;
        } // build_sidebar


        // ----------------------------------------------------------
        // Content: search bar, title, the stations in two columns
        // ----------------------------------------------------------

        /** A button beside the title, as tall as the title's text. */
        private static Gtk.Button title_button (string icon_name)
        {
            var icon = new Gtk.Image.from_icon_name (icon_name);
            icon.pixel_size = 24;
            var button = new Gtk.Button ();
            button.child = icon;
            button.valign = Gtk.Align.CENTER;
            return button;
        } // title_button


        private Gtk.Widget build_content ()
        {
            _search = new Gtk.SearchEntry ();
            _search.placeholder_text = _("Search stations");
            _search.hexpand = true;
            _search.activate.connect (() => { search (_search.text); });

            // Every change of the text (typing, backspace, cut, paste) restarts a short wait, and the search runs when
            // it ends, as the GTK3 app does with its entry's `changed`. (SearchEntry's own search-changed is not used:
            // it did not reliably follow a backspace.)
            _search.changed.connect (() =>
            {
                _save_search.sensitive = _search.text.strip () != "";
                if (_clearing_search)
                    return;
                if (_search_timer != 0)
                    Source.remove (_search_timer);
                _search_timer = Timeout.add (SEARCH_DELAY_MS, () =>
                {
                    _search_timer = 0;
                    var text = _search.text.strip ();
                    if (_showing_starred)
                        show_starred (_search.text);        // Typing filters the starred list while it is on show
                    else if (text != "" && text != _latest_query)
                        search (text);                      // Results follow the typing, as in the GTK3 app
                    return Source.REMOVE;
                });
            });

            // As in the GTK3 app: a panel that slides down under the header, the entry centred in it
            _search.placeholder_text = _("Station Search");
            _search.add_css_class ("big-search");
            _search.hexpand = false;
            _search.halign = Gtk.Align.CENTER;
            _search.width_request = 420;
            _search.margin_top = 3;
            _search.margin_bottom = 3;
            var search_panel = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            search_panel.hexpand = true;
            search_panel.halign = Gtk.Align.FILL;
            search_panel.add_css_class ("search-revealer-bg");
            var centre = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            centre.hexpand = true;
            centre.halign = Gtk.Align.CENTER;
            centre.append (_search);
            search_panel.append (centre);
            _search_revealer = new Gtk.Revealer ();
            _search_revealer.transition_type = Gtk.RevealerTransitionType.SLIDE_DOWN;
            _search_revealer.child = search_panel;
            _search_toggle.bind_property ("active", _search_revealer, "reveal-child", BindingFlags.SYNC_CREATE);
            _search_toggle.toggled.connect (() =>
            {
                if (_search_toggle.active)
                {
                    _search.text = "";
                    _search.grab_focus ();
                }
            });

            // The title of what is on show, with the save search action beside it
            _status = new Gtk.Label ("");
            _status.xalign = 0;
            _status.hexpand = false;
            _status.ellipsize = Pango.EllipsizeMode.END;
            _status.add_css_class ("stack-label");
            _status.notify["label"].connect (() =>
            {
                // A heading set while faded out fades in, after a beat. Later changes during the fade just change the text.
                if (_status.opacity == 0.0)
                {
                    Fade.to (_status, 1.0, HEADING_FADE_IN_MS, null, HEADING_DELAY_MS);
                    if (_shuffle.visible)
                        Fade.to (_shuffle, 1.0, HEADING_FADE_IN_MS, null, HEADING_DELAY_MS);
                }

                // A colon in a heading is followed by two spaces
                var text = _status.label;
                if (text != null && text.contains (":"))
                {
                    try
                    {
                        var spaced = new Regex (":\\s*(?=\\S)").replace_literal (text, -1, 0, ":" + HEADING_COLON_GAP);
                        if (spaced != text)
                            _status.label = spaced;
                    }
                    catch (RegexError e)
                    {
                        warning ("Heading spacing: %s", e.message);
                    }
                }
            });

            _save_search = title_button ("non-starred-symbolic");
            _save_search.tooltip_text = _("Save this search");
            _save_search.valign = Gtk.Align.CENTER;
            _save_search.visible = false;
            _save_search.sensitive = false;
            _save_search.clicked.connect (() =>
            {
                var text = _search.text.strip ();
                if (text != "")
                    _app.core.directory.add_saved_search (text);
            });

            _shuffle = title_button ("media-playlist-shuffle-symbolic");
            _shuffle.tooltip_text = _("Discover more stations");
            _shuffle.valign = Gtk.Align.CENTER;
            _shuffle.visible = false;
            _shuffle.clicked.connect (() => { show_random (false); });

            var title = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 14);        // about two spaces of the title's size
            title.margin_start = 16;
            title.margin_end = 12;
            title.margin_top = 10;
            title.margin_bottom = 6;
            _loading = new Gtk.Label ("…");           // Shown after the heading while a set loads
            _loading.add_css_class ("stack-label");
            _loading.opacity = 0.0;
            var heading = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            heading.append (_status);
            heading.append (_loading);
            heading.append (_shuffle);          // beside the ellipsis, which is its own label, so the heading text never moves it
            title.append (heading);
            title.append (_save_search);
            var title_spacer = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            title_spacer.hexpand = true;
            title.append (title_spacer);

            _store = new GLib.ListStore (typeof (GLib.Object));
            build_factories ();
            _list = new Gtk.GridView (new Gtk.NoSelection (_store), _station_factory);
            _list.single_click_activate = false;          // a station plays on a double click, as in the GTK3 app
            _list.min_columns = 1;
            _list.max_columns = 20;
            _list.valign = Gtk.Align.FILL;
            _list.margin_start = 10;
            _list.margin_end = 10;
            _list.add_css_class ("station-list");
            _list.activate.connect (on_list_activated);

            var scroller = new Gtk.ScrolledWindow ();
            scroller.vexpand = true;
            scroller.hscrollbar_policy = Gtk.PolicyType.NEVER;
            scroller.child = _list;

            var list_box = scroller;

            // The faint tuner behind the stations, as in the GTK3 app
            _backdrop = new Backdrop ();
            var overlay = new Gtk.Overlay ();
            overlay.vexpand = true;
            overlay.child = _backdrop;
            overlay.add_overlay (list_box);

            // The listening time
            _tape = new Gtk.Label ("");
            _tape.tooltip_text = _("Listening time: this station, and in total");
            _tape.add_css_class ("dim-label");
            var footer = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
            footer.margin_start = 12;
            footer.margin_end = 12;
            footer.margin_top = 4;
            footer.margin_bottom = 6;
            var spacer = new Gtk.Label ("");
            spacer.hexpand = true;
            footer.append (spacer);
            footer.append (_tape);

            var content = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            content.hexpand = true;
            content.append (_search_revealer);
            content.append (title);
            content.append (new Gtk.Separator (Gtk.Orientation.HORIZONTAL));
            content.append (overlay);
            content.append (footer);
            return content;
        } // build_content


        // ----------------------------------------------------------
        // Core -> window
        // ----------------------------------------------------------

        private void connect_core ()
        {
            var events = _app.core.events;

            events.connection_state_changed_sig.connect (on_connection_state);
            events.station_changed_sig.connect ((station) =>
            {
                _track_station = station;
                _track_title = "";
                _track_metadata = "";
                if (_meta_popover != null)
                    _meta_popover.popdown ();
                follow_star (station);
                show_heart ();
                _tuner_status.tune_to (station);
                _backdrop.tune_to (station);
                _now.change_station (station);
            });
            events.playback_metadata_changed_sig.connect ((station, metadata) =>
            {
                // The core has already put the track in the history
                _track_station = station;
                _track_metadata = metadata.pretty_print != null ? metadata.pretty_print : "";
                _image_popup.handle_metadata (metadata);
                _track_title = metadata.title != null ? metadata.title : "";
                _now.handle_metadata (metadata);
                show_heart ();
            });
            events.player_state_changed_sig.connect ((station, state) =>
            {
                show_play_state (state);
                update_controls_state ();
            });
            events.volume_changed_sig.connect (set_volume_scale);
            events.playback_time_tick_sig.connect ((station, total, here) => { show_tape (here, total); });

            // The history changes by itself as stations play; keep it up to date while it is on show
            var history = _app.core.history;
            history.entry_added_sig.connect ((entry) => { history_changed (); });
            history.entry_removed_sig.connect ((entry) => { history_changed (); });
            history.entry_changed_sig.connect ((entry) => { history_changed (); });
            history.cleared_sig.connect (() => { history_changed (); });

            // The jukebox turns itself off when a station is picked by hand
            _app.core.jukebox.shuffle_state_changed_sig.connect ((enabled) =>
            {
                if (Tuner.debug_enabled ())
                    debug ("jukebox shuffle state -> %s", enabled.to_string ());
                if (enabled)
                    mark_selected (_jukebox);
                _backdrop.show_jukebox (enabled);
            });

            set_volume_scale (_app.core.settings.volume);
            on_connection_state (_app.core.connection.state);

            // The count follows stars added or removed anywhere (the header star, a row's menu, an import)
            _app.core.events.starred_stations_changed_sig.connect ((station) => { refresh_star_count (); });
            _app.core.stars.loaded_sig.connect (() => { refresh_star_count (); });
        } // connect_core


        private void set_volume_scale (double volume)
        {
            _setting_volume = true;
            _volume.set_value (volume);
            _setting_volume = false;

            // The button shows the level: muted at zero
            _volume_button.icon_name = volume <= 0.0 ? "audio-volume-muted-symbolic"
                                     : volume < 0.34 ? "audio-volume-low-symbolic"
                                     : volume < 0.67 ? "audio-volume-medium-symbolic"
                                     :                 "audio-volume-high-symbolic";
        } // set_volume_scale


        /** Changes the heading with a fade: the old text fades out, then the new text fades in (the label's own handler does that). */
        private void change_heading (string text)
        {
            if (_status.label == text)
                return;

            if (_status.label == "")
            {
                Fade.cancel (_status);
                _status.opacity = 0.0;
                _status.label = text;
                return;
            }

            uint token = ++_heading_token;
            Fade.to (_status, 0.0, FADE_OUT_MS, () =>
            {
                if (token == _heading_token)       // not if a set has put its own heading up meanwhile
                    _status.label = text;
            });
        } // change_heading


        private void on_connection_state (Tuner.Events.ConnectionState state)
        {
            update_controls_state ();
            switch (state)
            {
                case Tuner.Events.ConnectionState.OFFLINE:
                    // TRANSLATORS: Heading shown when the station directory cannot be reached
                    change_heading (C_("connection status", "Offline"));
                    break;
                case Tuner.Events.ConnectionState.CONNECTING:
                    change_heading (_("Connecting to the station directory…"));
                    break;
                default:
                    // Once the first set is on show it sets its own heading; later, back online, the message just goes
                    if (_trending_shown && (_status.label == C_("connection status", "Offline") || _status.label == _("Connecting to the station directory…")))
                        change_heading ("");
                    if (!_trending_shown)
                    {
                        _trending_shown = true;
                        refresh_star_count ();
                        // The core has loaded the starred stations by now. Open on Discover, unless the user prefers Starred
                        if (_app.core.settings.start_on_starred)
                            show_starred ();
                        else
                        {
                            mark_selected (_discover);
                            show_random ();
                        }
                        load_tag_chips.begin ();
                    }
                    break;
            }
        } // on_connection_state


        // ----------------------------------------------------------
        // Preferences: the GTK3 menu, in the popover of the menu button
        // ----------------------------------------------------------

        private const string[] THEME_IDS = { "system", "light", "dark" };

        /** A setting as a row: the text, and the tick box at the right as in the GTK3 menu. */
        private Gtk.Widget pref_check (string text, string tip, string property, int indent = 8)
        {
            var label = new Gtk.Label (text);
            label.xalign = 0;
            label.hexpand = true;
            var check = new Gtk.CheckButton ();
            _app.core.settings.bind_property (property, check, "active",
                                              BindingFlags.BIDIRECTIONAL | BindingFlags.SYNC_CREATE);

            var row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12);
            row.margin_start = indent;
            row.margin_end = 8;
            row.margin_top = PREF_ROW_PAD_PX;
            row.margin_bottom = PREF_ROW_PAD_PX;
            row.tooltip_text = tip;
            row.append (label);
            row.append (check);
            var click = new Gtk.GestureClick ();
            click.released.connect ((n, x, y) => { check.active = !check.active; });
            row.add_controller (click);
            row.set_data<Gtk.CheckButton> ("check", check);
            return row;
        } // pref_check


        private static Gtk.Widget pref_divider ()
        {
            var divider = new Gtk.Separator (Gtk.Orientation.HORIZONTAL);
            divider.add_css_class ("pref-divider");
            divider.margin_top = PREF_DIVIDER_PAD_PX;
            divider.margin_bottom = PREF_DIVIDER_PAD_PX;
            divider.margin_start = 8;
            divider.margin_end = 8;
            return divider;
        } // pref_divider


        private Gtk.Button pref_button (string text, owned PrefAction action, Gtk.Popover popover)
        {
            var label = new Gtk.Label (text);
            label.xalign = 0;
            var button = new Gtk.Button ();
            button.child = label;
            button.add_css_class ("flat");
            button.add_css_class ("pref-button");
            button.margin_start = 8;
            button.clicked.connect (() =>
            {
                Fade.close_popover (popover);
                action ();
            });
            return button;
        } // pref_button


        private delegate void PrefAction ();


        private Gtk.Widget build_preferences (Gtk.Popover popover)
        {
            var settings = _app.core.settings;
            var menu = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            menu.margin_top = 10;
            menu.margin_bottom = 10;
            menu.margin_start = 5;
            menu.margin_end = 5;

            // Theme
            var names = new Gtk.StringList (null);
            // TRANSLATORS: Theme choice: follow the system light or dark setting
            names.append (C_("theme choice", "System"));
            names.append (_("Light mode"));
            names.append (_("Dark mode"));
            var themes = new Gtk.DropDown (names, null);
            for (uint i = 0; i < THEME_IDS.length; i++)
            {
                if (THEME_IDS[i] == settings.theme_mode)
                    themes.selected = i;
            }
            themes.notify["selected"].connect (() =>
            {
                if (themes.selected < THEME_IDS.length)
                    settings.theme_mode = THEME_IDS[themes.selected];
            });
            var theme_label = new Gtk.Label (_("Theme"));
            theme_label.xalign = 0;
            themes.hexpand = true;
            var theme_row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12);
            theme_row.margin_start = 8;
            theme_row.margin_end = 8;
            theme_row.append (theme_label);
            theme_row.append (themes);
            menu.append (theme_row);
#if LANGUAGE_SELECTOR
            // Development builds only: the language, "Default" being the system's. Changing it restarts Tuner.
            var language_codes = new string[] { "" };
            var language_names = new Gtk.StringList (null);
            language_names.append ("Default");                  // Dev builds only: not translated
            var language_map = Tuner.Models.Languages.get_language_map ();
            // In the order of the names, in the language now in use
            var sorted_codes = new Gee.ArrayList<string> ();
            sorted_codes.add_all (language_map.keys);
            sorted_codes.sort ((a, b) => { return language_map[a].collate (language_map[b]); });
            foreach (var code in sorted_codes)
            {
                language_codes += code;
                language_names.append (language_map[code]);
            }
            var languages = new Gtk.DropDown (language_names, null);
            for (int i = 0; i < language_codes.length; i++)
            {
                if (language_codes[i] == settings.language)
                    languages.selected = i;
            }
            languages.notify["selected"].connect (() =>
            {
                if (languages.selected < language_codes.length)
                    _app.set_language (language_codes[languages.selected]);
            });
            var language_label = new Gtk.Label (_("Language"));
            language_label.xalign = 0;
            languages.hexpand = true;
            var language_row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12);
            language_row.margin_start = 8;
            language_row.margin_end = 8;
            language_row.margin_top = PREF_ROW_PAD_PX;
            language_row.tooltip_text = _("Language changes restart Tuner");
            language_row.append (language_label);
            language_row.append (languages);
            menu.append (language_row);
#endif
            menu.append (pref_divider ());

            // Startup
            menu.append (pref_check (_("Open to Starred Stations"),
                _("If enabled, when Tuner starts it will open to the starred stations view"), "start-on-starred"));
            menu.append (pref_check (_("Auto-play last station on startup"),
                _("If enabled, when Tuner starts it will automatically start to play the last played station"), "auto-play"));
            menu.append (pref_check (_("Save all Hearted tracks for All Time"),
                _("If enabled, hearted tracks are also kept in the All Time list in History, which survives restarts and clearing the history"),
                "save-all-time-hearted"));
            menu.append (pref_divider ());

            // Playback
            menu.append (pref_check (_("Restart playing after a network outage"),
                _("If enabled, Tuner will restart playing the current station if it was stopped by a network outage"), "play-restart"));
            menu.append (pref_check (_("Keep playing when the window is closed"),
                _("If disabled, closing the window quits Tuner and stops playback instead of continuing to play in the background"),
                "play-in-background"));
            menu.append (pref_check (_("Keep the computer awake while playing"),
                _("If enabled, Tuner stops the computer suspending while a station plays, so it keeps playing with the screen locked. If disabled, the computer may suspend when idle and playback will stop"),
                "inhibit-sleep"));
            menu.append (pref_divider ());

            // Stream info: the options that refine it are indented beneath it
            menu.append (pref_check (_("Show stream info when playing"),
                _("Cycle through the metadata from the playing stream"), "stream-info"));
            var fast = pref_check (_("Faster cycling through stream info"),
                _("Fast cycle through the metadata from the playing stream if show stream info is enabled"), "stream-info-fast", 24);
            settings.bind_property ("stream-info", fast, "sensitive", BindingFlags.SYNC_CREATE);
            menu.append (fast);
            menu.append (pref_check (_("Stream metadata image popup"),
                _("Show a movable popup with images discovered in the stream metadata"), "stream-info-image-popup", 24));
            var stay_back = pref_check (_("Keep the image popup behind when it is sent back"),
                _("If you send the popup behind other windows (double click it), it stays there when its image changes or comes back after a station change, instead of coming to the front"), "stream-info-image-popup-stay-back", 48);
            settings.bind_property ("stream-info-image-popup", stay_back, "sensitive", BindingFlags.SYNC_CREATE);
            menu.append (stay_back);
            menu.append (pref_check (_("Shrink title dynamically with the text"),
                _("Shrink the title according to the length of the displayed text."), "stream-info-dynamic-shrink", 24));
            menu.append (pref_divider ());

            // Your data
            menu.append (pref_check (_("Do not participate in Station voting"),
                _("If checked, your starred and streamed stations will not be used to calculate the Station index popularity vote, nor the popular and trending stations"),
                "do-not-vote"));
            menu.append (pref_check (_("Play startup jingle"),
                _("If enabled, Tuner plays a short sound when it starts"), "startup-jingle"));
            menu.append (pref_divider ());
            menu.append (pref_button (_("Export Starred Stations to Playlist"), () => { export_starred (); }, popover));
            menu.append (pref_button (_("Import Station UUIDs as Starred Stations"), () => { import_starred (); }, popover));
            menu.append (pref_divider ());
            menu.append (pref_button (_("About"), () => { show_about (); }, popover));

            var scroller = new Gtk.ScrolledWindow ();
            scroller.hscrollbar_policy = Gtk.PolicyType.NEVER;
            scroller.propagate_natural_height = true;
            scroller.max_content_height = 640;
            scroller.child = menu;
            return scroller;
        } // build_preferences


        private void export_starred ()
        {
            var dialog = new Gtk.FileDialog ();
            dialog.title = _("Save File");
            dialog.initial_name = "tuner-starred.%s.m3u8".printf (new DateTime.now_local ().format ("%Y-%m-%d"));
            dialog.save.begin (this, null, (obj, res) =>
            {
                try
                {
                    var file = dialog.save.end (res);
                    FileUtils.set_contents (file.get_path (), _app.core.stars.export_m3u8 ());
                }
                catch (Error e)
                {
                    if (!(e is Gtk.DialogError.DISMISSED))
                        warning ("Error: %s", e.message);
                }
            });
        } // export_starred


        private void import_starred ()
        {
            var dialog = new Gtk.FileDialog ();
            dialog.title = _("Choose a file");
            dialog.open.begin (this, null, (obj, res) =>
            {
                try
                {
                    var file = dialog.open.end (res);
                    var stream = file.read ();
                    _app.core.stars.import_stationuuids (new DataInputStream (stream));
                    stream.close ();
                    if (_showing_starred)
                        show_starred (_search.text);
                    refresh_star_count ();
                }
                catch (Error e)
                {
                    if (!(e is Gtk.DialogError.DISMISSED))
                        warning ("Error reading file: %s", e.message);
                }
            });
        } // import_starred


        /** The About box: Gtk.AboutDialog, with the credits (authors, artists, translators) and the license text as in GTK3. */
        private void show_about ()
        {
            var about = new Gtk.AboutDialog ();
            about.transient_for = this;
            about.modal = true;
            about.destroy_with_parent = true;
            about.program_name = "Tuner";
            about.version = @"v$(APP_VERSION)";                // The presentation layer's version is the main one
            about.comments = _("Find & listen to Internet radio stations") + "\n\n"
                // TRANSLATORS: The two %s are version numbers
                + _("Tuner GTK4 v%s\nTuner core v%s").printf (APP_VERSION, BUILT_WITH_CORE_VERSION);
            about.logo_icon_name = "tuner:tuner-on";
            about.authors = { "Louis Brauer, technosf" };
            about.artists = { "https://faleksandar.com/", "Vinyl record graphic from SVGRepo https://www.svgrepo.com/" };
            about.translator_credits = """Arabic: Troy
Croatian: Milo Ivir
Dutch: Vistaus
English (UK): Andi Chandler, Masowick
Estonian: Priit Jõerüüt
French: NathanBnm, David D.
German: uwe-ss, J. Lavoie, Tobias S, Masowick
Hungarian: PokoPuli
Italian: DevAlien, albanobattistella, FinixFighter, J. Lavoie
Japanese: TANIGUCHI Takaki, ejlaner
Lao: BoneNI
Norwegian Bokmål: Allan Nordhøy, Jon Helgeland
Portuguese: ssantos
Russian: AHOHNMYC, Мистер Перевод
Spanish: Paxton, Gaston Martres, scmanjarrez, Francisco Serrador
Spanish (Latin America): Guillermo Rivero
Swedish: bittin
Turkish: safak45x, Oğuz Ersen""";
            about.copyright = _("Copyright © 2020-2024 Louis Brauer\nCopyright © 2024 technosf https://github.com/technosf");
            about.license = """* Copyright (c) 2020-2024 Louis Brauer <louis@brauer.family>,
        Copyright © 2024 technosf <https://github.com/technosf>

        Tuner is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

Tuner is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with Tuner.  If not, see <http://www.gnu.org/licenses/>.""";
            about.wrap_license = true;
            about.website = "https://github.com/tuner-labs/tuner";
            about.website_label = _("Tuner on Github");
            Fade.window_in (about);
            about.present ();
        } // show_about


        /** The play button shows the inverse of the player state, as in the GTK3 app. */
        private void show_play_state (Tuner.Models.StreamPlayer.State state)
        {
            _play.tooltip_text = null;
            switch (state)
            {
                case Tuner.Models.StreamPlayer.State.PLAYING:
                    _play_image.icon_name = "media-playback-stop-symbolic";
                    _play_image.opacity = 1.0;
                    break;
                case Tuner.Models.StreamPlayer.State.BUFFERING:
                    _play_image.icon_name = "media-playback-pause-symbolic";
                    _play_image.opacity = 0.5;
                    break;
                case Tuner.Models.StreamPlayer.State.STOPPED_ERROR:
                    _play_image.icon_name = "dialog-error-symbolic";
                    _play_image.opacity = 0.5;
                    var why = _app.core.player.play_error_message;
                    _play.tooltip_text = (why == null || why.strip () == "") ? _("An error occurred during playback.") : why;
                    break;
                default:
                    _play_image.icon_name = "media-playback-start-symbolic";
                    _play_image.opacity = 1.0;
                    break;
            }
        } // show_play_state


        /** Online: every control works. Offline: only what can still help (stopping what plays, history). */
        private void update_controls_state ()
        {
            var state = _app.core.player.player_state;
            bool is_playing_now = state == Tuner.Models.StreamPlayer.State.PLAYING
                || state == Tuner.Models.StreamPlayer.State.BUFFERING;
            bool online = _app.core.connection.state == Tuner.Events.ConnectionState.READY;

            _tuner_status.online = online;
            _now.online = online;
            _star_head.sensitive = online && _star_station != null;
            _play.sensitive = online || is_playing_now;
            _play.opacity = (online || is_playing_now) ? 1.0 : 0.5;
            _volume_button.sensitive = online;
            _search_toggle.sensitive = online;
        } // update_controls_state




        /**
         * A station was chosen by hand. As in the GTK3 app, further choices are ignored while the change settles, so
         * the stations are not started on top of one another.
         */
        private void play_clicked (Tuner.Models.Station station)
        {
            // The core decides: it ignores clicks while offline, on the station playing, and while a change settles
            if (_app.core.player.request_station (station))
            {
                // TRANSLATORS: Window title: the app name before the name of the playing station
                title = _("Tuner: ") + station.name;

                // A station picked by hand ends jukebox mode, as in the GTK3 app
                if (_app.core.jukebox.enabled)
                    _app.core.jukebox.disable ();
            }
        } // play_clicked


        /** Adds an item to the list; the first one fades the list in, gently, as the GTK3 app does. */
        private void list_add (GLib.Object item)
        {
            _store.append (item);
            if (!_list_revealing && _list.opacity < 1.0)
            {
                _list_revealing = true;
                Fade.to (_list, 1.0, FADE_IN_MS);
            }
        } // list_add


        private void history_changed ()
        {
            show_heart ();
        } // history_changed


        // ----------------------------------------------------------
        // Heart
        // ----------------------------------------------------------

        private void show_heart ()
        {
            bool has_track = _track_station != null && _track_title != "";
            _heart.sensitive = has_track;
            if (has_track && _app.core.history.is_last_entry_hearted_for (_track_station, _track_title))
                _heart.add_css_class ("heart-favorited");
            else
                _heart.remove_css_class ("heart-favorited");
        } // show_heart


        private void toggle_heart ()
        {
            if (_track_station == null || _track_title == "")
                return;

            var history = _app.core.history;
            bool next = !history.is_last_entry_hearted_for (_track_station, _track_title);
            history.set_last_entry_hearted_if_matches (_track_station, _track_title, next);
            show_heart ();
        } // toggle_heart


        // ----------------------------------------------------------
        // Window -> core
        // ----------------------------------------------------------

        // ----------------------------------------------------------
        // Discover: genre, country, random
        // ----------------------------------------------------------

        /** Swaps the down arrow the drop-down draws for the right arrow the collapsed headings use. */
        private void use_right_arrow (Gtk.Widget widget)
        {
            var image = widget as Gtk.Image;
            if (image != null && image.icon_name == "pan-down-symbolic")
                image.icon_name = "pan-end-symbolic";

            for (var child = widget.get_first_child (); child != null; child = child.get_next_sibling ())
                use_right_arrow (child);
        } // use_right_arrow


        private Gtk.Widget build_country_picker ()
        {
            // Sorted by the name shown, with the codes kept alongside
            var named = new Gee.ArrayList<string> ();
            foreach (var code in Tuner.Models.Countries.map.keys)
                named.add ("%s\t%s".printf (Tuner.Models.Countries.get_by_code (code), code));
            named.sort ((a, b) => { return strcmp (a.down (), b.down ()); });

            var names = new Gtk.StringList (null);
            // TRANSLATORS: First entry of the country drop-down: no country chosen
            names.append (C_("country drop-down", "Country"));
            var codes = new string[0];
            foreach (var item in named)
            {
                var parts = item.split ("\t");
                names.append (parts[0]);
                codes += parts[1];
            }
            _country_codes = codes;

            _countries = new Gtk.DropDown (names, null);
            _countries.enable_search = true;
            _countries.add_css_class ("country-heading");
            // The closed drop-down shows a right arrow, like the collapsed genre headings
            _countries.realize.connect (() => { use_right_arrow (_countries); });
            _countries.expression = new Gtk.PropertyExpression (typeof (Gtk.StringObject), null, "string");
            _countries.notify["selected"].connect (() =>
            {
                if (_resetting_pickers || _countries.selected == 0 || (int) _countries.selected > _country_codes.length)
                    return;
                var code = _country_codes[_countries.selected - 1];
                var name = Tuner.Models.Countries.get_by_code (code);
                reset_pickers ();
                show_set.begin (_app.core.directory.load_by_country (PAGE_SIZE, code), name);
            });
            return _countries;
        } // build_country_picker


        /** Puts both pickers back on their prompt, so choosing the same entry again works. */
        private void reset_pickers ()
        {
            _resetting_pickers = true;
            _countries.selected = 0;
            _resetting_pickers = false;
        } // reset_pickers


        /** Whether the main window already shows (or is loading) the set with this name, so choosing it again should not reload it. */
        private bool already_showing (string title)
        {
            // An empty list (nothing found, or the directory did not answer) is asked for again
            return _view == View.STATIONS && _set != null && _set_title == title && _store.n_items > 0;
        } // already_showing


        public void show_tag (string tag)
        {
            if (already_showing (tag))
                return;
            show_set.begin (_app.core.directory.load_by_tag (tag), tag);
        } // show_tag

        public void show_random (bool fade_heading = true)
        {
            show_set.begin (_app.core.directory.load_random_stations (PAGE_SIZE), _("Stations to Discover"), fade_heading);
        } // show_random






        /** Makes the header star follow the star of the station playing. */
        private void follow_star (Tuner.Models.Station station)
        {
            if (_star_station != null && _star_handler != 0)
                SignalHandler.disconnect (_star_station, _star_handler);

            _star_station = station;
            _star_handler = station.station_star_changed_sig.connect ((starred) => { show_star_head (); });
            _star_head.sensitive = true;
            show_star_head ();
        } // follow_star


        private void refresh_star_count ()
        {
            _starred_count.label = _app.core.directory.get_starred ().size.to_string ();
            if (_showing_starred && _search.text.strip () == "")
            {
                int total = _app.core.directory.get_starred ().size;
                // TRANSLATORS: Heading; %d is the number of starred stations
                _status.label = total == 0 ? _("No starred stations yet") : _("Starred by You:  %d").printf (total);
            }
        } // refresh_star_count


        private void show_star_head ()
        {
            bool on = _star_station != null && _star_station.starred;
            _setting_star = true;
            _star_head.active = on;
            _setting_star = false;
            _star_head.icon_name = on ? "starred-symbolic" : "non-starred-symbolic";
            refresh_star_count ();
            if (on)
                _star_head.add_css_class ("star-favorited");
            else
                _star_head.remove_css_class ("star-favorited");
        } // show_star_head




        // ----------------------------------------------------------
        // Keyboard
        // ----------------------------------------------------------

        private void add_shortcuts ()
        {
            var keys = new Gtk.ShortcutController ();
            keys.propagation_phase = Gtk.PropagationPhase.CAPTURE;

            add_key (keys, "<Control>f", (w, a) => { _search_toggle.active = true; _search.grab_focus (); return true; });
            add_key (keys, "<Control>p", (w, a) =>
            {
                if (_play.sensitive)
                    _app.core.player.play_pause ();
                return true;
            });
            add_key (keys, "<Control>Up", (w, a) => { nudge_volume (0.05); return true; });
            add_key (keys, "<Control>Down", (w, a) => { nudge_volume (-0.05); return true; });
            add_key (keys, "<Control>r", (w, a) => { show_random (); return true; });
            add_key (keys, "<Control>comma", (w, a) =>
            {
                _menu_button.popup ();
                return true;
            });
            add_key (keys, "<Control>q", (w, a) =>
            {
                _app.core.quit_cleanly ("quit shortcut");
                return true;
            });
            ((Gtk.Widget) this).add_controller (keys);
        } // add_shortcuts


        private static void add_key (Gtk.ShortcutController keys, string accelerator, owned Gtk.ShortcutFunc func)
        {
            keys.add_shortcut (new Gtk.Shortcut (Gtk.ShortcutTrigger.parse_string (accelerator),
                                                 new Gtk.CallbackAction ((owned) func)));
        } // add_shortcut


        private void nudge_volume (double step)
        {
            _app.core.player.volume = (_app.core.player.volume + step).clamp (0.0, 1.0);
        } // nudge_volume


        private void show_tape (int here, int total)
        {
            _tape.label = "%s / %s".printf (clock (here), clock (total));
        } // show_tape


        private static string clock (int seconds)
        {
            return seconds >= 3600
                ? "%d:%02d:%02d".printf (seconds / 3600, (seconds / 60) % 60, seconds % 60)
                : "%d:%02d".printf (seconds / 60, seconds % 60);
        } // clock


        public void show_trending ()
        {
            if (already_showing (_("Trending Stations in the last 24 hours")))
                return;
            show_set.begin (_app.core.directory.load_trending_stations (PAGE_SIZE), _("Trending Stations in the last 24 hours"));
        }

        public void show_popular ()
        {
            if (already_showing (_("Most listened to Stations")))
                return;
            show_set.begin (_app.core.directory.load_popular_stations (PAGE_SIZE), _("Most listened to Stations"));
        }

        public void search (string text)
        {
            var query = text.strip ();
            if (query == "")
                return;
            _latest_query = query;
            // TRANSLATORS: Heading; %s is the text that was searched for
            show_set.begin (_app.core.directory.load_search_stations (query, PAGE_SIZE), _("Search Results"), true, _("Search Results: '%s'").printf (query));
        }

        /** Shows the results of the latest search again, or says there has been none (the view always follows the highlight). */
        private void show_latest_search ()
        {
            string query = _search.text.strip () != "" ? _search.text.strip () : _latest_query;
            if (query != "")
            {
                _clearing_search = true;
                _search.text = query;
                _clearing_search = false;
                _showing_starred = false;
                search (query);
                return;
            }

            _generation++;
            switch_content (() =>
            {
                _view = View.STATIONS;
                clear ();
                _status.label = _("No search result yet...");
            });
        } // show_latest_search

        /** Shows the starred stations, only those matching the filter text (name, tags or country) if there is one. */
        public void show_starred (string filter = "")
        {
            _generation++;

            // Already on show (typing a filter, reordering): refresh in place; otherwise fade over from what is showing
            if (_showing_starred)
                do_show_starred (filter, true);
            else
                switch_content (() => { do_show_starred (filter, false); });
        } // show_starred


        private void do_show_starred (string filter, bool in_place)
        {
            _view = View.STATIONS;
            clear (in_place);
            _showing_starred = true;
            _list_reorderable = filter.strip () == "";        // The order can be changed only in the whole list

            var wanted = filter.strip ().down ();
            var stations = _app.core.directory.get_starred ();
            int shown = 0;
            foreach (var station in stations)
            {
                if (wanted != "" && !matches (station, wanted))
                    continue;
                list_add (station);
                shown++;
            }

            refresh_star_count ();
            if (stations.size == 0)
                _status.label = _("No starred stations yet");
            else if (wanted != "")
                // TRANSLATORS: Heading; the first %d is how many starred stations match the filter, the second how many are starred
                _status.label = _("Starred by You:  %d of %d").printf (shown, stations.size);
            else
                // TRANSLATORS: Heading; %d is the number of starred stations
                _status.label = _("Starred by You:  %d").printf (stations.size);
        } // do_show_starred


        private static bool matches (Tuner.Models.Station station, string wanted)
        {
            return (station.name ?? "").down ().contains (wanted)
                || (station.tags ?? "").down ().contains (wanted)
                || (station.country ?? "").down ().contains (wanted);
        } // matches


        /** Shows some random tags from the directory as buttons. */
        private async void load_tag_chips ()
        {
            if (_loading_tags || _tags_chosen)     // the tags are chosen once per run, not again each time the section is opened
                return;
            _loading_tags = true;

            var tags = yield _app.core.directory.load_random_genres_async (EXPLORE_TAGS);

            // The new choices are built off-screen, then cross-fade over the ones on show
            var page = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            foreach (var tag in tags)
            {
                var name = tag.name;
                var chip = side_item (name, "tuner:playlist-symbolic");
                // TRANSLATORS: Tooltip of a tag; %u is the number of stations with that tag
                chip.tooltip_text = ngettext ("%u station", "%u stations", tag.stationcount).printf (tag.stationcount);
                chip.clicked.connect (() => { show_tag (name); });
                page.append (chip);
            }
            _tag_stack.add_child (page);
            _tag_stack.visible_child = page;
            _tags_chosen = tags.size > 0;           // an empty answer (offline) is tried again
            _loading_tags = false;
        } // load_tag_chips


        /** The station (name, popularity, place) and what its stream has said about itself, in a popover under the header. */
        private void show_metadata_popover ()
        {
            if (_track_station == null)
                return;

            if (_meta_popover == null)
            {
                _meta_label = new Gtk.Label ("");
                _meta_label.wrap = true;
                _meta_label.max_width_chars = 48;
                _meta_label.xalign = 0.0f;
                _meta_label.selectable = false;
                _meta_label.margin_start = _meta_label.margin_end = 8;
                _meta_label.margin_top = _meta_label.margin_bottom = 6;

                _meta_popover = new Gtk.Popover ();
                _meta_popover.position = Gtk.PositionType.BOTTOM;
                _meta_popover.add_css_class ("metadata-popover");
                _meta_popover.child = _meta_label;
                _meta_popover.set_parent (_now);

                // Right click copies the text
                var copy = new Gtk.GestureClick ();
                copy.button = Gdk.BUTTON_SECONDARY;
                copy.pressed.connect ((n_press, x, y) =>
                {
                    var original = _meta_label.label;
                    get_clipboard ().set_text (original);
                    _meta_label.label = _("Copied to clipboard");
                    Timeout.add (1200, () =>
                    {
                        _meta_label.label = original;
                        return Source.REMOVE;
                    });
                });
                ((Gtk.Widget) _meta_popover).add_controller (copy);
            }

            var sb = new StringBuilder ();
            if (_track_station.starred)
                sb.append ("\u2605 ");
            sb.append (_track_station.name).append ("\n\n").append (_track_station.popularity ());
            var locale = _track_station.locale ();
            if (locale != null && locale != "")
                sb.append ("\n\n").append (locale);
            if (_track_metadata != "")
                sb.append ("\n\n").append (_track_metadata);
            _meta_label.label = sb.str;
            _meta_popover.popup ();
        } // show_metadata_popover


        /** Moves a starred station one place up (-1) or down (+1) and shows the new order. */
        private void move_starred (Tuner.Models.Station station, int direction)
        {
            var uuids = new Gee.ArrayList<string> ();
            foreach (var s in _app.core.directory.get_starred ())
                uuids.add (s.stationuuid);

            int from = uuids.index_of (station.stationuuid);
            int to = from + direction;
            if (from < 0 || to < 0 || to >= uuids.size)
                return;

            uuids.remove_at (from);
            uuids.insert (to, station.stationuuid);
            _app.core.directory.reorder_starred (uuids);
            show_starred ();
        } // move_starred

        /** A starred station was dragged onto another: it takes that station's place and the new order is saved. */
        private void drop_starred (string from_uuid, Tuner.Models.Station onto)
        {
            var uuids = new Gee.ArrayList<string> ();
            foreach (var s in _app.core.directory.get_starred ())
                uuids.add (s.stationuuid);

            int from = uuids.index_of (from_uuid);
            int to = uuids.index_of (onto.stationuuid);
            if (from < 0 || to < 0 || from == to)
                return;

            uuids.remove_at (from);
            uuids.insert (to, from_uuid);
            _app.core.directory.reorder_starred (uuids);
            show_starred ();
        } // drop_starred

        public void show_saved_searches ()
        {
            _generation++;
            if (_view == View.SAVED_SEARCHES && _store.n_items > 0)
                do_show_saved_searches (true);          // A search was removed: refresh in place
            else
                switch_content (() => { do_show_saved_searches (false); });
        } // show_saved_searches


        private void do_show_saved_searches (bool in_place)
        {
            _view = View.SAVED_SEARCHES;
            clear (in_place);
            _list.factory = _search_factory;
            _list.max_columns = 1;
            var searches = _app.core.directory.load_saved_searches ();
            foreach (var entry in searches.entries)
                list_add (new Gtk.StringObject (entry.key));
            _status.label = searches.size == 0 ? _("No saved searches yet...")
                                               : _("Saved Searches");
        } // do_show_saved_searches

        /** Saves the window size, so the next start opens the same way. */
        public void remember_size ()
        {
            _app.core.settings.remember_window_geometry (0, 0, get_width (), get_height ());
        } // remember_size


        /** A row was activated (double click, or Enter): play the station, or run the saved search. */
        private void on_list_activated (uint position)
        {
            var item = _store.get_item (position);

            var station = item as Tuner.Models.Station;
            if (station != null)
            {
                play_clicked (station);
                return;
            }

            var search = item as Gtk.StringObject;
            if (search != null)
            {
                _search.text = search.string;
                this.search (search.string);
            }
        } // on_list_activated


        /** The two kinds of row the list shows: a row is made empty, then bound to its item as it scrolls into view. */
        private void build_factories ()
        {
            _station_factory = new Gtk.SignalListItemFactory ();
            _station_factory.setup.connect ((object) =>
            {
                var item = (Gtk.ListItem) object;
                var row = new StationRow (_app.core.session);
                row.stars = _app.core.stars;
                row.station_dropped.connect (drop_starred);
                row.move_requested.connect (move_starred);
                row.star_toggled.connect (() => { refresh_star_count (); });
                row.update_requested.connect ((s) =>
                {
                    var fresh = s.updated ();
                    if (fresh == null)
                        return;
                    fresh.starred = s.starred;
                    _app.core.stars.update (fresh);
                    if (_showing_starred)
                        show_starred (_search.text);
                });
                row.note_requested.connect ((s) =>
                {
                    new NoteWindow (this, _app.core, s).present ();
                });
                item.child = row;
            });
            _station_factory.bind.connect ((object) =>
            {
                var item = (Gtk.ListItem) object;
                ((StationRow) item.child).bind ((Tuner.Models.Station) item.item, _list_reorderable);
            });
            _station_factory.unbind.connect ((object) =>
            {
                ((StationRow) ((Gtk.ListItem) object).child).unbind ();
            });

            _search_factory = new Gtk.SignalListItemFactory ();
            _search_factory.setup.connect ((object) =>
            {
                var item = (Gtk.ListItem) object;
                var row = new SearchRow ();
                row.remove_requested.connect ((text) =>
                {
                    _app.core.directory.remove_saved_search (text);
                    show_saved_searches ();
                });
                item.child = row;
            });
            _search_factory.bind.connect ((object) =>
            {
                var item = (Gtk.ListItem) object;
                ((SearchRow) item.child).bind (((Gtk.StringObject) item.item).string);
            });
        } // build_factories


        /** @param keep_visible Leave the list showing (the same list is being refreshed), instead of fading the new content in */
        private void clear (bool keep_visible = false)
        {
            _set = null;
            _showing_starred = false;
            _list_reorderable = false;
            if (_list.factory != _station_factory)
                _list.factory = _station_factory;
            _list.max_columns = 20;
            _shuffle.visible = false;
            _save_search.visible = false;
            if (!keep_visible)
            {
                Fade.cancel (_list);
                _list.opacity = 0.0;
                _list_revealing = false;
            }
            _store.remove_all ();
        } // clear


        private const uint FADE_OUT_MS = 200;     // The GTK3 page stack crossfades in 200ms,
        private const uint ELLIPSIS_FADE_MS = FADE_OUT_MS + 250;   // The loading ellipsis fades in and out a quarter second slower
        private const uint FADE_IN_MS = 400;      // and its station list fades in over 400ms
        private const uint HEADING_DELAY_MS = 250;    // a beat after the old heading has gone, before the new one starts to show
        private const uint HEADING_FADE_IN_MS = FADE_IN_MS;  // the heading fades in over the same time as the list

        /** Fades the list and its heading out; finishes when they are gone. */
        private async void fade_out_content (bool fade_heading = true)
        {
            if (fade_heading)
                Fade.to (_status, 0.0, FADE_OUT_MS);
            if (fade_heading && _shuffle.visible)
                Fade.to (_shuffle, 0.0, FADE_OUT_MS);
            Fade.to (_list, 0.0, FADE_OUT_MS, () =>
            {
                Idle.add (() => { fade_out_content.callback (); return Source.REMOVE; });
            });
            yield;
        } // fade_out_content


        /**
         * Runs a change of content once what is on show has faded out. The caller has already counted a new
         * generation, so a request made during the fade replaces this one.
         */
        private void switch_content (owned FadeDone body)
        {
            int generation = _generation;
            if (_store.n_items == 0 || !_list.get_mapped ())
            {
                body ();
                return;
            }

            fade_out_content.begin (true, (obj, res) =>
            {
                fade_out_content.end (res);
                if (generation == _generation)
                    body ();
            });
        } // switch_content


        /** Shows the first page of a station set. Only the newest request may fill the list. */
        private async void show_set (Tuner.StationSet set, string title, bool fade_heading = true, string? heading = null)
        {
            int generation = ++_generation;
            _view = View.STATIONS;

            // The stations on show fade out before the new set replaces them
            if (_store.n_items > 0 && _list.get_mapped ())
            {
                yield fade_out_content (fade_heading);
                if (generation != _generation)
                    return;
            }
            // A "Connecting…" or "Offline" message fades out before the first heading comes in
            if (fade_heading && _status.opacity > 0.0 && (_status.label == _("Connecting to the station directory…") || _status.label == C_("connection status", "Offline")))
            {
                bool resumed = false;
                SourceFunc resume = () =>
                {
                    if (!resumed)
                    {
                        resumed = true;
                        show_set.callback ();
                    }
                    return false;
                };
                Fade.to (_status, 0.0, FADE_OUT_MS, () => { resume (); });
                Timeout.add (FADE_OUT_MS + 100, () => { resume (); return false; });
                yield;
                if (generation != _generation)
                    return;
            }
            clear ();
            _set = set;
            _set_title = title;
            _shuffle.visible = title == _("Stations to Discover");
            _save_search.visible = title == _("Search Results");
            _shuffle.opacity = _status.opacity;     // the Discover button comes and goes with the heading
            ++_heading_token;
            _status.label = heading ?? title;      // What the heading says may add to the set's name, such as the search term
            if (fade_heading && _status.opacity < 1.0)     // a heading fading out, or one with the same text as before and so no notification: bring it up
            {
                Fade.to (_status, 1.0, HEADING_FADE_IN_MS, null, HEADING_DELAY_MS);
                if (_shuffle.visible)
                    Fade.to (_shuffle, 1.0, HEADING_FADE_IN_MS, null, HEADING_DELAY_MS);
            }
            Fade.to (_loading, 1.0, ELLIPSIS_FADE_MS, null, fade_heading ? HEADING_DELAY_MS : 0);
            yield fill_page (set, heading ?? title, generation);
        } // show_set


        /** What goes between a heading and a message after it: a colon, unless the heading already has one (as a search heading does, before the term). */
        private static string heading_join (string heading)
        {
            return heading.contains (":") ? "  -  " : ":  ";
        } // heading_join


        /**
         * Adds the first page of a set to the list, as the GTK3 app does: one page, no "load more". The directory
         * answers a failed request like a search that found nothing; choosing the entry again asks again.
         */
        private async void fill_page (Tuner.StationSet set, string title, int generation)
        {
            try
            {
                var page = yield set.next_page_async ();
                if (generation == _generation)
                    Fade.to (_loading, 0.0, ELLIPSIS_FADE_MS);
                if (generation != _generation)
                    return;

                if (page == null)
                {
                    _status.label = C_("connection status", "Offline");
                    return;
                }
                foreach (var station in page)
                    list_add (station);

                if (_store.n_items == 0)
                    // TRANSLATORS: Follows a heading, as in "Search Results:  No Stations"
                    _status.label = title + heading_join (title) + _("No Stations");
            } catch (SourceError e)
            {
                if (generation == _generation)
                    Fade.to (_loading, 0.0, ELLIPSIS_FADE_MS);
                if (generation == _generation)
                    // TRANSLATORS: Follows a heading, as in "Search Results:  the directory did not answer"
                    _status.label = title + heading_join (title) + _("the directory did not answer");
            }
        } // fill_page
    } // MainWindow
} // TunerGtk4
