set shell := ["sh", "-c"]
set windows-shell := ["powershell.exe", "-c"]

bin := home_directory() / ".local/bin"
data := env("XDG_DATA_HOME", home_directory() / ".local/share")
release := justfile_directory() / "zig-out/release"
units := env("XDG_CONFIG_HOME", home_directory() / ".config") / "systemd/user"

[doc('Compile every artifact without running it')]
check:
    zig build check

[doc('Compile every artifact for Linux from any host')]
check-linux:
    zig build check -Dtarget=x86_64-linux-gnu

[doc('Compile every artifact for Windows from any host')]
check-windows:
    zig build check -Dtarget=x86_64-windows-gnu

[doc('Run the continuous integration pipeline')]
ci:
    zig build ci
    zig build test:unit -Doptimize=safe

[doc('Format build.zig and every source file')]
fmt:
    zig fmt build.zig src

[doc('Regenerate the tray pixmaps from the icons')]
icons:
    magick 'assets/active.ico[2]' -depth 8 rgba:assets/active.rgba
    magick 'assets/inactive.ico[2]' -depth 8 rgba:assets/inactive.rgba

[doc('Build a release, install it, its user service, and its desktop entry, and restart the service on the new build')]
[linux]
install:
    zig build --release=safe --prefix '{{ release }}'
    install -D -m 755 '{{ release }}/bin/phantom' '{{ bin }}/phantom.new'
    mv -f '{{ bin }}/phantom.new' '{{ bin }}/phantom'
    install -D -m 644 contrib/phantom.service '{{ units }}/phantom.service'
    install -D -m 644 contrib/phantom.desktop '{{ data }}/applications/phantom.desktop'
    install -D -m 644 assets/inactive.svg '{{ data }}/icons/hicolor/scalable/apps/phantom.svg'
    touch '{{ data }}/icons/hicolor'
    systemctl --user daemon-reload
    systemctl --user enable phantom.service
    systemctl --user restart phantom.service
    sleep 2
    systemctl --user is-active phantom.service

[doc('Lint build.zig and every source file with tigerstyle-lsp')]
lint:
    tigerstyle-lsp check build.zig src --format concise

[default]
[doc('List every recipe')]
list:
    @just --list

[doc('Build and run the application')]
run:
    zig build run

[doc('Run every test suite and the format check')]
test:
    zig build test

[doc('Run the end to end tests against the fake backends: just test-fake [filter]')]
test-fake filter="":
    zig build test:fake {{ if filter == "" { "" } else { "-Dtest-filter=" + filter } }}

[doc('Run the unit tests and the tidy check: just test-unit [filter]')]
test-unit filter="":
    zig build test:unit {{ if filter == "" { "" } else { "-Dtest-filter=" + filter } }}
