/**
 * SPDX-FileCopyrightText: Copyright © 2020-2024 Louis Brauer <louis@brauer.family>
 * SPDX-FileCopyrightText: Copyright © 2024 technosf <https://github.com/technosf>
 * SPDX-FileCopyrightText: Copyright © 2026 technosf <https://github.com/technosf>
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * @file Style.vala
 *
 * @brief The look of the window, ported from the GTK3 app's Tuner-system.css.
 */

namespace TunerGtk4
{
    public class Style : Object
    {
        /** Point size of the "Tuner" title in the header while nothing is playing */
        private const int IDLE_TITLE_PT = 18;

        private const string CSS = """
.station-label { font-weight: 600; font-size: 11.5pt; letter-spacing: -0.05em; }
.station-label.idle { font-size: @IDLE_TITLE_PT@pt; margin-top: 6px; }
.track-info { font-size: 11pt; letter-spacing: -0.06em; opacity: 0.85; }
.stack-label { font-weight: 300; font-size: 18pt; letter-spacing: -0.05em; }

.sidebar-pane { background-color: alpha(currentColor, 0.04); }
.sidebar-heading { font-weight: 700; }
.sidebar-item { padding: 2px 8px; border-radius: 0; min-height: 0; }
dropdown.country-heading > button { padding: 4px 8px; border-radius: 0; min-height: 0; background: none; border: none; box-shadow: none; }
dropdown.country-heading > button:hover { background-color: alpha(currentColor, 0.08); }
dropdown.country-heading > button label { font-weight: 700; }
.sidebar-item.selected { background-color: @theme_selected_bg_color; color: @theme_selected_fg_color; }
headerbar button image { -gtk-icon-size: 24px; }

.station-list { background: transparent; }
.big-search, .big-search text { font-size: 14pt; }
.big-search { min-height: 38px; }
.big-search > text { margin-left: 10px; }
.pref-divider { min-height: 1px; background-color: alpha(black, 0.4); }
.mover-button { min-height: 0; min-width: 0; padding: 0 6px; color: #8a8a8a; }
.pref-button { min-height: 0; padding: 3px 8px; }
.metadata-popover { opacity: 0.85; }
.metadata-popover > contents { background-color: black; }
.metadata-popover label { color: white; }

/* Hover tips, as in the GTK3 app: dark and slightly see-through, with white text */
tooltip, tooltip.background { opacity: 0.75; background-color: black; border-radius: 8px; border: 1px solid black; }

/* Every popover has rounded corners and a black border, as in the GTK3 app */
popover > contents { border-radius: 8px; border: 1px solid black; }
tooltip > box { padding: 4px 8px; }
tooltip label { color: white; }
.drop-over { background-color: alpha(@theme_selected_bg_color, 0.35); border-radius: 6px; }
.station-list > child, .station-list > child:focus, .station-list > child:hover,
.station-list > child:selected { outline: none; box-shadow: none; background: transparent; padding: 0 4px; }
/* Hover, as in the GTK3 app: the border shows, then the background lights, then the border fades away */
@keyframes station-pop {
  0%   { background-color: alpha(currentColor, 0);    border-color: alpha(currentColor, 0.45); }
  35%  { background-color: alpha(currentColor, 0.08); border-color: alpha(currentColor, 0.45); }
  100% { background-color: alpha(currentColor, 0.08); border-color: alpha(currentColor, 0); }
}
.station-button { font-weight: 500; border-radius: 4px; padding: 0 2px; min-width: 300px;
                  border: 1px solid transparent; transition: background-color 250ms ease, border-color 250ms ease; }
.station-button:hover { background-color: alpha(currentColor, 0.08); animation: station-pop 700ms ease-out; }
.station-button image.station-icon { background-color: alpha(black, 0.25); margin-right: 5px; min-width: 48px; }

/* The station right-click menu */
popover.station-menu > contents { padding: 8px 0; border-radius: 4px; border: 1px solid black; }
popover.station-menu > contents > box { margin: 0; padding: 0; }
popover.station-menu button.station-menu-item { padding: 0 40px 0 14px; min-height: 0; min-width: 0; margin: 0; border: none; border-radius: 0; }
popover.station-menu button.station-menu-item:last-child { border-radius: 0; }
popover.station-menu button.station-menu-item > label { margin: 0; padding: 0; }
popover.station-menu separator { margin: 3px 8px; min-height: 1px; background-color: alpha(black, 0.4); }     /* as the preferences dividers */
popover.station-menu label.station-menu-head { margin: 0; padding: 0 14px; }
.station-button-description { font-size: 13px; color: gray; background-color: transparent; border: none; }
.tag { border-radius: 5px; min-width: 20px; min-height: 18px; font-size: 11px; font-weight: 400;
       margin-top: 4px; margin-bottom: 1px; padding: 0 8px; background-color: alpha(black, 0.2);
       border: 1px solid alpha(black, 0.7); }

.search-revealer-bg { background-color: alpha(currentColor, 0.1); border: 2px solid alpha(currentColor, 0.1); }

.history-popover > contents { padding: 0; }
.history-summary-box { margin-bottom: 2px; }
.history-summary-tile { background-color: alpha(currentColor, 0.05); border-radius: 6px; padding: 6px 8px; }
.history-summary-box button { padding: 0; border-radius: 6px; }
.history-summary-tile-active { background-color: alpha(@theme_selected_bg_color, 0.35); }
.history-summary-value { font-weight: 700; font-size: 13pt; }
.history-summary-caption { font-size: 8.5pt; opacity: 0.72; }
.history-action-row button { min-width: 32px; }
.history-list { background: transparent; }
.history-row { border-radius: 6px; background-color: alpha(currentColor, 0.03); }
.history-row-alt { background-color: alpha(@theme_selected_bg_color, 0.08); }
.history-row-hearted { background-color: alpha(#c52828, 0.10); border-left: 3px solid alpha(#c52828, 0.70); }
.history-row-station { font-weight: 700; }
.history-row-title { opacity: 0.88; }
.history-row-title-hearted { color: #b61f1f; font-weight: 600; }
.history-heart-badge { color: #c52828; background-color: transparent; border-radius: 0; font-size: 14pt; font-weight: 700; padding: 0; }
.history-play-time, .history-total-time { font-family: monospace; }

.heart-favorited image { color: #d00000; }
.star-favorited image { color: #e5a50a; }
""";

        public static void load ()
        {
            var provider = new Gtk.CssProvider ();
            provider.load_from_string (CSS.replace ("@IDLE_TITLE_PT@", IDLE_TITLE_PT.to_string ()));
            add_provider_for_display (Gdk.Display.get_default (), provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);
        } // load


        /**
         * GTK 4.10 deprecated the whole GtkStyleContext class, but this call, which is how an application
         * installs its CSS for every window, has no replacement (libadwaita still uses it). It is bound here
         * directly so the build is not noisy about it.
         */
        [CCode (cname = "gtk_style_context_add_provider_for_display")]
        private extern static void add_provider_for_display (Gdk.Display display, Gtk.StyleProvider provider, uint priority);
    } // Style
}
