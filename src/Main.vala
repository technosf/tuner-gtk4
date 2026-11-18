/**
 * SPDX-FileCopyrightText: Copyright © 2026 technosf <https://github.com/technosf>
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * @file Main.vala
 *
 * @brief Entry point of the GTK4 prototype.
 */

public static int main (string[] args)
{
    Intl.setlocale (LocaleCategory.ALL, "");
    Gst.init (ref args);

    var app = new TunerGtk4.App ();
    return app.run (args);
}
