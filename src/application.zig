const std = @import("std");

const arc = @import("arc");
const nimble = @import("nimble");
const umbra = @import("umbra");

const icon = @import("icon.zig");
const menu = @import("menu.zig");
const State = @import("state.zig").State;

const assert = std.debug.assert;

const CapacityError = nimble.remote.CapacityError;
const Command = menu.Command;
const Custom = umbra.Event.Custom;
const Key = nimble.Key;
const Logger = arc.Logger;
const PlatformError = nimble.remote.PlatformError;
const Position = nimble.Position;
const RequestError = nimble.remote.RequestError;
const Selection = umbra.Event.Selection;
const Tick = umbra.Event.Tick;

const RunError = umbra.Error || CapacityError || PlatformError || RequestError;

pub const Message = enum(u32) {
    toggle = 1,
    _,
};

pub const TimerID = enum(u32) {
    move = 1,
    _,
};

const binding = "Ctrl+Alt+M";
const move_interval_ms: u32 = 10 * 1000;
const name = "Phantom";
pub const offset_pixels_max: i32 = 50;
pub const offset_pixels_min: i32 = -50;

comptime {
    assert(binding.len > 0);
    assert(move_interval_ms > 0);
    assert(name.len > 0);
    assert(offset_pixels_max > 0);
    assert(offset_pixels_min < 0);
}

pub fn ApplicationType(comptime Libraries: type) type {
    comptime assert(@hasDecl(Libraries, "App"));
    comptime assert(@hasDecl(Libraries, "Client"));

    return struct {
        client: Client,
        logger: ?*const Logger,
        prng: std.Random.DefaultPrng,
        runtime: App,
        state: State,

        const Application = @This();
        const App = Libraries.App;
        const Client = Libraries.Client;

        pub fn init(application: *Application, logger: ?*const Logger) umbra.Error!void {
            if (logger) |held| assert(held.enabled(.information));

            try application.runtime.init(.{ .name = name, .tooltip = name });
            errdefer application.runtime.deinit();

            application.client = .{};
            application.logger = logger;
            application.prng = .init(application.runtime.now_ms());
            application.state = .inactive;

            try icon.register(App, &application.runtime.icons);
            try icon.show(App, &application.runtime.icons, application.state);

            menu.fill(App, &application.runtime.menu, application.state) catch {
                application.log("Unable to fill the menu");
            };

            assert(!application.runtime.is_running());
            assert(!application.client.is_connected());
            assert(!application.state.is_active());

            application.log("Application is ready");
        }

        pub fn deinit(application: *Application) void {
            application.log("Shutting down");

            application.client.disconnect();
            application.runtime.deinit();

            assert(!application.runtime.is_running());
            assert(!application.client.is_connected());
        }

        pub fn run(application: *Application) RunError!void {
            try application.runtime.bus.attach(Application, application);

            application.client.connect() catch |err| {
                application.log_error("Unable to connect to the input service", err);

                return err;
            };

            _ = application.client.bind(
                binding,
                .{ .consume = true },
                Application,
                application,
                on_toggle,
            ) catch |err| {
                application.log_error("Unable to bind the toggle hotkey", err);

                return err;
            };

            try application.runtime.run();
        }

        pub fn on_app_init(application: *Application) void {
            application.log("Initialized");
        }

        pub fn on_app_shutdown(application: *Application) void {
            application.log("Shutdown event received");

            if (!application.state.is_active()) {
                return;
            }

            application.runtime.timers.stop(@backingInt(TimerID.move)) catch {
                application.log("Unable to stop the move timer");

                return;
            };
        }

        pub fn on_custom(application: *Application, custom: Custom) void {
            switch (@as(Message, @fromBackingInt(@backingInt(custom.code)))) {
                .toggle => application.toggle_state(),
                _ => {},
            }
        }

        pub fn on_menu_select(application: *Application, selection: Selection) void {
            assert(selection.id <= umbra.limits.menu_item_id_max);

            switch (@as(Command, @fromBackingInt(selection.id))) {
                .toggle => application.toggle_state(),
                .exit => application.on_exit(),
                _ => {},
            }
        }

        pub fn on_timer_tick(application: *Application, tick: Tick) void {
            assert(tick.id <= umbra.limits.timer_id_max);

            switch (@as(TimerID, @fromBackingInt(tick.id))) {
                .move => application.move(),
                _ => {},
            }
        }

        fn activate(application: *Application) void {
            assert(!application.state.is_active());

            application.set_state(.active, "trigger activated");

            const mover = App.TimerSet.Timer{
                .id = @backingInt(TimerID.move),
                .interval_ms = move_interval_ms,
            };

            application.runtime.timers.start(mover) catch {
                application.log("Unable to start the move timer");

                return;
            };

            application.log("Move timer started");
        }

        fn deactivate(application: *Application) void {
            assert(application.state.is_active());

            application.set_state(.inactive, "trigger deactivated");

            application.runtime.timers.stop(@backingInt(TimerID.move)) catch {
                application.log("Unable to stop the move timer");

                return;
            };

            application.log("Move timer stopped");
        }

        fn move(application: *Application) void {
            assert(application.state.is_active());

            const random = application.prng.random();
            const minimum = offset_pixels_min;
            const maximum = offset_pixels_max;

            const offset = Position{
                .x = random.intRangeAtMost(i32, minimum, maximum),
                .y = random.intRangeAtMost(i32, minimum, maximum),
            };

            assert(offset.x >= minimum);
            assert(offset.x <= maximum);
            assert(offset.y >= minimum);
            assert(offset.y <= maximum);

            application.client.simulate_move(offset) catch |err| {
                application.log_error("Unable to move the mouse", err);

                return;
            };

            application.log("Moved mouse");
        }

        fn notify(application: *Application, value: State) void {
            const body = value.to_notification_body();

            application.runtime.notifier.send(.{ .body = body, .title = name }) catch {
                return;
            };
        }

        fn on_exit(application: *Application) void {
            application.log("Exiting");
            application.runtime.quit();
        }

        fn on_toggle(application: *Application, _: ?*const Key) void {
            _ = application.runtime.post(@fromBackingInt(@backingInt(Message.toggle)));
        }

        fn refresh_menu(application: *Application) void {
            menu.fill(App, &application.runtime.menu, application.state) catch {
                application.log("Unable to fill the menu");
            };

            application.runtime.menu.build() catch {
                return;
            };
        }

        fn set_state(application: *Application, value: State, reason: []const u8) void {
            assert(application.state != value);
            assert(reason.len > 0);

            application.state = value;

            icon.show(App, &application.runtime.icons, value) catch {
                application.log("Unable to show the tray icon");
            };

            application.refresh_menu();
            application.log_state(value, reason);
            application.notify(value);

            assert(application.state == value);
        }

        fn toggle_state(application: *Application) void {
            if (application.state.is_active()) {
                application.deactivate();

                return;
            }

            application.activate();
        }

        fn log(application: *Application, message: []const u8) void {
            assert(message.len > 0);

            if (application.logger) |logger| {
                logger.information(message, &.{}, &@src());
            }
        }

        fn log_error(application: *Application, message: []const u8, err: anyerror) void {
            assert(message.len > 0);

            if (application.logger) |logger| {
                logger.err(
                    message,
                    &.{.{ .key = "error", .value = .{ .string = @errorName(err) } }},
                    &@src(),
                );
            }
        }

        fn log_state(application: *Application, value: State, reason: []const u8) void {
            assert(application.state == value);
            assert(reason.len > 0);

            if (application.logger) |logger| {
                logger.information(
                    "State changed",
                    &.{
                        .{ .key = "state", .value = .{ .string = value.to_string() } },
                        .{ .key = "reason", .value = .{ .string = reason } },
                    },
                    &@src(),
                );
            }
        }
    };
}

const testing = std.testing;

test ApplicationType {
    const Libraries = struct {
        pub const App = umbra.AppType(umbra.Fake);
        pub const Client = nimble.RuntimeType(nimble.Fake).Client;
    };

    const Application = ApplicationType(Libraries);
    const application = try testing.allocator.create(Application);
    defer testing.allocator.destroy(application);

    try application.init(null);
    defer application.deinit();

    try testing.expectEqual(State.inactive, application.state);

    application.on_custom(.{ .code = @fromBackingInt(@backingInt(Message.toggle)) });

    try testing.expectEqual(State.active, application.state);
    try testing.expectEqualStrings("active", application.runtime.icons.get_current_name().?);

    application.on_menu_select(.{ .checked = false, .id = @backingInt(Command.toggle) });

    try testing.expectEqual(State.inactive, application.state);
    try testing.expectEqualStrings("inactive", application.runtime.icons.get_current_name().?);
}
