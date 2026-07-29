# RotateApps

RotateApps is a lightweight macOS window switcher inspired by Windows Alt+Tab. It is designed for fast app/window rotation without relying on heavy live previews.

## Features

- Global shortcut based app/window switching.
- Configurable shortcut from the menu bar preferences.
- `Command + Tab` can be selected from a preset button; while it is selected, RotateApps turns off the built-in macOS application switcher so the shortcut is delivered reliably.
- Hold `Shift` with the configured shortcut to rotate backward.
- Separate entries for multiple windows in the same app.
- Window title plus optional thumbnail so similar windows can be distinguished.
- Same-app window activation uses AX window number first, then window position/size matching, so Chrome/Finder multi-window switching works more reliably.
- Regular desktop apps only; accessory/background helper apps are filtered out.
- All windows are shown in a centered grid.
- Adjustable switcher item size.
- Menu bar only app with no dock icon.
- Simple generated app icon with small-size variants for Finder list view.

## Download

Download the latest `RotateApps.zip` from GitHub Releases, unzip it, and open `RotateApps.app`.

The app is currently unsigned. macOS may require opening it from Finder via `Open` in the context menu the first time.

## Build

```sh
swift build
```

For a launchable app bundle:

```sh
./Scripts/build-app.sh
open .build/RotateApps.app
```

To build, replace the copy in `/Applications`, and relaunch it in one step:

```sh
./Scripts/install-app.sh
```

The running instance is quit through AppleScript first so it can restore the native `Command + Tab` shortcut. Set `ROTATEAPPS_INSTALL_DIR` to install somewhere else.

To create the same zip archive used for releases:

```sh
./Scripts/package-release.sh
```

## Release

Release archives are created by GitHub Actions when a `v*` tag is pushed.

```sh
git tag v0.1.0
git push origin v0.1.0
```

The workflow builds `RotateApps.app`, packages `.build/RotateApps.zip`, creates a GitHub Release, and uploads the zip as a downloadable asset.

## Permissions

macOS will ask for Accessibility permission the first time the app starts. This is required to raise and focus a selected window.

If thumbnails are enabled, macOS may also require Screen Recording permission for window contents to appear. Without that permission, RotateApps falls back to app icons and window titles.

If thumbnails do not appear, open the menu bar item and choose `Request Screen Recording Permission`, then enable RotateApps in System Settings. After rebuilding the app bundle, macOS may treat it as a new app; remove the old RotateApps entry from the Screen Recording permission list and add/enable the rebuilt app again.

## Default Shortcut

The default shortcut is `Option + Tab`. Hold `Shift` with the shortcut to rotate backward. Open the menu bar item and choose `Preferences...` to change the shortcut.

`Command + Tab` cannot be recorded normally because macOS handles it first. Use `Use Command + Tab` in Preferences to switch to that preset, and `Reset Default` to return to `Option + Tab`.

### How `Command + Tab` is taken over

macOS routes `Command + Tab` to its own switcher in the WindowServer, before any application shortcut. While that preset is selected, RotateApps disables the corresponding system shortcuts (`Command + Tab` and `Command + Shift + Tab`) and registers its own global hotkey instead.

That system setting persists after the process exits, so RotateApps restores it when quitting, and also on the next launch if it was left disabled by a crash. Selecting any other shortcut restores the built-in switcher immediately.

## Notes

- Thumbnails are best-effort. If Screen Recording permission is unavailable, RotateApps falls back to app icons and titles.
- The app intentionally filters out non-regular apps, such as helper tools that draw window borders or run only in the menu bar.
- Finder can cache app icons. If a rebuilt icon does not appear immediately, move the app, rename it temporarily, or restart Finder.
