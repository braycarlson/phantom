const std = @import("std");

const nimble = @import("nimble");
const umbra = @import("umbra");

const Application = @import("application.zig").Application;
const constant = @import("constant.zig");
const State = @import("state.zig").State;

const Event = umbra.Event;
const Response = umbra.Response;

const monitor = nimble.mock.monitor;
const record = nimble.mock.record;

const testing = std.testing;

fn open(application: *Application) !void {
    nimble.mock.reset();

    try application.init(null);
}

fn label_of(application: *const Application, id: u32) []const u8 {
    const item = application.app.menu.get_item(id) orelse return "";

    return item.get_label();
}

test "a fresh application is inactive and shows the activate label" {
    var application: Application = undefined;

    try open(&application);
    defer application.deinit();

    try testing.expectEqual(State.inactive, application.state);
    try testing.expectEqualStrings("inactive", application.app.icon.get_current_name().?);
    try testing.expectEqualStrings("Activate", label_of(&application, constant.Menu.toggle));
    try testing.expectEqualStrings("Exit", label_of(&application, constant.Menu.exit));
    try testing.expectEqual(@as(u32, 0), application.app.notification.sent_count());
}

test "a posted toggle activates the application" {
    var application: Application = undefined;

    try open(&application);
    defer application.deinit();

    application.on_custom(constant.Message.toggle);

    try testing.expectEqual(State.active, application.state);
    try testing.expectEqualStrings("active", application.app.icon.get_current_name().?);
    try testing.expectEqualStrings("Deactivate", label_of(&application, constant.Menu.toggle));
    try testing.expectEqual(@as(u32, 1), application.app.notification.sent_count());
}

test "a second posted toggle deactivates the application" {
    var application: Application = undefined;

    try open(&application);
    defer application.deinit();

    application.on_custom(constant.Message.toggle);
    application.on_custom(constant.Message.toggle);

    try testing.expectEqual(State.inactive, application.state);
    try testing.expectEqualStrings("inactive", application.app.icon.get_current_name().?);
    try testing.expectEqualStrings("Activate", label_of(&application, constant.Menu.toggle));
    try testing.expectEqual(@as(u32, 2), application.app.notification.sent_count());
}

test "an unknown custom code leaves the application alone" {
    var application: Application = undefined;

    try open(&application);
    defer application.deinit();

    application.on_custom(constant.Message.toggle + 1);

    try testing.expectEqual(State.inactive, application.state);
    try testing.expectEqual(@as(u32, 0), application.app.notification.sent_count());
}

test "the menu toggle drives the same transition as a posted code" {
    var application: Application = undefined;

    try open(&application);
    defer application.deinit();

    application.on_menu_select(constant.Menu.toggle);

    try testing.expectEqual(State.active, application.state);

    application.on_menu_select(constant.Menu.toggle);

    try testing.expectEqual(State.inactive, application.state);
}

test "an unknown menu identifier is ignored" {
    var application: Application = undefined;

    try open(&application);
    defer application.deinit();

    application.on_menu_select(constant.Menu.exit + 1);

    try testing.expectEqual(State.inactive, application.state);
}

test "a move tick synthesizes one bounded pointer movement" {
    var application: Application = undefined;

    try open(&application);
    defer application.deinit();

    application.on_custom(constant.Message.toggle);

    const before = record.count_of(.mouse_move);
    const origin = monitor.get_cursor_position();

    application.on_timer_tick(constant.Timer.move_id);

    const after = record.count_of(.mouse_move);
    const moved = monitor.get_cursor_position();

    try testing.expectEqual(before + 1, after);

    const offset_x = moved.x - origin.x;
    const offset_y = moved.y - origin.y;

    try testing.expect(offset_x >= constant.Movement.offset_min);
    try testing.expect(offset_x <= constant.Movement.offset_max);
    try testing.expect(offset_y >= constant.Movement.offset_min);
    try testing.expect(offset_y <= constant.Movement.offset_max);
}

test "a tick for another timer never moves the pointer" {
    var application: Application = undefined;

    try open(&application);
    defer application.deinit();

    application.on_custom(constant.Message.toggle);

    const before = record.count_of(.mouse_move);

    application.on_timer_tick(constant.Timer.move_id + 1);

    try testing.expectEqual(before, record.count_of(.mouse_move));
}

test "shutdown while inactive is inert" {
    var application: Application = undefined;

    try open(&application);
    defer application.deinit();

    application.on_shutdown();

    try testing.expectEqual(State.inactive, application.state);
}

test "many toggles leave the state consistent" {
    var application: Application = undefined;

    try open(&application);
    defer application.deinit();

    var round: u32 = 0;

    while (round < 32) : (round += 1) {
        application.on_custom(constant.Message.toggle);

        try testing.expectEqual(round % 2 == 0, application.state.is_active());
    }

    try testing.expectEqual(State.inactive, application.state);
}

const Probe = struct {
    var owner: ?*Application = null;
    var icon_pushed: bool = false;
    var timer_started: bool = false;
    var timer_stopped_by_shutdown: bool = false;
    var timer_stopped_by_toggle: bool = false;
    var tray_created: bool = false;

    fn reset(application: *Application) void {
        owner = application;
        icon_pushed = false;
        timer_started = false;
        timer_stopped_by_shutdown = false;
        timer_stopped_by_toggle = false;
        tray_created = false;
    }

    fn handle(_: *const Event, _: ?*anyopaque) Response {
        const application = owner orelse return .pass;

        tray_created = application.app.tray.is_created();

        application.on_custom(constant.Message.toggle);

        timer_started = application.app.timer.is_running(constant.Timer.move_id);
        icon_pushed = application.app.icon.get_current() != null;

        application.on_custom(constant.Message.toggle);

        timer_stopped_by_toggle = !application.app.timer.is_running(constant.Timer.move_id);

        application.on_custom(constant.Message.toggle);
        application.on_shutdown();

        timer_stopped_by_shutdown = !application.app.timer.is_running(constant.Timer.move_id);

        return .pass;
    }
};

test "a full run creates the tray and the toggle drives the move timer" {
    var application: Application = undefined;

    try open(&application);
    defer application.deinit();

    Probe.reset(&application);

    _ = application.app.bus.on(.app_init, Probe.handle, null);

    try application.run();

    try testing.expect(Probe.tray_created);
    try testing.expect(Probe.icon_pushed);
    try testing.expect(Probe.timer_started);
    try testing.expect(Probe.timer_stopped_by_toggle);
    try testing.expect(Probe.timer_stopped_by_shutdown);
}
