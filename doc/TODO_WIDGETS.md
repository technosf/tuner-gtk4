# GTK4 widget opportunities

Plain GTK4 (4.10+) widgets that could simplify the presentation layer or add polish. No libadwaita.
Tick each off as it is done; build, run and check against the GTK3 look before moving on.

## Simplifications (do these in order)

- [x] 1. `Gtk.Stack` with `CROSSFADE` replaces the hand-written `fade_to` (Explore tags) and the backdrop mix animation. Done, unbuilt. Content-list swaps are left for item 2.
- [x] 2. `Gtk.GridView` with a factory for the station list (virtualised). Done, unbuilt: `Gio.ListStore` + `Gtk.NoSelection`, `StationRow`/`SearchRow` recycled through bind/unbind, saved searches use a second factory, activation is `GridView.activate` (double click). Differences to check: row/column spacing is now padding in CSS (`.station-list > child`), and "Load more" sits under the scrolling list instead of at the end of it. History tiles are not converted (a small fixed set; left as is). The pager (`StationListBoxPager`) is core code and is untouched.
- [ ] 3. `Gtk.FilterListModel` + `Gtk.StringFilter` + `Gtk.SortListModel` for Starred: filter-as-you-type and reorder become model operations.
- [ ] 4. `Gtk.TreeListModel` + `Gtk.TreeExpander` for the sidebar (replaces `side_section`; saved searches could become children of Library).
- [ ] 5. `Gtk.PopoverMenu` from a `Gio.MenuModel` + `Gio.SimpleAction`s for the station context menu and preferences.
- [ ] 6. `Gtk.WindowHandle` for dragging the metadata image popup (replaces `Gdk.Toplevel.begin_move` code).
- [ ] 7. `Gtk.EditableLabel` for inline station notes instead of a separate note window.
- [ ] 8. `Gtk.Inscription` (4.8) instead of `Gtk.Label` in list rows.
- [ ] 9. `Gtk.CenterBox` for the header, to centre now-playing without spacers.
- [ ] 10. `Gtk.Switch` for preference toggles (optional; the tick boxes match GTK3).
- [ ] 11. `Gtk.AlertDialog` for confirmations.

## Flourishes

- [ ] A. Level meter from the core's `last_rms_db`: `Gtk.LevelBar`, or a small `Gtk.DrawingArea` equaliser.
- [ ] B. Spinning vinyl record beside the station art while playing (`Gtk.Snapshot` rotation; stops when paused).
- [ ] C. `Gtk.Picture` (`content_fit = COVER`) for station art, with a CSS `filter: blur()` copy as a backdrop.
- [ ] D. CSS transitions / `@keyframes`: row hover and selection, a pulse on the playing row.
- [ ] E. `Gtk.Revealer` slide on rows as they load or are removed (e.g. unstarring in Starred).
- [ ] F. `Gtk.Scale` marks on the volume slider.
- [ ] G. `Gtk.ShortcutsWindow` listing the keyboard shortcuts.

## Header bar animation (centre block and track line)

Done (unbuilt): the centre block has a fixed height, so collapsing it no longer changes the bar's height; the width glide
and the favicon fade use the frame clock; the next favicon is decoded off the main thread while the old station collapses,
and one that arrives late fades in. Check by eye, and with `GTK_DEBUG=interactive` (inspector, Graphics, frame clock).

Later, if it is still not as smooth as GTK3:

- [ ] H1. Animate by transform, not by layout: a `Gtk.Widget` subclass that overrides `snapshot` to clip, translate and fade the
  child. The size is fixed from the start, so nothing relayouts during the animation. Replaces the `Gtk.Revealer` in `NowPlaying`
  and the `set_size_request` glide in `SlidingLabel` (the icon slides from its old centred position to the new one).
- [ ] H2. CSS transitions: toggle a class such as `.collapsed` and let GTK run `transition: opacity ..., transform ... ease-in-out` on
  the frame clock, instead of the hand-written tick code in `Fade` for these widgets. Try on one widget first (the favicon).
- [ ] H3. Drive the whole station change from one timeline (one frame-clock callback with named phases) instead of the chain of
  `Timeout`s (667 ms, 1200 ms, 1.1x, 1.5x), so the steps cannot drift apart on a busy frame.

## Notes

- Faithfulness to the GTK3 look and behaviour comes first; a widget swap must not change what the user sees unless listed here.
- Logic stays in core; these are presentation-only changes.
