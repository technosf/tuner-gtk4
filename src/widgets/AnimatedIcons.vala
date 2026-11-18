/**
 * SPDX-FileCopyrightText: Copyright © 2020-2024 Louis Brauer <louis@brauer.family>
 * SPDX-FileCopyrightText: Copyright © 2024 technosf <https://github.com/technosf>
 * SPDX-FileCopyrightText: Copyright © 2026 technosf <https://github.com/technosf>
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * @file AnimatedIcons.vala
 *
 * @brief The tuner and jukebox artwork with a moving needle, knob and record. Ported from the GTK3 app: the
 * drawing is the same, only the widget's draw hook differs.
 */

namespace TunerGtk4
{
    /** @brief Default size of the header bar's tuner and jukebox icons: GTK3's IconSize.DIALOG */
    public const int ICON_PX = 48;
}

/**
 * @class SvgLayers
 * @brief An SVG document drawn one layer at a time, using the current librsvg calls (2.52 or newer).
 *
 * The icons draw a document's layers (needle, knob, record) under their own Cairo transforms. `layer ()` draws an
 * element where it sits in the document, in the document's own units, with the caller's transform; the viewport is
 * the document's own size at the origin, so librsvg adds no scaling of its own.
 */
public class TunerGtk4.SvgLayers : GLib.Object
{
    public struct Size
    {
        public double width;
        public double height;
    }

    private Rsvg.Handle _handle;
    private Rsvg.Rectangle _viewport;
    private Size _size;


    /** @brief Loads the SVG; the size is its intrinsic size in pixels, or `fallback` when it has none. */
    public SvgLayers (uint8[] data, double fallback = 128.0) throws GLib.Error
    {
        _handle = new Rsvg.Handle.from_data (data);

        double w, h;
        if (!_handle.get_intrinsic_size_in_pixels (out w, out h) || w <= 0.0 || h <= 0.0)
        {
            w = fallback;
            h = fallback;
        }
        _size.width = w;
        _size.height = h;

        _viewport = Rsvg.Rectangle ();
        _viewport.x = 0.0;
        _viewport.y = 0.0;
        _viewport.width = w;
        _viewport.height = h;
    } // SvgLayers


    public Size size ()
    {
        return _size;
    } // size


    /** @brief Draws one element (by id, without the #) where it sits in the document. */
    public bool layer (Cairo.Context cr, string id)
    {
        try
        {
            return _handle.render_layer (cr, "#" + id, _viewport);
        }
        catch (GLib.Error e)
        {
            warning ("Cannot draw layer %s: %s", id, e.message);
            return false;
        }
    } // layer


    /** @brief Draws the whole document at its natural size. */
    public bool whole (Cairo.Context cr)
    {
        try
        {
            return _handle.render_document (cr, _viewport);
        }
        catch (GLib.Error e)
        {
            warning ("Cannot draw the document: %s", e.message);
            return false;
        }
    } // whole
} // SvgLayers


public class TunerGtk4.AnimatedTunerIcon : Gtk.DrawingArea
{
    // SVG coordinate system is 128x128. These match the artwork geometry.
    private const double DIAL_OVERSHOOT = 5.0;
    private const double DIAL_LEFT_X = 23.0;
    private const double DIAL_RIGHT_X = 105.0;
    private const double NEEDLE_BASE_X = 54.0; // original needle x in SVG
    private const double NEEDLE_MIN_X = DIAL_LEFT_X - DIAL_OVERSHOOT;
    private const double NEEDLE_MAX_X = DIAL_RIGHT_X + DIAL_OVERSHOOT;
    // Layer_2 is translated by (0, -8) in the SVG, so the root-space center
    // is original center + LAYER_OFFSET_Y.
    private const double LAYER_OFFSET_Y = -8.0;
    private const double KNOB_CENTER_X = 64.5;
    private const double KNOB_CENTER_Y = 98.5 + LAYER_OFFSET_Y;
    private const double KNOB_TURNS = 3.0; // full needle sweep = 3 full knob rotations
    private const int ANIMATION_DURATION_MS = 2000; // full sweep duration

    private SvgLayers _handle;
    private uint _animation_tick_id = 0;
    private int64 _animation_start_us = 0;
    private double _needle_offset = 0.0;
    private double _knob_angle = 0.0;
    private double _start_needle_offset = 0.0;
    private double _start_knob_angle = 0.0;
    private double _target_needle_offset = 0.0;
    private double _target_knob_angle = 0.0;
    private double _target_norm = 0.5;
    private bool _return_on_complete = false;
    private double _return_norm = 0.5;

    /**
     * @brief Create an animated tuner icon with an optional fixed size.
     * @param width Optional pixel width (defaults to IconSize.DIALOG).
     * @param height Optional pixel height (defaults to IconSize.DIALOG).
     */
    public AnimatedTunerIcon (int? width = null, int? height = null)
    {
        halign = Gtk.Align.CENTER;
        valign = Gtk.Align.CENTER;

        set_size_request (width ?? ICON_PX, height ?? ICON_PX);

        // Load the SVG icon from GResource so we can render individual elements.
        try {
            var bytes = GLib.resources_lookup_data ("/io/github/tuner_labs/tuner/gtk4/icons/tuner:tuner-on.svg", GLib.ResourceLookupFlags.NONE);
            _handle = new SvgLayers (bytes.get_data ());
        } catch (GLib.Error e) {
            warning ("Failed to load tuner SVG for animation: %s", e.message);
        }

        // Drive drawing via the widget's draw signal.
        // Initialize to the SVG's original needle position.
        _needle_offset = 0.0;
        _knob_angle = 0.0;

        set_draw_func ((area, cr, width, height) => { paint (cr, width, height); });

    }

    /**
     * @brief Animate the tuner to a normalized dial position.
     * @param normalized_position 0.0 = dial-left, 1.0 = dial-right.
     */
    public void animate_to (double normalized_position)
    {
        start_animation (normalized_position, false, 0.5);
    }

    /**
     * @brief Animate out-and-back around a center position.
     * @param center_norm Center position to return to.
     * @param delta_norm Offset to move away before returning.
     */
    public void animate_pulse (double center_norm, double delta_norm)
    {
        double target = center_norm + delta_norm;
        start_animation (target, true, center_norm);
    }

    /**
     * @brief Internal animation setup shared by animate_to and animate_pulse.
     */
    private void start_animation (double normalized_position, bool return_on_complete, double return_norm)
    {
        // Clamp the target and store optional return target.
        _target_norm = Math.fmax (0.0, Math.fmin (1.0, normalized_position));
        _return_on_complete = return_on_complete;
        _return_norm = Math.fmax (0.0, Math.fmin (1.0, return_norm));

        // Map normalized value to needle offset and knob rotation.
        _target_needle_offset = (NEEDLE_MIN_X + _target_norm * (NEEDLE_MAX_X - NEEDLE_MIN_X)) - NEEDLE_BASE_X;
        _target_knob_angle = (_target_norm - 0.5) * 360.0 * KNOB_TURNS;

        // Capture the current state as the animation start.
        _start_needle_offset = _needle_offset;
        _start_knob_angle = _knob_angle;
        _animation_start_us = 0;

        // Use frame clock ticks to keep motion smooth and synced to refresh.
        if (_animation_tick_id == 0)
            _animation_tick_id = add_tick_callback (on_animation_tick);
    }

    /**
     * @brief Frame-clock tick callback. Updates interpolation and triggers redraw.
     * @return false when the animation completes (stops tick), true to continue.
     */
    private bool on_animation_tick (Gtk.Widget widget, Gdk.FrameClock frame_clock)
    {
        int64 frame_us = frame_clock.get_frame_time ();
        if (_animation_start_us == 0)
            _animation_start_us = frame_us;

        double elapsed_ms = (frame_us - _animation_start_us) / 1000.0;
        double progress = elapsed_ms / ANIMATION_DURATION_MS;

        if (progress >= 1.0) {
            _needle_offset = _target_needle_offset;
            _knob_angle = _target_knob_angle;
            queue_draw ();

            if (_return_on_complete) {
                // Start the return leg without stopping the tick.
                _return_on_complete = false;
                start_animation (_return_norm, false, _return_norm);
                return true;
            }

            _animation_tick_id = 0;
            _animation_start_us = 0;
            return false;
        }

        // Ease-out for a smoother glide instead of a linear jump.
        double eased = 1.0 - Math.pow (1.0 - progress, 3.0);
        _needle_offset = _start_needle_offset + ((_target_needle_offset - _start_needle_offset) * eased);
        _knob_angle = _start_knob_angle + ((_target_knob_angle - _start_knob_angle) * eased);
        queue_draw ();
        return true;
    }
    /**
     * @brief Draw handler. Renders SVG layers with animation transforms.
     */
    private void paint (Cairo.Context cr, int width, int height)
    {
        if (_handle == null) {
            return;
        }

        var dims = _handle.size ();

        if (dims.width == 0 || dims.height == 0 || width == 0 || height == 0) {
            return;
        }

        // Keep uniform scaling so rotations don't skew when the widget isn't square.
        double scale = Math.fmin ((double) width / (double) dims.width,
            (double) height / (double) dims.height);
        double tx = ((double) width - ((double) dims.width * scale)) / 2.0;
        double ty = ((double) height - ((double) dims.height * scale)) / 2.0;

        cr.save ();
        cr.translate (tx, ty);
        cr.scale (scale, scale);

        // Draw base first, then move the needle horizontally, then rotate knob indicator.
        render_static (cr, "tuner-base");
        render_translated (cr, "needle-position", _needle_offset, 0.0);
        render_rotated (cr, "knob-rotation", _knob_angle);

        cr.restore ();
        return;
    }

    /**
     * @brief Render an SVG element by id without transforms.
     */
    private void render_static (Cairo.Context cr, string id)
    {
        _handle.layer (cr, id);
    }

    /**
     * @brief Render an SVG element by id with a translation.
     * @param dx X translation in SVG units.
     * @param dy Y translation in SVG units.
     */
    private void render_translated (Cairo.Context cr, string id, double dx, double dy)
    {
        cr.save ();
        cr.translate (dx, dy);
        _handle.layer (cr, id);
        cr.restore ();
    }

    /**
     * @brief Render an SVG element by id with rotation around the knob center.
     * @param angle_deg Rotation angle in degrees.
     */
    private void render_rotated (Cairo.Context cr, string id, double angle_deg)
    {
        cr.save ();
        // 1) Move the origin to the knob center so rotation pivots around it.
        cr.translate (KNOB_CENTER_X, KNOB_CENTER_Y);
        // 2) Rotate the coordinate system by the desired angle (degrees -> radians).
        cr.rotate (angle_deg * Math.PI / 180.0);
        // 3) Move the origin back so SVG element coordinates remain in their original space.
        cr.translate (-KNOB_CENTER_X, -KNOB_CENTER_Y);

        // The indicator path is authored in absolute SVG coordinates. After the
        // translate/rotate/translate, any point (x, y) is rotated around
        // (KNOB_CENTER_X, KNOB_CENTER_Y), so its locus is a circle centered there.
        _handle.layer (cr, id);

        cr.restore ();
    }
}


/**
 * @brief Animated jukebox icon that moves the tonearm and spins the record.
 *
 * Renders the jukebox SVG from resources, then animates sub-layers:
 * - `tuner-base`: static cabinet art
 * - `window`: static upper glass
 * - `needle-position`: translated across the record
 * - `record-position`: stationary clipped record for static icon rendering
 * - `knob-rotation`: record art rotated inside a Cairo clip
 */
public class TunerGtk4.AnimatedJukeboxIcon : Gtk.DrawingArea
{
    // SVG coordinate system is 128x128. These match the jukebox artwork geometry.
    private const double NEEDLE_BASE_X = 0.0;
    private const double NEEDLE_MIN_X = -4.0;
    private const double NEEDLE_MAX_X = 18.0;
    private const double RECORD_SOURCE_SIZE = 800.0;
    private const double RECORD_SOURCE_CENTER = RECORD_SOURCE_SIZE / 2.0;
    private const double RECORD_CLIP_X = 27.594669;
    private const double RECORD_CLIP_WIDTH = 73.808601;
    private const double RECORD_CLIP_PADDING = 1.0;
    private const double RECORD_VISIBLE_TOP_Y = 13.1;
    private const double RECORD_VISIBLE_BOTTOM_Y = 53.5;
    private const double RECORD_SCALE = RECORD_CLIP_WIDTH / RECORD_SOURCE_SIZE;
    private const double RECORD_POSITION_X = RECORD_CLIP_X;
    private const double RECORD_POSITION_Y = RECORD_VISIBLE_BOTTOM_Y - (RECORD_SOURCE_CENTER * RECORD_SCALE);
    private const double RECORD_CENTER_X = RECORD_POSITION_X + (RECORD_SOURCE_CENTER * RECORD_SCALE);
    private const double RECORD_CENTER_Y = RECORD_POSITION_Y + (RECORD_SOURCE_CENTER * RECORD_SCALE);
    private const double RECORD_TURNS = 4.0;
    private const int ANIMATION_DURATION_MS = 2000;

    private SvgLayers _handle;
    private SvgLayers _record_handle;
    private uint _animation_tick_id = 0;
    private int64 _animation_start_us = 0;
    private double _needle_offset = 0.0;
    private double _record_angle = 0.0;
    private double _start_needle_offset = 0.0;
    private double _start_record_angle = 0.0;
    private double _target_needle_offset = 0.0;
    private double _target_record_angle = 0.0;

    /**
     * @brief Create an animated jukebox icon with an optional fixed size.
     * @param width Optional pixel width (defaults to IconSize.DIALOG).
     * @param height Optional pixel height (defaults to IconSize.DIALOG).
     */
    public AnimatedJukeboxIcon (int? width = null, int? height = null)
    {
        halign = Gtk.Align.CENTER;
        valign = Gtk.Align.CENTER;

        set_size_request (width ?? ICON_PX, height ?? ICON_PX);

        try
        {
            var bytes = GLib.resources_lookup_data ("/io/github/tuner_labs/tuner/gtk4/icons/tuner:background-jukebox.svg", GLib.ResourceLookupFlags.NONE);
            _handle = new SvgLayers (bytes.get_data ());
            var record_bytes = GLib.resources_lookup_data ("/io/github/tuner_labs/tuner/gtk4/icons/tuner:vinyl-record.svg", GLib.ResourceLookupFlags.NONE);
            _record_handle = new SvgLayers (record_bytes.get_data ());
        }
        catch (GLib.Error e)
        {
            warning ("Failed to load jukebox SVG for animation: %s", e.message);
        }

        set_draw_func ((area, cr, width, height) => { paint (cr, width, height); });

    } // AnimatedJukeboxIcon


    /**
     * @brief Animate the jukebox to a normalized station position.
     * @param normalized_position 0.0 = tonearm-left, 1.0 = tonearm-right.
     */
    public void animate_to (double normalized_position)
    {
        // Stop old animation immediately
        if (_animation_tick_id != 0) 
        {
            remove_tick_callback(_animation_tick_id);
            _animation_tick_id = 0;
            _animation_start_us = 0;
        }

        double target_norm = Math.fmax (0.0, Math.fmin (1.0, normalized_position));

        _target_needle_offset = (NEEDLE_MIN_X + target_norm * (NEEDLE_MAX_X - NEEDLE_MIN_X)) - NEEDLE_BASE_X;
        _target_record_angle = _record_angle + (293.0 * RECORD_TURNS) + (target_norm * 360.0);
        
        _start_needle_offset = _needle_offset;
        _start_record_angle = _record_angle;
        _animation_start_us = 0;

        if (_animation_tick_id == 0)
            _animation_tick_id = add_tick_callback (on_animation_tick);
    } // animate_to


    /**
     * @brief Frame-clock tick callback. Updates interpolation and triggers redraw.
     * @return false when the animation completes (stops tick), true to continue.
     */
    private bool on_animation_tick (Gtk.Widget widget, Gdk.FrameClock frame_clock)
    {
        int64 frame_us = frame_clock.get_frame_time ();
        if (_animation_start_us == 0)
            _animation_start_us = frame_us;

        double elapsed_ms = (frame_us - _animation_start_us) / 1000.0;
        double progress = elapsed_ms / ANIMATION_DURATION_MS;

        if (progress >= 1.0)
        {
            _needle_offset = _target_needle_offset;
            _record_angle = _target_record_angle;
            queue_draw ();

            _animation_tick_id = 0;
            _animation_start_us = 0;
            return false;
        }

        double eased = 1.0 - Math.pow (1.0 - progress, 3.0);
        _needle_offset = _start_needle_offset + ((_target_needle_offset - _start_needle_offset) * eased);
        _record_angle = _start_record_angle + ((_target_record_angle - _start_record_angle) * eased);
        queue_draw ();
        return true;
    } // on_animation_tick


    /**
     * @brief Draw handler. Renders SVG layers with animation transforms.
     */
    private void paint (Cairo.Context cr, int width, int height)
    {
        if (_handle == null || _record_handle == null)
            return;

        var dims = _handle.size ();

        if (dims.width == 0 || dims.height == 0 || width == 0 || height == 0)
            return;

        double scale = Math.fmin ((double) width / (double) dims.width,
            (double) height / (double) dims.height);
        double tx = ((double) width - ((double) dims.width * scale)) / 2.0;
        double ty = ((double) height - ((double) dims.height * scale)) / 2.0;

        cr.save ();
        cr.translate (tx, ty);
        cr.scale (scale, scale);

        render_static (cr, "tuner-base");
        render_static (cr, "window");
        render_clipped_rotated_record (cr, _record_angle);
        render_translated (cr, "needle-position", _needle_offset, 0.0);

        cr.restore ();
        return;
    } // on_draw


    /**
     * @brief Render an SVG element by id without transforms.
     */
    private void render_static (Cairo.Context cr, string id)
    {
        _handle.layer (cr, id);
    } // render_static


    /**
     * @brief Render an SVG element by id with a translation.
     * @param dx X translation in SVG units.
     * @param dy Y translation in SVG units.
     */
    private void render_translated (Cairo.Context cr, string id, double dx, double dy)
    {
        cr.save ();
        cr.translate (dx, dy);
        _handle.layer (cr, id);
        cr.restore ();
    } // render_translated


    /**
     * @brief Render the record rotation inside the stationary SVG clip path.
     * @param angle_deg Rotation angle in degrees.
     */
    private void render_clipped_rotated_record (Cairo.Context cr, double angle_deg)
    {
        cr.save ();
        double clip_x = RECORD_CLIP_X - RECORD_CLIP_PADDING;
        double clip_y = RECORD_VISIBLE_TOP_Y;
        double clip_width = RECORD_CLIP_WIDTH + (RECORD_CLIP_PADDING * 2.0);
        double clip_height = RECORD_CENTER_Y - clip_y;

        cr.rectangle (clip_x, clip_y, clip_width, clip_height);
        cr.clip ();

        cr.translate (RECORD_POSITION_X, RECORD_POSITION_Y);
        cr.scale (RECORD_SCALE, RECORD_SCALE);
        cr.translate (RECORD_SOURCE_CENTER, RECORD_SOURCE_CENTER);
        cr.rotate (angle_deg * Math.PI / 180.0);
        cr.translate (-RECORD_SOURCE_CENTER, -RECORD_SOURCE_CENTER);

        _record_handle.whole (cr);
        cr.restore ();
    } // render_clipped_rotated_record
} // AnimatedJukeboxIcon


/** 
 * TunerStatus widget for displaying tuner on-line status and data provider information.
 */


/**
 * @class Backdrop
 * @brief The large faint tuner (or jukebox) behind the station list. It tunes to each station that plays.
 */
public class TunerGtk4.Backdrop : Gtk.Box
{
    private const double OPACITY = 0.15;
    private const int TRANSITION_TIME_MS = 1500;

    private AnimatedTunerIcon _tuner_icon = new AnimatedTunerIcon (256, 256);
    private AnimatedJukeboxIcon _jukebox_icon = new AnimatedJukeboxIcon (256, 256);

    // The tuner or the jukebox shows; Gtk.Stack cross-fades between them, and copes with being switched mid-fade
    private Gtk.Stack _icons = new Gtk.Stack ();


    public Backdrop ()
    {
        Object (orientation: Gtk.Orientation.HORIZONTAL, spacing: 0);

        _icons.transition_type = Gtk.StackTransitionType.CROSSFADE;
        _icons.transition_duration = TRANSITION_TIME_MS;
        _icons.add_named (_tuner_icon, "tuner");
        _icons.add_named (_jukebox_icon, "jukebox");
        _icons.visible_child = _tuner_icon;
        _icons.opacity = OPACITY;
        _icons.can_target = false;
        append (_icons);

        halign = Gtk.Align.CENTER;
        valign = Gtk.Align.CENTER;
        can_target = false;
    } // Backdrop


    /** Shows the jukebox icon (shuffle mode) or the tuner icon. */
    public void show_jukebox (bool jukebox)
    {
        _icons.visible_child_name = jukebox ? "jukebox" : "tuner";
    } // show_jukebox


    public void tune_to (Tuner.Models.Station station)
    {
        string key = station.stationuuid != "" ? station.stationuuid : station.name;
        double norm = (double) (GLib.str_hash (key) % 1000) / 999.0;
        _tuner_icon.animate_to (norm);
        _jukebox_icon.animate_to (norm);
    } // tune_to
} // Backdrop


/**
 * @class TunerStatus
 * @brief The tuner icon at the left of the header bar: lit and tuned when online, dark when offline.
 */
public class TunerGtk4.TunerStatus : Gtk.Box
{
    private const double ONLINE_PULSE_DELTA = 0.12;
    private const int LIFT_PX = 5;      // Bottom margin, as in GTK3, so the icon sits centred in the bar

    private AnimatedTunerIcon _tuner_on = new AnimatedTunerIcon ();
    private double _last_norm = 0.5;


    public TunerStatus ()
    {
        Object (orientation: Gtk.Orientation.HORIZONTAL, spacing: 0);     // GtkOverlay is final in GTK4: hold one
        var off = new Gtk.Image.from_icon_name ("tuner:tuner-off");
        off.pixel_size = ICON_PX;
        var overlay = new Gtk.Overlay ();
        overlay.child = off;
        overlay.add_overlay (_tuner_on);
        append (overlay);
        valign = Gtk.Align.CENTER;
        margin_start = 5;
        margin_end = 5;
        margin_bottom = LIFT_PX;
        tooltip_text = _("Data Provider");
    } // TunerStatus


    public void tune_to (Tuner.Models.Station station)
    {
        string key = station.stationuuid != "" ? station.stationuuid : station.name;
        _last_norm = (double) (GLib.str_hash (key) % 1000) / 999.0;
        _tuner_on.animate_to (_last_norm);
    } // tune_to


    public bool online
    {
        set
        {
            _tuner_on.opacity = value ? 1.0 : 0.0;
            if (value)
                _tuner_on.animate_pulse (_last_norm, ONLINE_PULSE_DELTA);
        }
    } // online
} // TunerStatus
