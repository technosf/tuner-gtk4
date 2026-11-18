# Tuner GTK4: what it uses, what is missing

This repository is an experiment (SEPARATION_PLAN.md in tuner-core, P6). It builds `tuner-core` as a meson subproject
and uses only the core's public API. It has its own application id, `io.github.tuner_labs.tuner.gtk4`, so its cache and
data folders (including `starred.json`) are separate from the GTK3 app's. It is not installed.

## Build and run

```bash
sudo apt install libgtk-4-dev          # GTK 4 development files (package name varies by distro)
ln -s ../../tuner-core subprojects/tuner-core        # once: the core checkout (see subprojects/README.md)
scripts/check-build.sh                 # configure and compile; the output is kept in build.log
scripts/run.sh                         # run it, with the core's settings schema from the build tree
```

The core's own tests run from the tuner-core checkout (`scripts/check-build.sh` there).

The settings schema is shared with the GTK3 app (`io.github.tuner_labs.tuner`), so volume and similar settings are
shared too. Close the GTK3 app first: both would claim the same GSettings state.

## What the prototype does

| Behaviour | Core API used |
|---|---|
| Start, wait for a directory server | `CoreSession`, `connection.start()`, `events.connection_state_changed_sig` |
| Load starred stations once the connection is ready | `directory.load()` |
| Trending, popular, search | `directory.load_trending_stations / load_popular_stations / load_search_stations`, `StationSet.next_page_async()` |
| Starred list | `directory.get_starred()` |
| Star or unstar | `Station.starred` (the directory controller saves it) |
| Play a station | `player.play_station()` |
| Play/pause | `player.play_pause()` |
| Now playing, track, state | `events.station_changed_sig`, `playback_metadata_changed_sig`, `player_state_changed_sig` |
| Volume | `player.volume`, `events.volume_changed_sig` |
| Quit | `core.quit_cleanly()` (the core asks the host to save view state and quit) |

## Gaps found so far (core and spec)

These are written from reading the core while building the prototype, before it has been compiled or run. Confirm
them when it runs.

Core:
- **Favicons.** The core now downloads and caches favicon bytes but offers no decoded image, so every frontend writes
  its own decode and fade (GTK3 has `ImageSupport`). The prototype shows none. A frontend needs the cache file path
  (`Favicon.favicon_image_file()`) and nothing else, which is the right shape, but it is undocumented.
- **Start-up (fixed in P7).** The window used to have to know that `directory.load()` waits for the connection, and the
  GTK3 `StartupCoordinator` was built by the application and played a GTK3 resource. Now `CoreSession.start_services()`
  (connection and MPRIS, early) and `CoreSession.start()` (load starred stations when ready, then the start-up flows)
  are the whole interface; the sound comes from `Host.startup_sound_uri()`. The prototype calls `start()` and gains
  start-on-starred and auto-play for free.
- **MPRIS (fixed in P7).** `start_services()` starts it, so no frontend has to remember.
- **Json warning filter (fixed in P7).** The `CoreSession` constructor installs it. The crash signal handlers in the GTK3
  `Main.vala` are still per frontend.
- **No `Host` for notifications or sleep inhibit.** The GTK3 app inhibits suspend while playing, using the
  application. The core should offer a "playing" state the host can map to an inhibitor.
- **Lists.** `StationSet` hands out a whole page as a `Gee.Set`. A GTK4 `ListView` wants a `Gio.ListModel`. The
  prototype uses a plain `ListBox` and appends rows, which is fine for 50 stations but not for scrolling a long result.
  This is decision D4 in the plan.
- **History was a frontend job (fixed in P7).** The GTK3 header bar appended each track to the history and told it when
  playback started and stopped, so a second frontend had no history. `HistoryRecorder` in the core does it now.
- **Starring is observable, but by hand.** Stations emit `station_star_changed_sig` and rows follow it, using weak
  references because stations outlive their rows. A frontend-neutral list model would remove that bookkeeping (D4).

Also in the prototype now: favicons (the cached file shown in a `Gtk.Image`; the core checks downloads through
`Favicon.image_check`), saved searches (save, run, remove), notes on starred stations, the session history with a live
refresh, and a heart button for the current track. Rows follow the station's star and favicon.

Also added: a preferences window (switches bound straight to `Tuner.Settings` properties: auto-play, start on starred,
inhibit sleep, play restart, do not vote, keep hearted tracks; plus the theme), suspend inhibit while playing
(`Gtk.Application.inhibit`, driven by `player_state_changed_sig` and `settings.inhibit_sleep`), the All Time hearted
view (`all_time.tracks`, `changed_sig`), starred reordering with up and down buttons (`directory.reorder_starred`), a
jukebox toggle (`jukebox.enable()/disable()`, `shuffle_state_changed_sig`) and window size memory
(`settings.window_width/height`, `remember_window_geometry`, called from `Host.save_view_state`).

Then also: browse by genre (`Tuner.Models.Genre.GENRES`, `directory.load_by_tag`) and country (`Countries.map`,
`directory.load_by_country`), random stations (`directory.load_random_stations`), Load more paging
(`StationSet.has_more()` and `next_page_async()`), a station info window (every station property the core exposes; a tag
button lists the stations with that tag; the stream address can be copied), the tape counter
(`events.playback_time_tick_sig`, `tape_counter.reset()`) and the player's error message on `STOPPED_ERROR`.

Then also: keyboard shortcuts (Ctrl+F search, Ctrl+P play/pause, Ctrl+Up and Ctrl+Down volume, Ctrl+R random, Ctrl+, preferences,
Ctrl+Q quit), the playing station's favicon in the now-playing bar (click it for the station's details), Copy and Clear
for the session history (`history.build_clipboard_text()`, `history.clear()`), and Remove and Clear all in the All time
view (`all_time.remove()`, `all_time.clear()`).

Then also: stations that failed to play this session carry a warning mark with the reason as its tooltip, and the mark
clears if the station recovers (`session.is_broken()`, `station_marked_broken_sig`, `station_recovered_sig`,
`session.lookup()`); the station window shows what happened to the station this session (plays, errors, the problem);
random tags to try as buttons (`directory.load_random_genres_async()`); and a filter for the starred list, which the
search box applies by name, tag or country while the starred list is on show. Reordering is offered only for the
whole list.

What this showed about the core:
- **Theme and sleep inhibit are frontend jobs again.** Both are a few lines in the host, driven by settings and the
  player state event, which is fine. A `playing` flag on the core would save every frontend from deciding what counts as
  playing (the GTK3 and GTK4 apps both treat PLAYING and BUFFERING as playing).
- **Settings are bindable.** Because `Settings` is a plain GObject, a frontend can `bind_property` its switches and needs
  no core code.
- **Window position is not usable on GTK4.** `remember_window_geometry` takes x and y; a GTK4 toplevel cannot report
  them, so the prototype passes 0 and only the size is kept.

Not in the prototype at all: language, share and QR code, accessibility, screenshots.

## Findings feed

P7 takes the confirmed items above into the core and the spec.

## Look and feel (matches the GTK3 app)

- Header bar: volume (popover), star, play/pause, heart on the left; the station and track playing in the middle
  (click for details); menu (Preferences), history and search toggle on the right.
- Sidebar: Selections (Discover, Trending, Popular, Jukebox), Library (Starred, Saved Searches, History, All Time),
  Explore (country, random tags), then Genres, Subgenres, Eras, Talk/News/Sport. Open/closed state is kept in the core
  setting `category-expanded-mask` (same bits as the GTK3 app).
- Content: a large title for what is on show, the stations in two columns (badge for codec and bitrate, country code),
  a search bar that opens from the header, the listening time in the footer.
- `src/Style.vala` holds the CSS, ported from the GTK3 `Tuner-system.css`.
- Not matched yet: the GTK3 custom sidebar icons (stock icons are used), the backdrop image, drag-and-drop reorder,
  the right-click station menu.

## Port fidelity (second pass)

- Fades: the playing display fades out, clears and fades in for each station (`change_station_display`); the list
  fades in when stations arrive; the backdrop and the tuner icon are the GTK3 animated artwork (`AnimatedIcons.vala`,
  librsvg + Cairo, same drawing code).
- Play button: the GTK3 states (stop while playing, pause at half opacity while buffering, error icon with the
  message as its tooltip, play when stopped) and the GTK3 online/offline control sensitivity.
- Volume: a vertical slider in the volume button's popover. Preferences: the GTK3 menu, in the menu button's popover
  (theme, startup, playback, stream info, data, export/import starred, About).

## Logic moved into the core (shared by both frontends)

- `PlayerController.request_station (station)`: what a click on a station means. Ignored offline, on the station
  playing, and while an earlier change settles (`STATION_CHANGE_SETTLE_MS`); an accepted station is remembered as the
  last played. Tests: `/player/request-station`, `/player/request-station-offline`.
- `Settings.is_category_expanded (n)` / `set_category_expanded (n, expanded)`: the saved open/closed state of the
  sidebar sections.
- `GstFader`: a transition cancelled by a newer one now stops the player that was fading out. Before, quick station
  changes left earlier stations playing.

Other logic that still lives in a frontend and probably belongs in the core: playing a station found by its UUID
(GTK3 `HeaderBar.play_station_by_uuid`), and the codec/bitrate label and star/warning prefix a station list shows.

## TODO: librsvg deprecation warnings (estimate options)

The animated tuner and jukebox icons (`src/AnimatedIcons.vala`, and the same code in
`tuner-gtk3/src/Widgets/base/AnimatedIcons.vala`) warn about:

- `Rsvg.Handle.get_dimensions` (used to scale the artwork to the widget; lines ~163 and ~372 in GTK4)
- `Rsvg.Handle.render_cairo_sub` (draws one SVG element by id with our own translate/rotate; ~6 calls)
- `Rsvg.Handle.render_cairo` (draws the whole vinyl record, rotated; deprecated the same way)

Both apps use the same code, so the fix should be shared, and verified visually against the GTK3 screenshots
(needle and record positions must not move).

Options to estimate:

1. **Port to the new API** (`get_intrinsic_size_in_pixels` / `get_geometry_for_element` +
   `render_element(cr, "#id", viewport)` / `render_document`). Correct long term. Risk: the new calls position an
   element inside a viewport, so the needle/record transform maths (the RECORD_* and NEEDLE_* constants, which
   assume the old whole-canvas coordinates) must be re-derived. Estimate: medium, mostly testing the geometry.
2. **Pre-split the artwork** into separate SVG files (base, window, needle, record) and draw each with
   `render_document`, doing the translate/rotate with Cairo. No element-by-id calls, so the geometry stays simple.
   Cost: more files in the gresource, a small asset change in both apps. Estimate: small to medium.
3. **Switch to Gtk-native rendering** (`Gtk.Snapshot` with `Gsk` transforms of `Gdk.Texture`s or
   `Rsvg` -> texture once). GPU friendly and removes Cairo from the draw path; the biggest change. Estimate: large.
4. **Leave the warnings** (they are only deprecation notices; librsvg still ships these calls) or bind the C functions
   directly, as done for `gtk_style_context_add_provider_for_display` in `Style.vala`. Estimate: trivial, but defers
   the problem until librsvg removes them.

Suggested order: 4 now if the noise matters, then 1 or 2 for both apps together.

**Update:** option 1 is being worked on in `tuner-tng/cairo` (a headless old-vs-new pixel comparison test, plus
`scripts/port-apps.py` to apply the change to both apps once the test passes). See its README.

## Station menu parity (GTK3 StationContextMenu)

Added to the GTK4 row menu: "Share stream URI" (`ShareStreamWindow`: QR card with the tower icon, click to copy the
image or the URI; needs libqrencode, with `vapi/libqrencode.vapi` copied from the GTK3 app), "Add Note" / "Edit Note"
on starred stations, and "Update Station from Online" (with the changes as a tooltip) when a starred station is out
of date with the provider's index. The QR card drawing uses `render_document`, the current librsvg call.
Candidate for the core later: the QR encoding (`encode`, error-correction level, icon share) is toolkit-free; it
would need libqrencode as a core dependency.

**librsvg port done:** the `tuner-tng/cairo` test drew the tuner and jukebox with the old and the new calls in 40
cases (5 sizes, 4 states each) and found them pixel-identical (max difference 0). Both apps' `AnimatedIcons.vala` now
use a small `SvgLayers` wrapper (`get_intrinsic_size_in_pixels`, `render_layer`, `render_document`), the GTK3 share
window uses `render_document`, and both meson files require librsvg >= 2.52.
