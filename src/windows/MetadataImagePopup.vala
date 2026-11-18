/**
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * @file MetadataImagePopup.vala
 */

/**
 * @class MetadataImagePopup
 * @brief A frameless, movable popup showing the image a stream offers in its metadata (cover art, for instance).
 *
 * The core's `StreamMetadata.get_image_url ()` finds the address; this fetches it with the core's HTTP client and
 * shows it. It follows the "Stream metadata image popup" preference (`enabled`), and hides itself when the
 * metadata has no image, the preference is off, or the picture cannot be loaded.
 */
public class TunerGtk4.MetadataImagePopup : Gtk.Window
{
    private const int MAX_IMAGE_SIZE = 320;
    private const size_t MAX_IMAGE_BYTES = 10 * 1024 * 1024;
    private const double DORMANT_OPACITY = 0.01;     // Not 0: GTK does not paint a fully transparent window (see Fade.window_in)

    private Gtk.Picture _picture = new Gtk.Picture ();
    private Gtk.Window _parent;
    private bool _moving = false;
    private uint _load_generation = 0;
    private string _current_url = "";
    private bool _dormant = false;      // Mapped but empty, 1 pixel and all but invisible: it keeps its place behind other windows

    /** Follows the preference: a popup that is behind other windows is kept there, not raised, when a new image comes. */
    public bool stay_back { get; set; default = true; }

    /** Follows the preference: switched off, the popup hides and ignores the metadata. */
    public bool enabled { get; set; default = false; }


    public MetadataImagePopup (Gtk.Window parent)
    {
        // Not transient: a transient window is held above its parent, so it could never be sent behind it
        Object (decorated: false, resizable: false);
        _parent = parent;

        _picture.content_fit = Gtk.ContentFit.CONTAIN;
        _picture.can_shrink = false;
        child = _picture;

        // Drag it anywhere to move it (the move starts once the pointer has really moved, so a click is still a click)
        var drag = new Gtk.GestureDrag ();
        drag.button = Gdk.BUTTON_PRIMARY;
        drag.drag_update.connect ((offset_x, offset_y) =>
        {
            if (_moving || (offset_x.abs () < 4 && offset_y.abs () < 4))
                return;

            double start_x, start_y;
            drag.get_start_point (out start_x, out start_y);
            var toplevel = get_surface () as Gdk.Toplevel;
            var device = drag.get_device ();
            if (toplevel != null && device != null)
            {
                _moving = true;
                toplevel.begin_move (device, (int) drag.get_current_button (), start_x, start_y,
                                     drag.get_current_event_time ());
            }
        });
        drag.drag_begin.connect ((x, y) => { _moving = false; });
        drag.drag_end.connect ((offset_x, offset_y) => { _moving = false; });
        _picture.add_controller (drag);      // the picture fills the window (Gtk.Window hides add_controller)

        // Double click sends it to the back: GTK4 cannot lower a window, so the main window is raised over it
        var click = new Gtk.GestureClick ();
        click.button = Gdk.BUTTON_PRIMARY;
        click.pressed.connect ((n_press, x, y) =>
        {
            if (n_press == 2)
                _parent.present ();
        });
        _picture.add_controller (click);

        notify["enabled"].connect (() =>
        {
            if (!enabled)
                hide_popup ();
        });
    } // MetadataImagePopup


    /** The latest metadata of the playing stream: show its image, or hide the popup when it has none. */
    public void handle_metadata (Tuner.Models.StreamMetadata? metadata)
    {
        if (!enabled || metadata == null)
        {
            hide_popup ();
            return;
        }

        var url = metadata.get_image_url ();
        if (url == "")
        {
            hide_popup ();
            return;
        }

        if (url == _current_url)
            return;

        _current_url = url;
        load_image.begin (url);
    } // handle_metadata


    /**
     * Hides the popup; the same image is fetched again if it comes round later.
     *
     * GTK4 cannot lower a window or raise one without bringing it to the front, and a window shown again opens in front.
     * So a popup that is behind other windows is not hidden: it is emptied and shrunk to a pixel, and keeps its place, and
     * the next image fills it again, still behind. (It shows in the window switcher meanwhile.)
     */
    private void hide_popup ()
    {
        _load_generation++;
        _current_url = "";

        if (enabled && stay_back && visible && !is_active)
        {
            _picture.paintable = null;
            _picture.set_size_request (1, 1);
            opacity = DORMANT_OPACITY;
            _dormant = true;
            return;
        }

        _dormant = false;
        opacity = 1.0;
        visible = false;
    } // hide_popup


    private async void load_image (string url)
    {
        uint load_id = ++_load_generation;

        Uri? uri = null;
        try
        {
            uri = Uri.parse (url, UriFlags.NONE);
        }
        catch (UriError e)
        {
            hide_popup ();
            return;
        }

        uint status_code;
        InputStream? stream = yield Tuner.Services.HttpClient.GETasync (uri, Priority.LOW, out status_code);
        if (load_id != _load_generation)
            return;

        if (stream == null || status_code < 200 || status_code >= 300)
        {
            hide_popup ();
            return;
        }

        try
        {
            var data = new ByteArray ();
            while (data.len < MAX_IMAGE_BYTES)
            {
                var chunk = yield stream.read_bytes_async (64 * 1024, Priority.LOW);
                if (chunk.get_size () == 0)
                    break;
                data.append (chunk.get_data ());
            }
            if (load_id != _load_generation)
                return;

            var texture = Gdk.Texture.from_bytes (ByteArray.free_to_bytes ((owned) data));
            int w = texture.get_width ();
            int h = texture.get_height ();
            double scale = double.min (1.0, (double) MAX_IMAGE_SIZE / (double) int.max (w, h));
            _picture.paintable = texture;
            _picture.set_size_request ((int) (w * scale), (int) (h * scale));
            _dormant = false;
            opacity = 1.0;
            if (!visible)
                present ();         // Opens in front; a popup already on show (or kept behind) just changes its picture, and stays where it is
        }
        catch (Error e)
        {
            if (load_id == _load_generation)
                hide_popup ();
        }
    } // load_image
} // MetadataImagePopup
