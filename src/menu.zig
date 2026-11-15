const std = @import("std");

const umbra = @import("umbra");

const State = @import("state.zig").State;

const assert = std.debug.assert;

const CapacityError = umbra.CapacityError;

pub const Command = enum(u32) {
    exit = 1002,
    toggle = 1001,
    _,
};

pub fn fill(comptime App: type, menu: *App.Menu, state: State) CapacityError!void {
    menu.clear();

    assert(menu.is_empty());

    _ = try App.MenuBuilder.init(menu)
        .action(@backingInt(Command.toggle), state.to_label())
        .separator()
        .action(@backingInt(Command.exit), "Exit")
        .done();

    assert(!menu.is_empty());
}

const testing = std.testing;

const FakeApp = umbra.AppType(umbra.Fake);

test fill {
    var app: FakeApp = undefined;

    try app.init(.{ .name = "phantom" });
    defer app.deinit();

    const exit = @backingInt(Command.exit);
    const toggle = @backingInt(Command.toggle);

    try fill(FakeApp, &app.menu, .inactive);

    try testing.expectEqualStrings("Activate", app.menu.get_item(toggle).?.get_label());
    try testing.expectEqualStrings("Exit", app.menu.get_item(exit).?.get_label());

    try fill(FakeApp, &app.menu, .active);

    try testing.expectEqualStrings("Deactivate", app.menu.get_item(toggle).?.get_label());
}
