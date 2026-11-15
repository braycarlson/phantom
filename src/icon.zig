const std = @import("std");

const umbra = @import("umbra");

const State = @import("state.zig").State;

const assert = std.debug.assert;

const CapacityError = umbra.CapacityError;
const Pixmap = umbra.Icon.Pixmap;
const PlatformError = umbra.PlatformError;
const RequestError = umbra.RequestError;

const dimension: u32 = 32;
const active = Pixmap.from_rgba(@embedFile("active.rgba"), dimension);
const inactive = Pixmap.from_rgba(@embedFile("inactive.rgba"), dimension);

comptime {
    assert(active.height == dimension);
    assert(inactive.height == dimension);
}

pub fn register(comptime App: type, icons: *App.IconSet) (CapacityError || RequestError)!void {
    assert(icons.is_empty());

    _ = try App.IconBuilder.init(icons)
        .pixels(State.active.to_string(), active)
        .pixels(State.inactive.to_string(), inactive)
        .done();

    assert(!icons.is_empty());
}

pub fn show(
    comptime App: type,
    icons: *App.IconSet,
    state: State,
) (PlatformError || RequestError)!void {
    const name = state.to_string();

    assert(icons.get_source(name) != null);

    try icons.set_current(name);
}

const testing = std.testing;

const FakeApp = umbra.AppType(umbra.Fake);

fn partial_alpha_count(argb: []const u8) u32 {
    assert(argb.len % 4 == 0);

    var result: u32 = 0;
    var index: usize = 0;

    while (index < argb.len) : (index += 4) {
        const alpha = argb[index];
        if (alpha == 0) continue;
        if (alpha == 255) continue;

        result += 1;
    }

    assert(result <= argb.len / 4);

    return result;
}

test register {
    var app: FakeApp = undefined;

    try app.init(.{ .name = "phantom" });
    defer app.deinit();

    try register(FakeApp, &app.icons);
    try show(FakeApp, &app.icons, .inactive);

    try testing.expectEqualStrings("inactive", app.icons.get_current_name().?);
}

test show {
    var app: FakeApp = undefined;

    try app.init(.{ .name = "phantom" });
    defer app.deinit();

    try register(FakeApp, &app.icons);
    try show(FakeApp, &app.icons, .active);

    try testing.expectEqualStrings("active", app.icons.get_current_name().?);

    try show(FakeApp, &app.icons, .inactive);

    try testing.expectEqualStrings("inactive", app.icons.get_current_name().?);
}

test "the embedded pixmaps are complete 32 bit images" {
    try testing.expectEqual(dimension * dimension * 4, active.argb.len);
    try testing.expectEqual(dimension * dimension * 4, inactive.argb.len);
    try testing.expect(active.is_valid());
    try testing.expect(inactive.is_valid());
}

test "each pixmap keeps the antialiasing of the frame it was taken from" {
    try testing.expect(partial_alpha_count(active.argb) > 0);
    try testing.expect(partial_alpha_count(inactive.argb) > 0);
}

test "the opaque body of each icon carries the colour its source declares" {
    const offset = ((20 * dimension) + 21) * 4;

    try testing.expectEqualSlices(u8, &.{ 0xff, 0xdc, 0x26, 0x26 }, active.argb[offset..][0..4]);
    try testing.expectEqualSlices(u8, &.{ 0xff, 0xff, 0xff, 0xff }, inactive.argb[offset..][0..4]);
}
