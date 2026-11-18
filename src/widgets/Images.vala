/**
 * SPDX-FileCopyrightText: Copyright © 2026 technosf <https://github.com/technosf>
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * @file Images.vala
 *
 * @brief Image decoding for the core's favicon cache (GTK4 side).
 */

namespace TunerGtk4
{
    public class Images : Object
    {
        /** @brief True when GTK can read the file as an image. The core asks this of every favicon it downloads. */
        public static bool is_decodable (string path)
        {
            try
            {
                Gdk.Texture.from_filename (path);
                return true;
            } catch (Error e)
            {
                return false;
            }
        } // is_decodable
    } // Images
} // TunerGtk4
