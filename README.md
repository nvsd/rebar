# Rebar

A menu bar remote for the Google TV Streamer.

## Run it

Needs macOS 26 or later and Xcode (or the Xcode command line tools).

```sh
bash scripts/build-app.sh
open build/Rebar.app
```

To keep it, run `bash scripts/build-app.sh --install`, which copies it to `/Applications/Rebar.app`. `--dmg` also makes a signed `build/Rebar.dmg` to drag into Applications. Turn on Open at Login from the ••• menu.

A remote icon appears in the menu bar. Rebar has no Dock icon; quit it from the ••• menu at the bottom of its window.

To work on it in Xcode, open `Package.swift`.

The DMG from `--dmg` is signed with a personal Apple Development certificate, not notarized, so it will not open cleanly on other Macs. Build from source with the steps above instead.

## Tests

```sh
swift test
```

## Design

Rebar is built only from stock SwiftUI controls, so it follows Apple's current Liquid Glass look on macOS 26 and later without custom styling:
- The layout follows the Google TV and Roku phone remotes: a D-pad of glass circles with OK as the prominent button, then Back, Home and Input, volume, and app shortcuts.
- Pairing uses a standard list, text fields and progress views.
- The one main action on each screen uses `.glassProminent`.
- Holding the arrow or volume keys repeats them, using the system `buttonRepeatBehavior`.
- The keyboard shortcuts are standard `keyboardShortcut`s.

The app icon is an Icon Composer document (`Support/AppIcon.icon`), so macOS draws its light, dark and tinted looks.

Rebar needs macOS 26 or later, so there's no fallback look for older systems.

## Keyboard

While the panel is open:

- Arrow keys move
- Return selects
- Delete goes back
- H goes Home
- `-` and `=` change the volume
- M mutes

## Status

- [x] Step 1: menu bar shell with every Streamer button (buttons log but don't reach the TV yet)
- [x] Step 2: find the Streamer on the network and pair with it
- [x] Step 3: send button presses, hold to repeat, keyboard control
- [x] Step 4: polish and test on the TV

## Credits

The protocol details come from [androidtvremote2](https://github.com/tronikos/androidtvremote2) (Apache 2.0). See `NOTICE`.

## License

MIT. See `LICENSE`.
