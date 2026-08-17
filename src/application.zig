const std = @import("std");

const arc = @import("arc");
const umbra = @import("umbra");

const constant = @import("constant.zig");
const EventHandlerType = @import("handler.zig").EventHandlerType;
const IconManager = @import("icon.zig").IconManager;
const InputThread = @import("input.zig").InputThread;
const MenuManager = @import("menu.zig").MenuManager;
const NotificationManager = @import("notification.zig").NotificationManager;
const State = @import("state.zig").State;

const assert = std.debug.assert;

const App = umbra.App;
const Logger = arc.Logger;

pub const Error = error{
    InputUnavailable,
    RunFailed,
    SetupFailed,
};

pub const name = "Phantom";

comptime {
    assert(name.len > 0);
}

pub const Application = struct {
    app: App,
    icon: IconManager,
    input: InputThread,
    logger: ?*Logger,
    menu: MenuManager,
    notification: NotificationManager,
    random: std.Random.DefaultPrng,
    state: State,

    pub fn init(application: *Application, logger: ?*Logger) Error!void {
        application.app.init(.{
            .name = name,
            .tooltip = name,
            .initial_state = "inactive",
        }) catch {
            return Error.SetupFailed;
        };

        errdefer application.app.deinit();

        application.icon = IconManager.init(&application.app);
        application.input = InputThread.init();
        application.logger = logger;
        application.menu = MenuManager.init(&application.app);
        application.notification = NotificationManager.init(&application.app, true);
        application.random = std.Random.DefaultPrng.init(umbra.time.now_ms());
        application.state = .inactive;

        application.icon.configure() catch {
            return Error.SetupFailed;
        };

        application.menu.build(application.state);

        _ = application.app.configure();

        assert(!application.app.is_running());
        assert(!application.state.is_active());

        application.log("Application is ready");
    }

    pub fn deinit(application: *Application) void {
        application.log("Shutting down");

        application.input.deinit();
        application.app.deinit();

        assert(!application.app.is_running());
    }

    pub fn run(application: *Application) Error!void {
        EventHandlerType(Application).register(&application.app.bus, application);

        application.input.start() catch |err| {
            application.log_error("Unable to start the input hook", err);

            return Error.InputUnavailable;
        };

        application.app.run() catch |err| {
            application.log_error("Unable to run the application", err);

            return Error.RunFailed;
        };
    }

    pub fn on_custom(application: *Application, code: u32) void {
        if (code == constant.Message.toggle) {
            application.toggle_state();
        }
    }

    pub fn on_icon_change(application: *Application, icon_name: []const u8) void {
        assert(icon_name.len > 0);

        const handle = application.app.icon.get(icon_name) orelse return;

        application.app.tray.set_icon(handle) catch {
            application.log("Unable to update the tray icon");

            return;
        };
    }

    pub fn on_init(application: *Application) void {
        application.log("Initialized");
    }

    pub fn on_menu_select(application: *Application, id: u32) void {
        switch (id) {
            constant.Menu.toggle => application.toggle_state(),
            constant.Menu.exit => application.on_exit(),
            else => {},
        }
    }

    pub fn on_shutdown(application: *Application) void {
        application.log("Shutdown event received");

        if (!application.state.is_active()) {
            return;
        }

        application.app.timer.stop(constant.Timer.move_id) catch {
            application.log("Unable to stop the move timer");

            return;
        };
    }

    pub fn on_timer_tick(application: *Application, timer_id: u32) void {
        if (timer_id == constant.Timer.move_id) {
            application.move();
        }
    }

    fn activate(application: *Application) void {
        assert(!application.state.is_active());

        application.set_state(.active, "trigger activated");

        _ = application.app.timer.start(
            constant.Timer.move_id,
            constant.Timer.move_interval_ms,
        ) catch {
            application.log("Unable to start the move timer");

            return;
        };

        application.log("Move timer started");
    }

    fn deactivate(application: *Application) void {
        assert(application.state.is_active());

        application.set_state(.inactive, "trigger deactivated");

        application.app.timer.stop(constant.Timer.move_id) catch {
            application.log("Unable to stop the move timer");

            return;
        };

        application.log("Move timer stopped");
    }

    fn move(application: *Application) void {
        assert(application.state.is_active());

        const random = application.random.random();

        const offset_x = random.intRangeAtMost(
            i32,
            constant.Movement.offset_min,
            constant.Movement.offset_max,
        );

        const offset_y = random.intRangeAtMost(
            i32,
            constant.Movement.offset_min,
            constant.Movement.offset_max,
        );

        assert(offset_x >= constant.Movement.offset_min);
        assert(offset_x <= constant.Movement.offset_max);
        assert(offset_y >= constant.Movement.offset_min);
        assert(offset_y <= constant.Movement.offset_max);

        application.input.move_relative(offset_x, offset_y);

        application.log("Moved mouse");
    }

    fn on_exit(application: *Application) void {
        application.log("Exiting");
        application.app.quit();
    }

    fn set_state(application: *Application, value: State, reason: []const u8) void {
        assert(reason.len > 0);

        application.state = value;

        application.icon.update(value);
        application.menu.build(value);
        application.menu.push();
        application.log_state(value, reason);
        application.notification.show(value);

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
            logger.info(message, &.{}, @src());
        }
    }

    fn log_error(application: *Application, message: []const u8, err: anyerror) void {
        assert(message.len > 0);

        if (application.logger) |logger| {
            logger.@"error"(message, &.{arc.err_from(err)}, @src());
        }
    }

    fn log_state(application: *Application, value: State, reason: []const u8) void {
        assert(reason.len > 0);

        if (application.logger) |logger| {
            logger.info(
                "State changed",
                &.{ arc.string("state", value.to_string()), arc.string("reason", reason) },
                @src(),
            );
        }
    }
};
