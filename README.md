<p align="center">
    <picture>
        <source media="(prefers-color-scheme: dark)" srcset="assets/phantom-lockup-on-dark.svg">
        <source media="(prefers-color-scheme: light)" srcset="assets/phantom-lockup-on-light.svg">
        <img alt="phantom" src="assets/phantom-lockup-on-light.svg" width="375">
    </picture>
</p>

&nbsp;

<p align="center">
    A tray application that keeps your machine from going idle, on Windows and Linux.
</p>

<p align="center">
    <a href="https://github.com/braycarlson/phantom/actions/workflows/ci.yml"><img alt="ci" src="https://img.shields.io/github/actions/workflow/status/braycarlson/phantom/ci.yml?branch=main&amp;style=flat-square&amp;label=ci"></a>
    <a href="https://ziglang.org"><img alt="zig" src="https://img.shields.io/badge/zig-0.16.0-orange.svg?style=flat-square"></a>
    <a href="LICENSE"><img alt="license" src="https://img.shields.io/badge/license-MIT-blue.svg?style=flat-square"></a>
</p>

## Overview

phantom nudges the mouse pointer every ten seconds so the machine never reads as idle. The
nudge goes through the input layer the operating system watches for idleness.

## Features

- **Relative movement**: The pointer moves by an offset rather than to a coordinate, so
  whatever the cursor was over stays under it.
- **Random offset**: Each nudge picks its own offset between -50 and 50 pixels on both
  axes.
- **Toggle**: The tray menu turns the timer on and off, and the icon states which it is.
- **No configuration**: There is no configuration file.

## Install

Each tagged release carries a Linux and a Windows build.

The build from source looks for [nimble](https://github.com/braycarlson/nimble) and
[umbra](https://github.com/braycarlson/umbra) in the same parent directory, since
`build.zig.zon` points at them by relative path. It fetches
[arc](https://github.com/braycarlson/arc) by URL.

```
git clone https://github.com/braycarlson/nimble
git clone https://github.com/braycarlson/umbra
git clone https://github.com/braycarlson/phantom
cd phantom
zig build -Doptimize=ReleaseSafe
```

The binary lands in `zig-out/bin`. phantom requires Zig 0.16.0.

## Usage

The application starts in the tray with the timer running. The menu carries the toggle and
exit, and the tray reports each change of state.

| Setting | Value |
|---|---|
| Interval | The fixed ten seconds. |
| Offset | The random range from -50 to 50 pixels per axis. |
| Movement | The relative nudge that leaves the pointer where it was. |

Linux needs the `nimbled` daemon from [nimble](https://github.com/braycarlson/nimble),
which its `contrib/systemd` installer sets up along with the `uinput` permission.

## Development

The recipes below wrap `zig build`, and a bare `just` lists them all. The tidy law is a
test rather than a separate linter, so the mechanical rules run with everything else.

| Command | What it runs |
|---|---|
| `just ci` | The formatting check, compilation, and the test suites. |
| `just test` | The unit tests and the mock suite. |
| `just tidy` | The tidy law on its own. |
| `just run` | The application from source. |
| `just check-windows` | The compile of every artifact for Windows from any host. |

## Licence

MIT. See [LICENSE](LICENSE).
