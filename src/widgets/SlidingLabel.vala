/**
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * @file SlidingLabel.vala
 */

/**
 * @class SlidingLabel
 * @brief The track line under the station name in the header bar: a port of the GTK3 CyclingRevealLabel.
 *
 * A change of text fades the old text out, clears it, and fades the new text in (the timings are the GTK3 RevealLabel's),
 * while the width glides to fit, so the centred icon slides smoothly. A longer text widens at once; a shorter one only
 * narrows when `dynamic_shrink` is on, or when new metadata has arrived (so the icon does not bounce between texts of
 * one payload).
 *
 * While `show_metadata` is on, `cycle ()` shows the stream's sublabels (genre, audio info, location) in turn, each at
 * its own prime-numbered period in seconds.
 */
public class TunerGtk4.SlidingLabel : Gtk.Box      // GtkLabel is final in GTK4: hold one
{
    private const int PADDING_PX = 24;
    private const int GLIDE_MS = 500;            // The width glide, so the icon takes half a second to move from the centre to its new place
    private const uint TEXT_FADE_MS = 1200;       // The GTK3 RevealLabel's fade, each way
    private const int SUBTITLE_MIN_DISPLAY_SECONDS = 3;
    private const uint OPEN_MS = 250;             // The line opening downwards

    public bool dynamic_shrink { get; set; default = false; }
    public bool show_metadata { get; set; default = false; }
    public int min_width { get; construct set; default = 100; }
    public int max_width { get; set; default = 320; }

    /** Cycle the sublabels fast (small primes) or slowly */
    public bool metadata_fast_cycle
    {
        get { return _fast; }
        set { _fast = value; }
    }

    /** The text shown; see the class description for how a change looks. */
    public string label
    {
        get { return _label.label; }
        set { set_text (value); }
    }

    private Gtk.Label _label = new Gtk.Label ("");
    private Gtk.Revealer _reveal = new Gtk.Revealer ();      // Opens the line vertically once the width has glided
    private bool _fast = true;
    private bool _metadata_changed = true;
    private bool _changing = false;
    private uint _change_id = 0;
    private string _next_text = "";
    private string? _pending_text = null;      // Asked for during a change; the latest wins
    private string[] _sublabels = { "", "", "", "" };    // Positions 1 to 3 are used
    private uint _cycle_id = 0;
    private uint _display_seconds = 0;
    private int _count_down = 0;
    private uint _last_position = 99;
    private uint[] _phases_fast = { 5, 11, 17, 19, 23 };    // Primes, so everyone gets a chance
    private uint[] _phases_slow = { 23, 37, 43, 47, 53 };

    private int _current = 0;
    private int _from = 0;
    private int _to = 0;
    private int64 _start_us = 0;
    private int64 _duration_us = 0;
    private uint _tick_id = 0;


    public SlidingLabel (int min_width)
    {
        Object (orientation: Gtk.Orientation.HORIZONTAL, spacing: 0, min_width: min_width);
        _label.xalign = 0.5f;
        _label.justify = Gtk.Justification.CENTER;
        _label.ellipsize = Pango.EllipsizeMode.END;
        _label.max_width_chars = 1;      // Its natural width is one character: the box is as wide as the glide says, not as the text is,
                                         // or the icon would jump the moment a longer text is set
        _label.hexpand = true;
        _label.add_css_class ("track-info");
        halign = Gtk.Align.CENTER;
        hexpand = false;
        _current = min_width;
        _to = min_width;
        set_size_request (min_width, -1);
        _reveal.transition_type = Gtk.RevealerTransitionType.SLIDE_DOWN;     // No empty line until there is a track
        _reveal.transition_duration = OPEN_MS;
        _reveal.reveal_child = false;
        _reveal.child = _label;
        _reveal.hexpand = true;                   // Fills the box, so the text stays centred in it and grows outwards from the centre
        _reveal.halign = Gtk.Align.FILL;
        append (_reveal);

        notify["max-width"].connect (() => { glide_to (target_for (_label.label)); });
    } // SlidingLabel


    /** Marks that a new metadata payload has been applied. */
    public void notify_metadata_changed ()
    {
        _metadata_changed = true;
    } // notify_metadata_changed


    /** Sets a sublabel to cycle to: position 1 to 3; empty text removes it. Two parts are joined with " - ". */
    public void add_sublabel (int position, string? first, string? second = null)
    {
        if (position <= 0 || position >= _sublabels.length)
            return;
        if (first == null || first.strip () == "")
        {
            _sublabels[position] = "";
            return;
        }
        _sublabels[position] = (second == null || second.strip () == "") ? first.strip ()
                                                                         : first.strip () + " - " + second.strip ();
    } // add_sublabel


    /** Starts showing the sublabels in turn, a second at a time. */
    public void cycle ()
    {
        stop ();
        _cycle_id = Timeout.add_seconds_full (Priority.LOW, 1, () =>
        {
            _display_seconds++;
            if (_count_down-- > 0 || _changing)
                return Source.CONTINUE;
            _count_down = SUBTITLE_MIN_DISPLAY_SECONDS;

            if (!show_metadata)
                return Source.CONTINUE;
            var phases = _fast ? _phases_fast : _phases_slow;
            for (uint position = 1; position < _sublabels.length; position++)
            {
                if (_sublabels[position] != "" && _display_seconds % phases[position] == 0 && position != _last_position)
                {
                    set_text (_sublabels[position]);
                    _last_position = position;
                }
            }
            return Source.CONTINUE;
        });
    } // cycle


    /** Stops cycling. */
    public void stop ()
    {
        if (_cycle_id != 0)
        {
            Source.remove (_cycle_id);
            _cycle_id = 0;
        }
    } // stop


    /** Puts the width back to its minimum at once, with no glide: for when the line is out of sight. */
    public void reset_width ()
    {
        if (_tick_id != 0)
        {
            remove_tick_callback (_tick_id);
            _tick_id = 0;
        }
        _current = min_width;
        _from = min_width;
        _to = min_width;
        set_size_request (min_width, -1);
    } // reset_width


    /**
     * Clears the text at once, and the sublabels.
     *
     * @param glide_width the width glides back to its minimum; false leaves it as it is (see `reset_width`)
     */
    public void clear (bool glide_width = true)
    {
        stop ();
        _change_id++;
        _changing = false;
        _pending_text = null;
        _next_text = "";
        _last_position = 99;
        _sublabels = { "", "", "", "" };
        Fade.cancel (_label);
        _label.opacity = 1.0;
        _label.label = "";
        _reveal.transition_duration = 0;          // The block is faded out when this is called: close at once
        _reveal.reveal_child = false;
        _reveal.transition_duration = OPEN_MS;
        if (glide_width)
            glide_to (min_width);
    } // clear


    private void set_text (string text)
    {
        if (text == "")
        {
            clear ();
            return;
        }

        if (_changing)
        {
            _pending_text = (text == _next_text) ? null : text;
            return;
        }
        if (_label.label == text)
            return;

        // The width starts gliding now, while the old text fades out
        glide_to (target_for (text));
        _metadata_changed = false;
        start_change (text);
    } // set_text


    /** Fades the old text out, clears it, and fades the new text in. */
    private void start_change (string text)
    {
        _changing = true;
        _next_text = text;
        uint id = ++_change_id;

        if (_label.label == "")
        // Nothing on show to fade out
        {
            show_text (text);
            return;
        }

        Fade.to (_label, 0.0, TEXT_FADE_MS);
        Timeout.add (11 * TEXT_FADE_MS / 10, () =>
        {
            if (id == _change_id)
                _label.label = "";
            return Source.REMOVE;
        });
        Timeout.add (3 * TEXT_FADE_MS / 2, () =>
        {
            if (id == _change_id)
                show_text (_next_text);
            return Source.REMOVE;
        });
    } // start_change


    private void show_text (string text)
    {
        _label.label = text;
        _label.opacity = 0.0;
        uint id = _change_id;
        if (_reveal.reveal_child)
            Fade.to (_label, 1.0, TEXT_FADE_MS);
        else
        // First text of a station: the width glides from the centre, then the line opens downwards and the text fades in
        {
            Timeout.add ((uint) (_duration_us / 1000) + 30, () =>
            {
                if (id == _change_id)
                {
                    _reveal.reveal_child = true;
                    Fade.to (_label, 1.0, TEXT_FADE_MS);
                }
                return Source.REMOVE;
            });
        }
        _changing = false;

        var next = _pending_text;
        _pending_text = null;
        if (next != null && next != _label.label)
        // Asked for during the change: shown next
        {
            glide_to (target_for (next));
            _metadata_changed = false;
            start_change (next);
        }
    } // show_text


    private int target_for (string text)
    {
        if (text == null || text.strip ().length == 0)
            return min_width;

        var layout = _label.create_pango_layout (text);
        int w, h;
        layout.get_pixel_size (out w, out h);
        int target = int.min (int.max (w + PADDING_PX, min_width), int.max (max_width, min_width));

        if (!dynamic_shrink && !_metadata_changed && target < _current)
            target = _current;
        return target;
    } // target_for


    private void glide_to (int target)
    {
        if (target == _to && _tick_id == 0)
            return;

        _to = target;
        _from = _current;
        _start_us = 0;                         // Taken from the frame clock on the next tick, as Fade does
        _duration_us = (int64) GLIDE_MS * 1000;

        if (_tick_id == 0)
            _tick_id = add_tick_callback (on_tick);
    } // glide_to


    private bool on_tick (Gtk.Widget widget, Gdk.FrameClock clock)
    {
        int64 now = clock.get_frame_time ();
        if (_start_us == 0)
            _start_us = now;
        double progress = (double) (now - _start_us) / (double) _duration_us;
        progress = progress.clamp (0.0, 1.0);
        double eased = progress * progress * (3.0 - 2.0 * progress);     // smoothstep
        _current = (int) Math.round (_from + (_to - _from) * eased);
        set_size_request (_current, -1);

        if (progress >= 1.0)
        {
            _tick_id = 0;
            return Source.REMOVE;
        }
        return Source.CONTINUE;
    } // on_tick
} // SlidingLabel
