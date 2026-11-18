/**
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * @file NowPlaying.vala
 *
 * @brief The centre of the header bar: the playing station's icon, its name, and the track. Ported from the GTK3
 * PlayingStationInfo.
 */

namespace TunerGtk4
{
    /**
     * @class NowPlaying
     * @brief Shows the station and track playing, and carries out the change from one station to the next.
     *
     * A change of station, as in the GTK3 app (whose revealer slides up): the block collapses vertically; part way
     * the old station and track are cleared; once the player has settled the new station is put in and the block
     * expands again, and the track starts to cycle. At startup the block opens after a short wait. Metadata that
     * arrives during the change is kept and shown when it is done.
     */
    public class NowPlaying : Gtk.Box
    {
        private const int FAVICON_PX = 48;           // The station's favicon: the same as GTK3, and so inside the bar's height
        private const int FAVICON_NUDGE_PX = 3;       // Moves the icon down a pixel or two, so it is not tight to the bar top
        private const int BLOCK_HEIGHT_PX = FAVICON_PX + FAVICON_NUDGE_PX;   // The block never gets shorter: the bar must not change height as it collapses
        private const uint ICON_FADE_MS = 400u;      // A favicon that arrives late fades in
        private const int DEFAULT_ICON_PX = 36;      // The Tuner logo shown when there is no favicon
        private const uint REVEAL_MS = 1200u;        // The block collapsing or expanding, each way (GTK3: 3 x 400ms)
        private const uint CLEAR_MS = 667u;          // Part way through the collapse the old station is cleared (5/3 x 400ms)
        private const string DEFAULT_ICON = "tuner:internet-radio-symbolic";

        /** The track line, for binding its settings */
        public SlidingLabel track { get; private set; }

        private Gtk.Revealer _revealer = new Gtk.Revealer ();
        private Gtk.Image _icon;
        private Gtk.Label _station;
        private Gtk.Box _text;                       // Station name and track: its width is held while the block collapses
        private Tuner.Models.Station? _icon_station = null;     // Station whose favicon the icon follows
        private ulong _icon_handler = 0;
        private uint _change_id = 0;
        private bool _changing = false;
        private Tuner.Models.StreamMetadata? _pending = null;   // Arrived during a change
        private string _last_pretty = "";
        private bool _online = true;
        private Gdk.Texture? _preloaded = null;      // The next station's favicon, decoded while the old station collapses
        private string _preloaded_path = "";


        public NowPlaying ()
        {
            Object (orientation: Gtk.Orientation.VERTICAL, spacing: 0);
            halign = Gtk.Align.CENTER;
            valign = Gtk.Align.CENTER;
            set_size_request (-1, BLOCK_HEIGHT_PX);      // Collapsing the block changes only what is drawn, never the bar's height

            var content = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 10);
            content.halign = Gtk.Align.CENTER;
            content.valign = Gtk.Align.CENTER;
            _revealer.transition_type = Gtk.RevealerTransitionType.SLIDE_UP;
            _revealer.transition_duration = REVEAL_MS;
            _revealer.reveal_child = false;
            _revealer.child = content;
            _revealer.valign = Gtk.Align.CENTER;
            _revealer.vexpand = true;
            append (_revealer);

            // Opens a moment after the window is up
            ulong shown = 0;
            shown = map.connect (() =>
            {
                disconnect (shown);
                Timeout.add (REVEAL_MS, () =>
                {
                    if (!_changing)
                        _revealer.reveal_child = true;
                    return Source.REMOVE;
                });
            });

            _station = new Gtk.Label ("Tuner");
            _station.xalign = 0.5f;
            _station.justify = Gtk.Justification.CENTER;
            _station.halign = Gtk.Align.CENTER;
            _station.ellipsize = Pango.EllipsizeMode.MIDDLE;
            _station.add_css_class ("station-label");
            _station.add_css_class ("idle");                    // The idle "Tuner" is shown larger
            _station.notify["label"].connect (() =>
            {
                if (_station.label == "Tuner")
                    _station.add_css_class ("idle");
                else
                    _station.remove_css_class ("idle");
            });

            track = new SlidingLabel (100);

            _text = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            _text.valign = Gtk.Align.CENTER;
            _text.halign = Gtk.Align.CENTER;
            _text.append (_station);
            _text.append (track);

            // The icon sits in a frame of fixed size, so a large favicon is clipped rather than widening the bar
            _icon = new Gtk.Image.from_icon_name (DEFAULT_ICON);
            _icon.pixel_size = DEFAULT_ICON_PX;
            var frame = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            frame.set_size_request (FAVICON_PX, FAVICON_PX);
            frame.overflow = Gtk.Overflow.HIDDEN;
            frame.valign = Gtk.Align.CENTER;
            frame.margin_top = FAVICON_NUDGE_PX;
            _icon.halign = Gtk.Align.CENTER;
            _icon.valign = Gtk.Align.CENTER;
            _icon.hexpand = true;
            frame.append (_icon);

            content.append (frame);
            content.append (_text);
        } // NowPlaying


        /** Whether the directory is reachable: the icon dims when it is not */
        public bool online
        {
            set
            {
                _online = value;
                Fade.cancel (_icon);
                _icon.opacity = value ? 1.0 : 0.5;
            }
        }


        /** Changes to a station, with the transition described above. */
        public void change_station (Tuner.Models.Station station)
        {
            uint id = ++_change_id;
            _changing = true;
            _pending = null;
            _last_pretty = "";
            uint settle = Tuner.Controllers.PlayerController.STATION_CHANGE_SETTLE_MS;

            // Nothing may move sideways while the block collapses: hold the text's width from the start, and stop the
            // track line cycling its sublabels (each would glide the width)
            _text.set_size_request (_text.get_width (), -1);
            track.stop ();
            _revealer.reveal_child = false;
            preload_favicon (station, id);
            Timeout.add (CLEAR_MS, () =>
            {
                if (id != _change_id)
                    return Source.REMOVE;
                // The old station is cleared while the block is still collapsing; the width is held, so only the vertical
                // collapse shows
                track.clear (false);
                _station.label = "";
                _icon.clear ();
                return Source.REMOVE;
            });

            Timeout.add (settle, () =>
            {
                if (id != _change_id)
                    return Source.REMOVE;
                // Fully collapsed by now: the width can change unseen, and the block opens at the new station's width
                _text.set_size_request (-1, -1);
                track.reset_width ();
                _station.label = station.name;
                follow_favicon (station);
                _revealer.reveal_child = true;
                _changing = false;
                track.cycle ();
                if (_pending != null)
                {
                    apply (_pending);
                    _pending = null;
                }
                return Source.REMOVE;
            });
        } // change_station


        /** Shows the stream's metadata: now, or once the station change is done. Repeats are ignored. */
        public void handle_metadata (Tuner.Models.StreamMetadata metadata)
        {
            if (_changing)
            {
                _pending = metadata;
                return;
            }
            if (_last_pretty == (metadata.pretty_print ?? ""))
                return;
            apply (metadata);
        } // handle_metadata


        private void apply (Tuner.Models.StreamMetadata metadata)
        {
            _last_pretty = metadata.pretty_print ?? "";
            track.notify_metadata_changed ();
            track.add_sublabel (1, metadata.genre, metadata.homepage);
            track.add_sublabel (2, metadata.audio_info);
            track.add_sublabel (3, metadata.org_loc);
            track.label = metadata.title ?? "";
        } // apply


        /** Makes the icon follow the favicon of the station playing. */
        private void follow_favicon (Tuner.Models.Station station)
        {
            if (_icon_station != null && _icon_handler != 0)
                SignalHandler.disconnect (_icon_station, _icon_handler);

            _icon_station = station;
            _icon_handler = station.favicon_sig.connect (() => { show_icon (true); });    // Arrived after the block opened: fade in
            show_icon ();
        } // follow_favicon


        /** Decodes the station's favicon off the main thread while the old station collapses, so showing it does not cost a frame. */
        private void preload_favicon (Tuner.Models.Station station, uint id)
        {
            _preloaded = null;
            _preloaded_path = "";
            if (station.favicon_failing ())
                return;
            string? path = station.favicon_image_file ();
            if (path == null)
                return;

            string file = path;
            new Thread<void> ("favicon-decode", () =>
            {
                Gdk.Texture? texture = null;
                try
                {
                    texture = Gdk.Texture.from_filename (file);
                }
                catch (Error e)
                {
                    // Not decodable here: show_icon() falls back to loading the file itself
                }
                Idle.add (() =>
                {
                    if (id == _change_id && texture != null)
                    {
                        _preloaded = texture;
                        _preloaded_path = file;
                    }
                    return Source.REMOVE;
                });
            });
        } // preload_favicon


        private void show_icon (bool fade = false)
        {
            string? path = null;
            if (_icon_station != null && !_icon_station.favicon_failing ())
                path = _icon_station.favicon_image_file ();

            if (path != null)
            {
                _icon.pixel_size = FAVICON_PX;
                if (_preloaded != null && _preloaded_path == path)
                    _icon.set_from_paintable (_preloaded);
                else
                    _icon.set_from_file (path);
                if (fade)
                {
                    _icon.opacity = 0.0;
                    Fade.to (_icon, _online ? 1.0 : 0.5, ICON_FADE_MS);
                }
            }
            else
            {
                _icon.pixel_size = DEFAULT_ICON_PX;
                _icon.icon_name = DEFAULT_ICON;
            }
        } // show_icon
    } // NowPlaying
}
