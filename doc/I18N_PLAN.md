# Translations for tuner-gtk4: ideas (nothing implemented yet)

Aim: the **same build process as tuner-gtk3**, so the Weblate translations reach the app unchanged.

## 1. How GTK3 does it (the model to copy)

| Piece | GTK3 | Role |
|---|---|---|
| `po/application/{POTFILES,LINGUAS,application.pot}` | hand-kept POTFILES, `i18n.gettext('application', preset:'glib', install:false)` | UI strings (includes the core's `Models/*.vala`) |
| `po/countries/...` | POTFILES = core `Countries.vala`, `Languages.vala` | country / language names |
| `po/extra/...` | POTFILES = `data/*.desktop.in`; used by `i18n.merge_file(po_dir: po/extra)` | launcher text |
| `scripts/merge-po.sh` | run by `meson.build` at configure time | `msgcat --use-first` application + countries `.po` into `po/<lang>.po`, writes `po/LINGUAS` |
| `po/meson.build` | `subdir` the three, then `i18n.gettext(meson.project_name(), preset:'glib', install:true)` | compiles `po/*.po` to `.mo`, installs to `localedir` |
| `-Dtranslation=update` | combo option | enables the `*-pot` targets; `.pot` regenerated with `meson compile application-pot` etc. |
| `.gitattributes` | `po/**/*.po merge=theirs` | Weblate wins on conflicting PRs |
| Weblate | components Application / Countries / Flatpak metadata / Glossary, PRs against `development` | reads the `.pot` + `LINGUAS`, returns `.po` |

The gettext **domain** is `io.github.tuner_labs.tuner`, shared by the app and the core. The core's own
`GETTEXT_PACKAGE` / `LOCALEDIR` (Config.vala) and `Locales.found()` already follow this, which is why the
language selector can list what is installed.

## 2. Ideas

1. **Copy the layout verbatim.** Add `po/`, `scripts/merge-po.sh`, `.gitattributes` and `meson_options.txt: translation`
   to tuner-gtk4 exactly as in GTK3. Same `.mo` files, same Weblate components, no new tooling.
2. **Seed the catalogues from GTK3** (one-time copy of `po/*/*.po`, `LINGUAS`). Keep wording of strings identical to
   GTK3 where the UI is the same: Weblate matches by msgid, so every unchanged string arrives already translated.
   Only genuinely new GTK4 strings need translators.
3. **Weblate: do not run two sources.** Until the rename, Weblate stays on the GTK3 repo. At the rename (gtk4 becomes
   `tuner`) point the existing components at the new repo/branch; the `po/<component>/` paths are the same so nothing
   else changes. Before then, re-copy from GTK3 when Weblate PRs are merged (a small `scripts/sync-po-from-gtk3.sh`).
4. **Domain name.** GTK4's meson project is `io.github.tuner_labs.tuner.gtk4`; use the explicit domain
   `io.github.tuner_labs.tuner` in `po/meson.build` (and `-DGETTEXT_PACKAGE`) so GTK4 and core share one catalogue and
   the GTK3 `.mo` names still apply. After the rename the project name matches anyway.
5. **POTFILES for the new layout.** GTK4 paths: `src/App.vala`, `src/windows/*.vala`, `src/widgets/*.vala`; core:
   `subprojects/tuner-core/src/Models/{History,Station,StreamMetadata}.vala` (the `_()` users, as in GTK3).
   Add `scripts/check-potfiles.sh`: lists any `.vala`/`.in` containing `_(` that is not in a POTFILES (GTK3 relies on memory).
6. **String sweep.** GTK4 has no `_()` yet. Wrap UI text (menus, headings, tooltips, preferences, dialogs, "Connecting..."
   states) with `_()`; use `ngettext` for counts; keep `Intl.bindtextdomain` (already in `App.vala`).
7. **Metadata.** Rename GTK4 `.desktop` and `.metainfo.xml` to `*.in`, process both with `i18n.merge_file`
   (`type: 'desktop'` / `'xml'`, `po_dir: po/extra`) and list both in `po/extra/POTFILES`. GTK3 only translates the
   `.desktop`; adding the metainfo gives translated Flathub summary/description.
8. **Flatpak.** Install to `/app/share/locale`; flatpak-builder splits the `.mo` into the `.Locale` extension, and users
   only get their configured languages. For the dev manifest the language selector therefore only lists installed ones:
   `flatpak config --set languages '*'` once, then reinstall, to see them all. The Flathub release manifest needs the
   committed `po/*.po` (Weblate PRs merged) and gettext in the SDK (present).
9. **Local debug builds** keep `LOCALEDIR = build/po`, so `meson compile` + run shows translations without installing.
10. **CI (optional).** A GitHub Action that regenerates the `.pot` and fails if it differs from the committed one, so
    Weblate never sees stale sources.

## 3. Suggested order

1. Skeleton: `po/` tree, merge script, options, meson wiring, seeded `.po` (ideas 1, 2, 4).
2. POTFILES + `check-potfiles.sh` (5), then the `_()` sweep per file (6); regenerate `.pot`.
3. Metadata via `merge_file` (7) and Flatpak manifest/README notes (8).
4. Weblate repoint at the rename (3).

Open questions: keep GTK3's `po/*.po` generated copies committed (as GTK3 does) or build them only at configure time?
Re-use the existing glossary component unchanged?

## 4. Status: step 1 done (unbuilt)

- `po/` copied from GTK3 (catalogues, `LINGUAS`, `.po`, meson files); `po/meson.build` uses the explicit domain.
- `po/*/POTFILES` rewritten for the GTK4 paths. `po/extra` lists the `.desktop.in` and `.metainfo.xml.in`.
- `scripts/merge-po.sh` and `.gitattributes` copied; `meson.build` runs the script, defines `GETTEXT_PACKAGE`, `subdir('po')`.
- `meson_options.txt`: `translation` (`update` / `none`).
- `data/*.desktop` and `*.metainfo.xml` renamed to `*.in`, installed through `i18n.merge_file`.
- The `.pot` files are still GTK3's: regenerate after the `_()` sweep (step 2) with
  `meson setup build/meson -Dtranslation=update && meson compile -C build/meson application-pot countries-pot extra-pot`.
