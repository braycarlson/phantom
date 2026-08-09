const std = @import("std");

const wisp = @import("wisp");

const constant = @import("constant.zig");
const State = @import("state.zig").State;

const assert = std.debug.assert;

const App = wisp.App;
const IconBuilder = wisp.IconBuilder;
const IconError = wisp.IconError;
const IconPixmap = wisp.IconPixmap;

pub const channel_count: u32 = 4;
pub const pixmap_bytes: u32 = constant.Icon.dimension * constant.Icon.dimension * channel_count;

const active_argb = to_argb(@embedFile("active.rgba"));
const inactive_argb = to_argb(@embedFile("inactive.rgba"));

comptime {
    assert(channel_count == 4);
    assert(constant.Icon.dimension > 0);
    assert(active_argb.len == pixmap_bytes);
    assert(inactive_argb.len == pixmap_bytes);
}

pub const IconManager = struct {
    app: *App,

    pub fn init(app: *App) IconManager {
        const result = IconManager{
            .app = app,
        };

        return result;
    }

    pub fn configure(manager: *IconManager) IconError!void {
        _ = try IconBuilder.init(&manager.app.icon)
            .pixels("active", pixmap(&active_argb))
            .pixels("inactive", pixmap(&inactive_argb))
            .stock("active_fallback", .application)
            .stock("inactive_fallback", .shield)
            .done();

        manager.update(.inactive);
    }

    pub fn update(icon_manager: *IconManager, value: State) void {
        const manager = &icon_manager.app.icon;

        manager.set_current(value.to_string()) catch {
            manager.set_current(fallback_of(value)) catch {
                return;
            };
        };
    }
};

fn fallback_of(value: State) []const u8 {
    const result = switch (value) {
        .active => "active_fallback",
        .inactive => "inactive_fallback",
    };

    assert(result.len > 0);

    return result;
}

fn pixmap(argb: []const u8) IconPixmap {
    assert(argb.len == pixmap_bytes);

    const result = IconPixmap.init(argb, constant.Icon.dimension, constant.Icon.dimension);

    assert(result.is_valid());

    return result;
}

fn to_argb(comptime rgba: []const u8) [rgba.len]u8 {
    @setEvalBranchQuota(rgba.len * 8);

    var result: [rgba.len]u8 = undefined;
    var index: usize = 0;

    while (index + channel_count <= rgba.len) : (index += channel_count) {
        result[index + 0] = rgba[index + 3];
        result[index + 1] = rgba[index + 0];
        result[index + 2] = rgba[index + 1];
        result[index + 3] = rgba[index + 2];
    }

    return result;
}

fn partial_alpha_count(argb: []const u8) u32 {
    assert(argb.len == pixmap_bytes);
    assert(argb.len % channel_count == 0);

    var result: u32 = 0;
    var index: usize = 0;

    while (index < argb.len) : (index += channel_count) {
        const alpha = argb[index];

        if (alpha > 0 and alpha < 255) result += 1;
    }

    assert(result <= pixmap_bytes / channel_count);

    return result;
}

const testing = std.testing;

test "the embedded pixmaps are complete 32 bit images" {
    try testing.expectEqual(pixmap_bytes, active_argb.len);
    try testing.expectEqual(pixmap_bytes, inactive_argb.len);
    try testing.expect(pixmap(&active_argb).is_valid());
    try testing.expect(pixmap(&inactive_argb).is_valid());
}

test "to_argb moves the alpha channel in front of the colour channels" {
    const rgba = [_]u8{ 1, 2, 3, 4, 5, 6, 7, 8 };
    const argb = to_argb(&rgba);

    try testing.expectEqualSlices(u8, &.{ 4, 1, 2, 3, 8, 5, 6, 7 }, &argb);
}

test "each pixmap keeps the antialiasing of the frame it was taken from" {
    try testing.expect(partial_alpha_count(&active_argb) > 0);
    try testing.expect(partial_alpha_count(&inactive_argb) > 0);
}

test "the opaque body of each icon carries the colour its source declares" {
    const offset = ((20 * constant.Icon.dimension) + 21) * channel_count;

    try testing.expectEqualSlices(
        u8,
        &.{ 0xff, 0xdc, 0x26, 0x26 },
        active_argb[offset..][0..channel_count],
    );

    try testing.expectEqualSlices(
        u8,
        &.{ 0xff, 0xff, 0xff, 0xff },
        inactive_argb[offset..][0..channel_count],
    );
}

test "every fallback name is distinct from the state name" {
    try testing.expectEqualStrings("active_fallback", fallback_of(.active));
    try testing.expectEqualStrings("inactive_fallback", fallback_of(.inactive));
    try testing.expect(!std.mem.eql(u8, fallback_of(.active), State.active.to_string()));
}
