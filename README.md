# Awake

A tiny macOS menu bar app that keeps your display awake for a chosen amount of time. Click a duration, get a live countdown in the menu bar, and a notification when time's up.

The point: no more `caffeinate -d -t 7200` in a terminal.

![status](https://img.shields.io/badge/platform-macOS%2013%2B-blue) ![swift](https://img.shields.io/badge/swift-6-orange)

## Features

- Menu bar cup icon with durations: 30 minutes, 1, 2, 4, 6, 8 hours, indefinitely, or a custom hours and minutes time
- Live countdown in both the menu bar icon and the menu
- Local notification when a timed session expires
- Optional "Start at login" via Apple's modern `SMAppService`
- Pure AppKit + IOKit, no dependencies, no Xcode project needed

## Build

```bash
./build.sh
```

That's it. Requires Xcode command line tools (`xcode-select --install`). The app is built with `swiftc` and ad-hoc signed, output lands in `build/Awake.app`.

## Install

```bash
cp -R build/Awake.app /Applications/
```

## How it works

The app holds an IOKit power assertion (`PreventUserIdleDisplaySleep`), the same mechanism `caffeinate -d` uses. You can watch it appear with `pmset -g assertions`.

```text
click duration -> IOPMAssertionCreateWithName -> powerd holds the lock -> countdown -> release + notify
```

Timed sessions pair the assertion with a `Timer` and release it automatically at zero. "Turn off" releases early. Quitting the app always releases the assertion.

## Notes

- Prevents idle display sleep only. Closing the lid still sleeps the Mac.
- The notification permission prompt appears the first time a timed session ends (or shortly after first launch).

## License

MIT
