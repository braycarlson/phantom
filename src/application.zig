const std = @import("std");

const nimble = @import("nimble");
const w32 = @import("win32").everything;
const wisp = @import("wisp");

const constant = @import("constant.zig");
const Dispatcher = @import("handler.zig").Dispatcher;
const EventHandler = @import("handler.zig").EventHandler;
const IconManager = @import("icon.zig").IconManager;
const Logger = @import("logger.zig").Logger;
const MenuManager = @import("menu.zig").MenuManager;
const NotificationManager = @import("notification.zig").NotificationManager;
const State = @import("state.zig").State;

const App = wisp.App;
const Key = nimble.Key;
const Response = nimble.Response;
const Keyboard = nimble.Keyboard(.{});
const Mouse = nimble.Mouse(.{});

var instance: std.atomic.Value(?*Application) = std.atomic.Value(?*Application).init(null);

const dispatcher = Dispatcher{
    .on_exit = dispatch_exit,
    .on_init = dispatch_init,
    .on_menu_show = dispatch_menu_show,
    .on_shutdown = dispatch_shutdown,
    .on_timer_tick = dispatch_timer_tick,
    .on_toggle_state = dispatch_toggle_state,
};

pub const Application = struct {
    app: App,
    handler: EventHandler,
    icon: IconManager,
    keyboard: Keyboard,
    logger: ?*Logger,
    menu: MenuManager,
    mouse: Mouse,
    notification: NotificationManager,
    random: std.Random.DefaultPrng,
    state: State,

    pub fn init(self: *Application, logger: ?*Logger) void {
        self.* = Application{
            .app = undefined,
            .handler = undefined,
            .icon = undefined,
            .keyboard = Keyboard.init(),
            .logger = logger,
            .menu = undefined,
            .mouse = Mouse.init(),
            .notification = undefined,
            .random = std.Random.DefaultPrng.init(w32.GetTickCount64()),
            .state = .inactive,
        };

        self.app.init(.{
            .name = "Phantom",
            .tooltip = "Phantom",
            .initial_state = "inactive",
        });

        _ = self.app.configure();
    }

    pub fn configure(self: *Application) !void {
        self.icon = IconManager.init(&self.app);
        self.icon.configure();

        self.menu = MenuManager.init(&self.app);

        self.notification = NotificationManager.init(
            &self.app,
            &self.icon,
            true,
        );

        self.handler = EventHandler.init(&self.app, &dispatcher);

        _ = try self.keyboard.registry.register(
            'M',
            nimble.Modifier.from(.{ .ctrl = true, .alt = true }),
            toggle_bind_wrapper,
            self,
            .{ .block_exempt = true },
        );

        self.log("Application is ready");
    }

    pub fn deinit(self: *Application) void {
        self.log("Shutting down");

        instance.store(null, .seq_cst);

        self.keyboard.deinit();
        self.mouse.deinit();
        self.app.deinit();
    }

    pub fn run(self: *Application) void {
        instance.store(self, .seq_cst);

        self.configure() catch |err| {
            self.log_error("Failed to configure application", err);
            return;
        };

        self.handler.register();

        self.app.run() catch |err| {
            self.log_error("Failed to run application", err);
        };
    }

    fn activate(self: *Application) void {
        std.debug.assert(!self.state.is_active());

        self.set_state(.active, "trigger activated");

        _ = self.app.get_timer().start(
            constant.Timer.move_id,
            constant.Timer.move_interval_ms,
        ) catch {
            self.log("Failed to start move timer");
            return;
        };

        self.log("Move timer started");
    }

    fn deactivate(self: *Application) void {
        std.debug.assert(self.state.is_active());

        self.set_state(.inactive, "trigger activated");

        self.app.get_timer().stop(constant.Timer.move_id) catch {};

        self.log("Move timer stopped");
    }

    fn move(self: *Application) void {
        std.debug.assert(self.state.is_active());

        const random = self.random.random();

        const dx = random.intRangeAtMost(i32, constant.Movement.offset_min, constant.Movement.offset_max);
        const dy = random.intRangeAtMost(i32, constant.Movement.offset_min, constant.Movement.offset_max);

        std.debug.assert(dx >= constant.Movement.offset_min and dx <= constant.Movement.offset_max);
        std.debug.assert(dy >= constant.Movement.offset_min and dy <= constant.Movement.offset_max);

        _ = self.mouse.move_relative(dx, dy);

        self.log("Moved mouse");
    }

    fn log(self: *Application, message: []const u8) void {
        if (self.logger) |logger| {
            logger.log("{s}", .{message});
        }
    }

    fn log_error(self: *Application, message: []const u8, err: anyerror) void {
        if (self.logger) |logger| {
            logger.log("{s}: {}", .{ message, err });
        }
    }

    fn log_state(self: *Application, value: State, reason: []const u8) void {
        if (self.logger) |logger| {
            logger.log("State changed to {s} ({s})", .{ value.to_string(), reason });
        }
    }

    fn on_exit(self: *Application) void {
        self.log("Exiting");
        self.app.quit();
    }

    fn on_init(self: *Application) void {
        self.keyboard.start() catch {
            self.log("Unable to start keyboard hook");
        };

        self.log("Initialized");
    }

    fn on_menu_show(self: *Application) void {
        self.menu.build(self.state);
    }

    fn on_shutdown(self: *Application) void {
        self.log("Shutdown event received");

        if (self.state.is_active()) {
            self.app.get_timer().stop(constant.Timer.move_id) catch {};
        }
    }

    fn on_timer_tick(self: *Application, timer_id: u32) void {
        if (timer_id == constant.Timer.move_id) {
            self.move();
        }
    }

    fn on_toggle_state(self: *Application) void {
        self.toggle_state();
    }

    fn set_state(self: *Application, value: State, reason: []const u8) void {
        self.state = value;

        self.icon.update(value);
        self.log_state(value, reason);
        self.notification.show(value);
    }

    fn toggle_state(self: *Application) void {
        if (self.state.is_active()) {
            self.deactivate();
        } else {
            self.activate();
        }
    }
};

fn toggle_bind_wrapper(ctx: *anyopaque, key: *const Key) Response {
    _ = key;
    const self: *Application = @ptrCast(@alignCast(ctx));

    self.toggle_state();

    return .consume;
}

fn current() ?*Application {
    return instance.load(.seq_cst);
}

fn dispatch_exit() void {
    const app = current() orelse return;
    app.on_exit();
}

fn dispatch_init() void {
    const app = current() orelse return;
    app.on_init();
}

fn dispatch_menu_show() void {
    const app = current() orelse return;
    app.on_menu_show();
}

fn dispatch_shutdown() void {
    const app = current() orelse return;
    app.on_shutdown();
}

fn dispatch_timer_tick(timer_id: u32) void {
    const app = current() orelse return;
    app.on_timer_tick(timer_id);
}

fn dispatch_toggle_state() void {
    const app = current() orelse return;
    app.on_toggle_state();
}
