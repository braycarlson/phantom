set windows-shell := ["cmd.exe", "/c"]

# Default recipe
default:
    @just --list

# Run the whole continuous integration pipeline
ci:
    zig build ci --summary all

# Compile every artifact without running it
check:
    zig build check --summary all

# Compile every artifact for Linux from any host
check-linux:
    zig build check -Dtarget=x86_64-linux-gnu --summary all

# Compile every artifact for Windows from any host
check-windows:
    zig build check -Dtarget=x86_64-windows-gnu --summary all

# Build the application and install artifacts
build:
    zig build

# Build and run the application
run:
    zig build run

# Run every test suite
test:
    zig build test:unit test:mock --summary all

# Run the colocated unit tests and the tidy law, optionally filtered: just unit tidy
unit filter="":
    zig build test:unit --summary all -- {{filter}}

# Run the end to end tests against the mock backends, optionally filtered
mock filter="":
    zig build test:mock --summary all -- {{filter}}

# Run the tidy check on its own
tidy:
    zig build test:unit -- tidy

# Check that every source file is formatted
fmt:
    zig build test:fmt

# Format every source file in place
format:
    zig fmt build.zig src

# Regenerate the tray pixmaps from the icon sources
#
# The committed .rgba files are raw 32x32 8 bit per channel RGBA taken from the
# 32x32 frame of each .ico, which is index 2 in the icon directory. The .svg is
# not the source: it draws a different symbol, and its 256x340 viewBox does not
# match the 256x256 canvas it declares, so rasterising it stretches the artwork
# off its aspect ratio. The frame is already 32x32, so it is copied out without
# a resize. src/icon.zig moves the alpha channel to the front at comptime,
# because that is the ARGB order wisp ships to both backends.
[unix]
icons:
    convert 'asset/active.ico[2]' -depth 8 rgba:asset/active.rgba
    convert 'asset/inactive.ico[2]' -depth 8 rgba:asset/inactive.rgba

# Build with release safety checks
release:
    zig build -Doptimize=ReleaseSafe

# Build the smallest release binary
release-small:
    zig build -Doptimize=ReleaseSmall

# Clean build artifacts
[unix]
clean:
    rm -rf zig-out .zig-cache

# Clean build artifacts
[windows]
clean:
    if exist zig-out rmdir /s /q zig-out
    if exist .zig-cache rmdir /s /q .zig-cache
