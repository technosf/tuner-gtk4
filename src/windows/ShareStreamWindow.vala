/**
 * SPDX-FileCopyrightText: Copyright © 2026 <https://github.com/technosf>
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * @file ShareStreamWindow.vala
 *
 * @brief Ported from the GTK3 app: a small window for sharing a station's stream URI.
 */

namespace TunerGtk4
{
    /**
     * @class ShareStreamWindow
     * @brief Shows a "card": the station name above a QR code of the stream URI, with the radio tower icon in the
     * middle of the code, and the URI itself below the card. Clicking the card copies its image to the clipboard,
     * clicking the URI copies the URI text, and a floating message confirms either. Escape closes the window.
     *
     * The card is always dark on white, with the standard four-module quiet zone around the code, whatever the
     * theme is, because scanners need that contrast. The icon hides some modules in the middle of the code, which
     * the QR error correction makes up for, so the code is encoded with the highest error correction that fits the
     * URI, the icon is sized to the level, and there is no icon when only the lowest level fits.
     */
    public class ShareStreamWindow : Gtk.Window
    {
        private const int    QUIET_ZONE_MODULES = 4;      // required blank border around a QR code, in modules
        private const int    CARD_MIN_SIZE_PX   = 280;    // smallest drawn width of the card on screen
        private const int    COPY_MIN_SIZE_PX   = 512;    // smallest width of the card image put on the clipboard
        private const int    URI_MAX_CHARS      = 44;     // wrap the URI at about this many characters
        private const uint   MESSAGE_MS         = 1800u;  // how long the "copied" message stays
        private const double HEADER_RATIO       = 0.13;   // height of the name header as a share of the card width
        private const double NAME_FONT_RATIO    = 0.4675; // name font size as a share of the header height
        private const string ICON_RESOURCE      = "/io/github/tuner_labs/tuner/gtk4/icons/tuner:internet-radio-symbolic.svg";

        private static ShareStreamWindow? _open = null;     // Only one is open: choosing another station replaces it

        private string _name;
        private string _uri;
        private Qr.Code? _code = null;
        private Qr.EcLevel _level = Qr.EcLevel.L;
        private Rsvg.Handle? _icon = null;
        private int _module_px = 1;
        private Gtk.Revealer _message_revealer;
        private Gtk.Label _message_label;
        private uint _message_timeout = 0u;


        public ShareStreamWindow (Gtk.Window parent, Tuner.Models.Station station)
        {
            Object (transient_for: parent, destroy_with_parent: true, title: _("Share stream URI"), resizable: false);

            if (_open != null)
                _open.close ();
            _open = this;
            Fade.window_in (this);

            _name = station.name;

            // UrlResolved is the stream itself; url can be a playlist
            _uri = (station.urlResolved == null || station.urlResolved == "") ? station.url : station.urlResolved;
            _code = encode (_uri, out _level);
            load_icon ();

            var content = new Gtk.Box (Gtk.Orientation.VERTICAL, 12);
            content.margin_top = content.margin_bottom = content.margin_start = content.margin_end = 20;

            // The card, or a note when the URI is too long for a QR code
            if (_code != null)
            {
                int total = _code.width + 2 * QUIET_ZONE_MODULES;
                _module_px = (CARD_MIN_SIZE_PX + total - 1) / total;     // whole pixels per module keeps the code sharp

                // The card is drawn here, before the window opens, and shown as a picture of fixed size
                var area = new Gtk.Picture.for_paintable (render_card (_module_px));
                area.can_shrink = false;
                area.halign = Gtk.Align.CENTER;
                area.tooltip_text = _("Click to copy the QR code image to the clipboard");
                area.cursor = new Gdk.Cursor.from_name ("pointer", null);

                // Click the card to copy its image
                var click = new Gtk.GestureClick ();
                click.button = Gdk.BUTTON_PRIMARY;
                click.released.connect ((n_press, x, y) => { copy_card_image (); });
                area.add_controller (click);
                content.append (area);
            }
            else
            {
                var name_label = new Gtk.Label (null);
                name_label.set_markup ("<b>%s</b>".printf (Markup.escape_text (_name)));
                name_label.ellipsize = Pango.EllipsizeMode.END;
                name_label.max_width_chars = URI_MAX_CHARS;
                content.append (name_label);

                var too_long = new Gtk.Label (_("The stream URI is too long for a QR code"));
                too_long.add_css_class ("dim-label");
                content.append (too_long);
            }

            // The URI: click to copy
            var uri_label = new Gtk.Label (null);
            uri_label.set_markup ("<span underline=\"single\">%s</span>".printf (Markup.escape_text (_uri)));
            uri_label.wrap = true;
            uri_label.wrap_mode = Pango.WrapMode.CHAR;
            uri_label.natural_wrap_mode = Gtk.NaturalWrapMode.NONE;
            uri_label.max_width_chars = URI_MAX_CHARS;
            uri_label.width_chars = URI_MAX_CHARS;      // a fixed width, so the window is not resized when the text wraps
            uri_label.justify = Gtk.Justification.CENTER;

            var uri_button = new Gtk.Button ();
            uri_button.has_frame = false;
            uri_button.tooltip_text = _("Click to copy the stream URI to the clipboard");
            uri_button.child = uri_label;
            uri_button.clicked.connect (copy_uri);
            uri_button.cursor = new Gdk.Cursor.from_name ("pointer", null);
            content.append (uri_button);

            // Floating confirmation, over the bottom of the content
            _message_label = new Gtk.Label ("");
            _message_label.add_css_class ("app-notification");
            _message_label.margin_top = _message_label.margin_bottom = 6;
            _message_label.margin_start = _message_label.margin_end = 12;

            _message_revealer = new Gtk.Revealer ();
            _message_revealer.halign = Gtk.Align.CENTER;
            _message_revealer.valign = Gtk.Align.END;
            _message_revealer.margin_bottom = 14;
            _message_revealer.transition_type = Gtk.RevealerTransitionType.CROSSFADE;
            _message_revealer.transition_duration = 200;
            _message_revealer.reveal_child = false;
            _message_revealer.visible = false;        // nothing but the card shows until there is a message
            _message_revealer.child = _message_label;

            var overlay = new Gtk.Overlay ();
            overlay.child = content;
            overlay.add_overlay (_message_revealer);
            child = overlay;

            // Escape closes it
            var keys = new Gtk.ShortcutController ();
            keys.add_shortcut (new Gtk.Shortcut (Gtk.ShortcutTrigger.parse_string ("Escape"),
                                                 new Gtk.CallbackAction ((w, a) => { close (); return true; })));
            ((Gtk.Widget) this).add_controller (keys);

            close_request.connect (() =>
            {
                if (_open == this)
                    _open = null;
                if (_message_timeout != 0u)
                {
                    Source.remove (_message_timeout);
                    _message_timeout = 0u;
                }
                return false;
            });
        } // ShareStreamWindow


        /** @brief Tries the highest error-correction level first, then lower ones, which fit more text. */
        private static Qr.Code? encode (string uri, out Qr.EcLevel level)
        {
            Qr.EcLevel[] levels = { Qr.EcLevel.H, Qr.EcLevel.Q, Qr.EcLevel.M, Qr.EcLevel.L };

            level = Qr.EcLevel.L;
            foreach (var candidate in levels)
            {
                var code = Qr.Code.encode_string (uri, 0, candidate, Qr.Mode.BYTE, 1);
                if (code != null)
                {
                    level = candidate;
                    return code;
                }
            }
            return null;
        } // encode


        /** @brief Loads the radio tower icon, drawn in black so it stands out on the white patch. */
        private void load_icon ()
        {
            try
            {
                var bytes = GLib.resources_lookup_data (ICON_RESOURCE, GLib.ResourceLookupFlags.NONE);

                // Resource data is not guaranteed to end in a NUL, so copy exactly its length
                var text = new StringBuilder.sized (bytes.get_size ());
                text.append_len ((string) bytes.get_data (), (ssize_t) bytes.get_size ());

                var svg = text.str.replace ("#666", "#000");     // the symbolic icon is grey
                _icon = new Rsvg.Handle.from_data (svg.data);
            }
            catch (GLib.Error e)
            {
                warning ("Unable to load the radio tower icon: %s", e.message);
            }
        } // load_icon


        /** @brief Share of the code's width the icon patch may cover; 0 when the level is too low to hide anything. */
        private double icon_share ()
        {
            switch (_level)
            {
                case Qr.EcLevel.H: return 0.26;
                case Qr.EcLevel.Q: return 0.20;
                case Qr.EcLevel.M: return 0.15;
                default:           return 0.0;
            }
        } // icon_share


        private int card_width (int module_px)
        {
            return (_code.width + 2 * QUIET_ZONE_MODULES) * module_px;
        } // card_width


        private int card_height (int module_px)
        {
            int width = card_width (module_px);
            return (int) (width * HEADER_RATIO) + width;
        } // card_height


        /** @brief Paints the card: the station name, then the QR code with the icon in its middle. */
        private void paint_card (Cairo.Context cr, int module_px)
        {
            if (_code == null)
                return;

            int width = card_width (module_px);
            int height = card_height (module_px);
            int header = height - width;

            cr.set_antialias (Cairo.Antialias.DEFAULT);
            cr.set_source_rgb (1.0, 1.0, 1.0);
            cr.rectangle (0, 0, width, height);
            cr.fill ();

            paint_name (cr, width, header);

            cr.save ();
            cr.translate (0, header);
            paint_code (cr, module_px);
            cr.restore ();
        } // paint_card


        /** @brief Paints the station name centred in the header, shortened with an ellipsis if it is too long. */
        private void paint_name (Cairo.Context cr, int width, int header)
        {
            var layout = Pango.cairo_create_layout (cr);
            var font = new Pango.FontDescription ();
            font.set_family ("Sans");
            font.set_weight (Pango.Weight.BOLD);
            font.set_absolute_size (header * NAME_FONT_RATIO * Pango.SCALE);
            layout.set_font_description (font);
            layout.set_text (_name, -1);

            // The layout box is centred on the card and the text is centred within the box
            int box_width = (int) (width * 0.9);
            layout.set_width (box_width * Pango.SCALE);
            layout.set_ellipsize (Pango.EllipsizeMode.END);
            layout.set_alignment (Pango.Alignment.CENTER);

            int text_w, text_h;
            layout.get_pixel_size (out text_w, out text_h);

            cr.set_source_rgb (0.0, 0.0, 0.0);
            cr.move_to ((width - box_width) / 2.0, header - text_h);     // sits just above the quiet zone
            Pango.cairo_show_layout (cr, layout);
        } // paint_name


        /** @brief Paints the QR code, quiet zone included, and the icon patch in its middle. */
        private void paint_code (Cairo.Context cr, int module_px)
        {
            int modules = _code.width;
            int total = modules + 2 * QUIET_ZONE_MODULES;
            cr.set_antialias (Cairo.Antialias.NONE);

            cr.set_source_rgb (1.0, 1.0, 1.0);
            cr.rectangle (0, 0, total * module_px, total * module_px);
            cr.fill ();

            cr.set_source_rgb (0.0, 0.0, 0.0);
            for (int y = 0; y < modules; y++)
            {
                for (int x = 0; x < modules; x++)
                {
                    if ((_code.data[y * modules + x] & 1) != 0)
                        cr.rectangle ((x + QUIET_ZONE_MODULES) * module_px, (y + QUIET_ZONE_MODULES) * module_px,
                                      module_px, module_px);
                }
            }
            cr.fill ();

            paint_icon (cr, module_px);
        } // paint_code


        /** @brief Paints a white patch with the radio tower icon over the middle of the code (a whole, odd number of modules). */
        private void paint_icon (Cairo.Context cr, int module_px)
        {
            double share = icon_share ();
            if (_icon == null || share <= 0.0)
                return;

            int modules = _code.width;
            int patch = (int) (modules * share);
            if (patch % 2 == 0)
                patch--;                       // odd, so the patch is centred on the middle module
            if (patch < 5)
                return;                        // too small to be worth drawing

            int first = QUIET_ZONE_MODULES + (modules - patch) / 2;
            double px = first * module_px;
            double size = patch * module_px;

            cr.set_antialias (Cairo.Antialias.DEFAULT);

            // White patch, with a one-module margin around the icon
            cr.set_source_rgb (1.0, 1.0, 1.0);
            cr.rectangle (px, px, size, size);
            cr.fill ();

            // The current librsvg call: the document is fitted into the box we give it
            var box = Rsvg.Rectangle ();
            box.x = px + module_px;
            box.y = px + module_px;
            box.width = size - 2.0 * module_px;
            box.height = size - 2.0 * module_px;
            try
            {
                _icon.render_document (cr, box);
            }
            catch (GLib.Error e)
            {
                warning ("Unable to draw the radio tower icon: %s", e.message);
            }
        } // paint_icon


        /** @brief Draws the card to an image, at the given pixels per module. */
        private Gdk.Texture render_card (int module_px)
        {
            int width = card_width (module_px);
            int height = card_height (module_px);

            var surface = new Cairo.ImageSurface (Cairo.Format.ARGB32, width, height);
            var cr = new Cairo.Context (surface);
            paint_card (cr, module_px);
            surface.flush ();

            // Cairo's ARGB32 is premultiplied BGRA on little-endian machines; the card is opaque anyway
            int stride = surface.get_stride ();
            uint8[] pixels = new uint8[stride * height];
            Memory.copy (pixels, surface.get_data (), pixels.length);
            return new Gdk.MemoryTexture (width, height, Gdk.MemoryFormat.B8G8R8A8_PREMULTIPLIED,
                                          new Bytes.take ((owned) pixels), stride);
        } // render_card


        /** @brief Copies an image of the card, drawn larger so it stays sharp when pasted, and confirms it. */
        private void copy_card_image ()
        {
            if (_code == null)
                return;

            int total = _code.width + 2 * QUIET_ZONE_MODULES;
            int px = (COPY_MIN_SIZE_PX + total - 1) / total;
            get_clipboard ().set_texture (render_card (px));
            show_message (_("QR code copied to clipboard"));
        } // copy_card_image


        private void copy_uri ()
        {
            get_clipboard ().set_text (_uri);
            show_message (_("Stream URI copied to clipboard"));
        } // copy_uri


        /** @brief Shows the floating message for a short time. */
        private void show_message (string text)
        {
            if (_message_timeout != 0u)
                Source.remove (_message_timeout);

            _message_label.label = text;
            _message_revealer.visible = true;
            _message_revealer.reveal_child = true;
            _message_timeout = Timeout.add (MESSAGE_MS, () =>
            {
                _message_revealer.reveal_child = false;
                _message_timeout = 0u;
                return Source.REMOVE;
            });
        } // show_message
    } // ShareStreamWindow
} // TunerGtk4
