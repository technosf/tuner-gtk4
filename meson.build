# Copyright © 2026 <https://github.com/technosf>
# SPDX-FileCopyrightText: © 2026 <https://github.com/technosf>
#
# SPDX-License-Identifier: GPL-3.0-or-later
#

# Tuner GTK4: an experimental presentation layer for the Tuner core (tuner-core). It uses only the core's public
# API. It installs its launcher, metadata and icons for packaging (see ../tuner-flatpak).
project (
    'io.github.tuner_labs.tuner.gtk4',
    'vala', 'c',
    version: '3.0.0-beta.1',
    meson_version: '>= 1.3.2',
)

# The core is a meson subproject: subprojects/tuner-core is a checkout of the tuner-core repository (a symbolic link
# to a neighbouring checkout while developing; see subprojects/README.md).
# The log domain of this app's own messages: run with G_MESSAGES_DEBUG=Tuner for just those (the core uses it too)
add_project_arguments ('-DG_LOG_DOMAIN="Tuner"', language: 'c')

core = subproject ('tuner-core')
core_dep = core.get_variable ('core_dep')
core_version = core.get_variable ('core_version')

# The oldest core this app works with. The core has its own version (semver); a release of this app is built with one
# exact core (the manifest pins it), and says which in its About box and debug log.
core_minimum = '3.0.0'
if not core_version.version_compare ('>=' + core_minimum)
    error ('tuner-gtk4 needs tuner-core @0@ or newer, but found @1@'.format (core_minimum, core_version))
endif

version_data = configuration_data ()
version_data.set_quoted ('APP_VERSION', meson.project_version ())
version_data.set_quoted ('CORE_VERSION', core_version)
version_data.set_quoted ('PACKAGING', get_option ('packaging'))
version_file = configure_file (
    input: 'src/Version.vala.in',
    output: 'Version.vala',
    configuration: version_data
)

gnome = import ('gnome')
i18n = import ('i18n')
fs = import ('fs')

##
## Translations: the same process as tuner-gtk3 (see doc/I18N.md). Weblate delivers the .po files
##
po_script = join_paths (meson.project_source_root (), 'scripts', 'merge-po.sh')
if fs.exists (po_script)
    run_command (po_script, check: true)        # application + countries .po merged into po/<lang>.po, po/LINGUAS written
endif
add_project_arguments (
    '-DGETTEXT_PACKAGE="@0@"'.format ('io.github.tuner_labs.tuner'),    # One domain for the app and the core
    language: 'c'
)
subdir ('po')

gtk4_resources = gnome.compile_resources (
    'tuner-gtk4-resources',
    'data/tuner-gtk4.gresource.xml',
    source_dir: 'data',
    c_name: 'tuner_gtk4'
)

gtk4_sources = files (
    'src/App.vala',
    'src/Main.vala',
    'src/Style.vala',
    'src/widgets/AnimatedIcons.vala',
    'src/widgets/HistoryButton.vala',
    'src/widgets/Images.vala',
    'src/widgets/NowPlaying.vala',
    'src/widgets/SlidingLabel.vala',
    'src/widgets/Fade.vala',
    'src/widgets/StationRow.vala',
    'src/windows/MainWindow.vala',
    'src/windows/MetadataImagePopup.vala',
    'src/windows/NoteWindow.vala',
    'src/windows/PreferencesWindow.vala',
    'src/windows/ShareStreamWindow.vala'
)

# Dev-only language selector in Preferences: local debug builds, or when asked for explicitly (development Flatpak)
gtk4_vala_args = [
    '--pkg',
    'posix',
    '--vapidir',
    join_paths (meson.current_source_dir (), 'vapi')
    ]
if (get_option ('debug') and get_option ('prefix') != '/app') or get_option ('language_selector')
    gtk4_vala_args += ['--define=LANGUAGE_SELECTOR']
endif

executable (
    'tuner-gtk4',
    gtk4_sources,
    version_file,
    gtk4_resources,
    dependencies: [
        core_dep, 
        dependency ('gtk4'), 
        dependency ('librsvg-2.0', version: '>= 2.52'), 
        dependency ('libqrencode')
        ],
    # vapi/libqrencode.vapi: libqrencode ships no Vala binding (copied from the GTK3 app)
    vala_args: gtk4_vala_args,
    install: true
)

# Installed for packaging (Flatpak, distribution packages): the launcher, the metadata and the icons.
# The core's subproject installs the settings schema.
# Translated with the po/extra catalogue
i18n.merge_file (
    input: 'data/io.github.tuner_labs.tuner.gtk4.desktop.in',
    output: 'io.github.tuner_labs.tuner.gtk4.desktop',
    po_dir: join_paths (meson.project_source_root (), 'po', 'extra'),
    type: 'desktop',
    install: true,
    install_dir: get_option ('datadir') / 'applications'
)
# The newest <release> takes its version from the project version (as in the GTK3 app), then the text is translated
metainfo_versioned = configure_file (
    input: 'data/io.github.tuner_labs.tuner.gtk4.metainfo.xml.in',
    output: 'io.github.tuner_labs.tuner.gtk4.metainfo.versioned.xml.in',
    configuration: {
        'VERSION': meson.project_version (),
        'VERSION_DATE': run_command ('date', '+%Y-%m-%d', check: true).stdout ().strip (),
    }
)
i18n.merge_file (
    input: metainfo_versioned,
    output: 'io.github.tuner_labs.tuner.gtk4.metainfo.xml',
    po_dir: join_paths (meson.project_source_root (), 'po', 'extra'),
    type: 'xml',
    install: true,
    install_dir: get_option ('datadir') / 'metainfo'
)
install_data ('data/icons/io.github.tuner_labs.tuner-scalable.svg',
    install_dir: get_option ('datadir') / 'icons/hicolor/scalable/apps',
    rename: 'io.github.tuner_labs.tuner.gtk4.svg')
install_data ('data/icons/io.github.tuner_labs.tuner-symbolic.svg',
    install_dir: get_option ('datadir') / 'icons/hicolor/symbolic/apps',
    rename: 'io.github.tuner_labs.tuner.gtk4-symbolic.svg')
