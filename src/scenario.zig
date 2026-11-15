const std = @import("std");

const nimble = @import("nimble");
const umbra = @import("umbra");

const ApplicationType = @import("application.zig").ApplicationType;
const Command = @import("menu.zig").Command;
const Message = @import("application.zig").Message;
const offset_pixels_max = @import("application.zig").offset_pixels_max;
const offset_pixels_min = @import("application.zig").offset_pixels_min;
const State = @import("state.zig").State;
const TimerID = @import("application.zig").TimerID;

const Libraries = struct {
    pub const App = umbra.AppType(umbra.Fake);
    pub const Client = nimble.RuntimeType(nimble.Fake).Client;
};

const Application = ApplicationType(Libraries);
const testing = std.testing;

fn open() !*Application {
    const application = try testing.allocator.create(Application);
    errdefer testing.allocator.destroy(application);

    try application.init(null);

    return application;
}

fn close(application: *Application) void {
    application.deinit();
    testing.allocator.destroy(application);
}

fn label_of(application: *const Application, command: Command) []const u8 {
    const item = application.runtime.menu.get_item(@backingInt(command)) orelse return "";
    return item.get_label();
}

fn post(application: *Application, message: Message) void {
    application.on_custom(.{ .code = @fromBackingInt(@backingInt(message)) });
}

fn select(application: *Application, command: Command) void {
    application.on_menu_select(.{ .checked = false, .id = @backingInt(command) });
}

fn tick(application: *Application, timer: TimerID) void {
    application.on_timer_tick(.{ .id = @backingInt(timer), .count = 0 });
}

test "a fresh application is inactive and shows the activate label" {
    const application = try open();
    defer close(application);

    try testing.expectEqual(State.inactive, application.state);
    try testing.expectEqualStrings("inactive", application.runtime.icons.get_current_name().?);
    try testing.expectEqualStrings("Activate", label_of(application, .toggle));
    try testing.expectEqualStrings("Exit", label_of(application, .exit));
    try testing.expectEqual(@as(u32, 0), application.runtime.notifier.sent_count());
}

test "a posted toggle activates the application" {
    const application = try open();
    defer close(application);

    post(application, .toggle);

    try testing.expectEqual(State.active, application.state);
    try testing.expectEqualStrings("active", application.runtime.icons.get_current_name().?);
    try testing.expectEqualStrings("Deactivate", label_of(application, .toggle));
    try testing.expectEqual(@as(u32, 1), application.runtime.notifier.sent_count());
}

test "a second posted toggle deactivates the application" {
    const application = try open();
    defer close(application);

    post(application, .toggle);
    post(application, .toggle);

    try testing.expectEqual(State.inactive, application.state);
    try testing.expectEqualStrings("inactive", application.runtime.icons.get_current_name().?);
    try testing.expectEqualStrings("Activate", label_of(application, .toggle));
    try testing.expectEqual(@as(u32, 2), application.runtime.notifier.sent_count());
}

test "an unknown custom code leaves the application alone" {
    const application = try open();
    defer close(application);

    post(application, @fromBackingInt(@backingInt(Message.toggle) + 1));

    try testing.expectEqual(State.inactive, application.state);
    try testing.expectEqual(@as(u32, 0), application.runtime.notifier.sent_count());
}

test "the menu toggle drives the same transition as a posted code" {
    const application = try open();
    defer close(application);

    select(application, .toggle);

    try testing.expectEqual(State.active, application.state);

    select(application, .toggle);

    try testing.expectEqual(State.inactive, application.state);
}

test "an unknown menu identifier is ignored" {
    const application = try open();
    defer close(application);

    select(application, @fromBackingInt(@backingInt(Command.exit) + 1));

    try testing.expectEqual(State.inactive, application.state);
}

test "a move tick synthesizes one bounded pointer movement" {
    const application = try open();
    defer close(application);

    try application.client.connect();

    post(application, .toggle);

    const record = &application.client.raw.record;
    const before = record.count_of(.mouse_move);

    tick(application, .move);

    const after = record.count_of(.mouse_move);
    const moved = record.last() orelse return error.MoveMissing;

    try testing.expectEqual(before + 1, after);
    try testing.expect(moved.kind == .mouse_move);
    try testing.expect(moved.x >= offset_pixels_min);
    try testing.expect(moved.x <= offset_pixels_max);
    try testing.expect(moved.y >= offset_pixels_min);
    try testing.expect(moved.y <= offset_pixels_max);
}

test "a tick for another timer never moves the pointer" {
    const application = try open();
    defer close(application);

    try application.client.connect();

    post(application, .toggle);

    const record = &application.client.raw.record;
    const before = record.count_of(.mouse_move);

    tick(application, @fromBackingInt(@backingInt(TimerID.move) + 1));

    try testing.expectEqual(before, record.count_of(.mouse_move));
}

test "shutdown while inactive is inert" {
    const application = try open();
    defer close(application);

    application.on_app_shutdown();

    try testing.expectEqual(State.inactive, application.state);
}

test "many toggles leave the state consistent" {
    const application = try open();
    defer close(application);

    var round: u32 = 0;

    while (round < 32) : (round += 1) {
        post(application, .toggle);

        try testing.expectEqual(round % 2 == 0, application.state.is_active());
    }

    try testing.expectEqual(State.inactive, application.state);
}

const Probe = struct {
    application: *Application,
    icon_pushed: bool = false,
    timer_started: bool = false,
    timer_stopped_by_shutdown: bool = false,
    timer_stopped_by_toggle: bool = false,
    tray_created: bool = false,

    pub fn on_app_init(probe: *Probe) void {
        const application = probe.application;
        const timers = &application.runtime.timers;

        probe.tray_created = application.runtime.tray.is_created();

        post(application, .toggle);

        probe.timer_started = timers.is_running(@backingInt(TimerID.move));
        probe.icon_pushed = application.runtime.icons.get_current() != null;

        post(application, .toggle);

        probe.timer_stopped_by_toggle = !timers.is_running(@backingInt(TimerID.move));

        post(application, .toggle);
        application.on_app_shutdown();

        probe.timer_stopped_by_shutdown = !timers.is_running(@backingInt(TimerID.move));
    }
};

test "a full run creates the tray and the toggle drives the move timer" {
    const application = try open();
    defer close(application);

    var probe = Probe{ .application = application };

    try application.runtime.bus.attach(Probe, &probe);
    try application.run();

    try testing.expectEqual(@as(u8, 6), application.runtime.bus.listener_count());
    try testing.expect(probe.tray_created);
    try testing.expect(probe.icon_pushed);
    try testing.expect(probe.timer_started);
    try testing.expect(probe.timer_stopped_by_toggle);
    try testing.expect(probe.timer_stopped_by_shutdown);
}
