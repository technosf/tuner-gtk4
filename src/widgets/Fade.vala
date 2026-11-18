/**
 * SPDX-FileCopyrightText: Copyright © 2026 technosf <https://github.com/technosf>
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * @file Fade.vala
 *
 * @brief Fades a widget's opacity, from the frame clock.
 */

namespace TunerGtk4
{
    /** @brief Called when a fade has reached its target */
    public delegate void FadeDone ();

    /**
     * @class Fade
     * @brief Eases a widget's opacity to a target (smoothstep, as the GTK3 app does), driven by the frame clock.
     *
     * Starting a fade on a widget replaces any fade already running on it, carrying on from the opacity it has reached.
     * A replaced fade does not call its done callback.
     */
    public class Fade : GLib.Object
    {
        private const string KEY = "tuner-fade-tick";

        /**
         * @param widget The widget to fade
         * @param target The opacity to reach, 0.0 to 1.0
         * @param duration_ms How long the fade takes
         * @param done Called once the target is reached
         * @param delay_ms Wait this long, at the current opacity, before the fade starts
         */
        public static void to (Gtk.Widget widget, double target, uint duration_ms, owned FadeDone? done = null,
                               uint delay_ms = 0)
        {
            cancel (widget);

            double from = widget.opacity;
            if (from == target || duration_ms == 0)
            {
                widget.opacity = target;
                if (done != null)
                    done ();
                return;
            }

            int64 start = 0;
            uint id = widget.add_tick_callback ((w, clock) =>
            {
                int64 now = clock.get_frame_time ();
                if (start == 0)
                    start = now;

                double t = (((double) (now - start) / 1000.0) - (double) delay_ms) / (double) duration_ms;
                if (t <= 0.0)
                    return Source.CONTINUE;
                if (t >= 1.0)
                {
                    w.opacity = target;
                    w.set_data<uint> (KEY, 0);
                    if (done != null)
                        done ();
                    return Source.REMOVE;
                }

                w.opacity = from + (target - from) * (t * t * (3.0 - 2.0 * t));
                return Source.CONTINUE;
            });
            widget.set_data<uint> (KEY, id);
        } // to


        /** @brief Stops a fade running on the widget, leaving its opacity where it is */
        public static void cancel (Gtk.Widget widget)
        {
            uint id = widget.get_data<uint> (KEY);
            if (id != 0)
                widget.remove_tick_callback (id);
            widget.set_data<uint> (KEY, 0);
        } // cancel


        public const uint WINDOW_FADE_MS = 400;      // A window fades in over this, as the station list does
        public const uint WINDOW_SETTLE_MS = 0;      // after this wait
        public const double WINDOW_START_OPACITY = 0.01;   // Not 0: GTK does not paint a fully transparent window, so the compositor would show stale pixels

        /**
         * @brief Makes a window fade in when it first appears, rather than popping up. Call from its constructor.
         */
        public static void window_in (Gtk.Window window)
        {
            window.opacity = WINDOW_START_OPACITY;
            ulong shown = 0;
            shown = window.map.connect (() =>
            {
                window.disconnect (shown);
                to (window, 1.0, WINDOW_FADE_MS, null, WINDOW_SETTLE_MS);
            });
        } // window_in


        /** @brief Closes a popover that has been given a FadingPopover with a fade; any other popover just closes. */
        public static void close_popover (Gtk.Popover popover)
        {
            var fading = popover.get_data<FadingPopover> ("fading-popover");
            if (fading != null)
                fading.close ();
            else
                popover.popdown ();
        } // close_popover

    } // Fade

    /**
     * @class FadingPopover
     * @brief Gives a popover the same fade in and out as the app's windows and lists.
     *
     * The popover fades in as it opens. Autohide is replaced: a click outside it, or Escape, closes it with a fade,
     * and so does `Fade.close_popover ()`. (A click that closes it is not passed on to what is under the pointer.)
     */
    public class FadingPopover : GLib.Object
    {
        public const uint IN_MS = 400;     // The same as a window
        public const uint OUT_MS = 200;    // and as a list fading out

        private Gtk.Popover _popover;
        private bool _closing = false;
        private Gtk.GestureClick? _click = null;
        private Gtk.EventControllerKey? _keys = null;
        private Gtk.Widget? _root = null;
        private ulong _active_handler = 0;
        private uint _inactive_id = 0;


        public FadingPopover (Gtk.Popover popover)
        {
            _popover = popover;
            _popover.autohide = false;
            _popover.set_data<FadingPopover> ("fading-popover", this);

            _popover.map.connect (() =>
            {
                _closing = false;
                _popover.opacity = Fade.WINDOW_START_OPACITY;
                Fade.to (_popover, 1.0, IN_MS);
                listen ();
            });
            _popover.unmap.connect (() =>
            {
                unlisten ();
                Fade.cancel (_popover);
                _popover.opacity = 1.0;
                _closing = false;
            });
        } // FadingPopover


        /** Fades the popover out and closes it. */
        public void close ()
        {
            if (_closing || !_popover.visible)
                return;
            _closing = true;
            Fade.to (_popover, 0.0, OUT_MS, () =>
            {
                _closing = false;
                _popover.popdown ();
            });
        } // close


        /** Watches the window the popover belongs to for a click outside it, or Escape. */
        private void listen ()
        {
            var parent = _popover.get_parent ();
            _root = parent != null ? parent.get_root () as Gtk.Widget : null;
            if (_root == null)
                return;

            // The popover is its own surface, so a click on the window is a click outside the popover
            _click = new Gtk.GestureClick ();
            _click.propagation_phase = Gtk.PropagationPhase.CAPTURE;
            _click.pressed.connect ((n, x, y) =>
            {
                _click.set_state (Gtk.EventSequenceState.CLAIMED);
                close ();
            });
            _root.add_controller (_click);

            _keys = new Gtk.EventControllerKey ();
            _keys.propagation_phase = Gtk.PropagationPhase.CAPTURE;
            _keys.key_pressed.connect ((keyval, keycode, state) =>
            {
                if (keyval != Gdk.Key.Escape)
                    return false;
                close ();
                return true;
            });
            _root.add_controller (_keys);

            // Autohide is off, so the popover has to be closed when the window is left: another window, or another desktop
            var window = _root as Gtk.Window;
            if (window != null)
            {
                _active_handler = window.notify["is-active"].connect (() =>
                {
                    if (_inactive_id != 0)
                    {
                        Source.remove (_inactive_id);
                        _inactive_id = 0;
                    }
                    if (window.is_active)
                        return;
                    // A moment's grace: a menu opened from the popover can pass focus about briefly
                    _inactive_id = Timeout.add (150, () =>
                    {
                        _inactive_id = 0;
                        if (!window.is_active)
                            close ();
                        return Source.REMOVE;
                    });
                });
            }
        } // listen


        private void unlisten ()
        {
            if (_inactive_id != 0)
            {
                Source.remove (_inactive_id);
                _inactive_id = 0;
            }
            if (_root != null)
            {
                if (_active_handler != 0)
                    _root.disconnect (_active_handler);
                _active_handler = 0;
                if (_click != null)
                    _root.remove_controller (_click);
                if (_keys != null)
                    _root.remove_controller (_keys);
            }
            _click = null;
            _keys = null;
            _root = null;
        } // unlisten
    } // FadingPopover
}
