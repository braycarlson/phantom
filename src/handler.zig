const std = @import("std");

const wisp = @import("wisp");

const constant = @import("constant.zig");

const App = wisp.App;
const Event = wisp.Event;
const Response = wisp.Response;

pub const Dispatcher = struct {
    on_exit: *const fn () void,
    on_init: *const fn () void,
    on_menu_show: *const fn () void,
    on_shutdown: *const fn () void,
    on_timer_tick: *const fn (u32) void,
    on_toggle_state: *const fn () void,
};

pub const EventHandler = struct {
    app: *App,
    dispatcher: *const Dispatcher,

    pub fn init(app: *App, dispatcher: *const Dispatcher) EventHandler {
        return EventHandler{
            .app = app,
            .dispatcher = dispatcher,
        };
    }

    pub fn register(self: *EventHandler) void {
        _ = self.app.event_bus().on(.app_init, on_app_init, self);
        _ = self.app.event_bus().on(.app_shutdown, on_app_shutdown, self);
        _ = self.app.event_bus().on(.icon_change, on_icon_change, self);
        _ = self.app.event_bus().on(.menu_select, on_menu_select, self);
        _ = self.app.event_bus().on(.menu_show, on_menu_show, self);
        _ = self.app.event_bus().on(.taskbar_restart, on_taskbar_restart, self);
        _ = self.app.event_bus().on(.timer_tick, on_timer_tick, self);
        _ = self.app.event_bus().on(.tray_left_click, on_tray_click, self);
        _ = self.app.event_bus().on(.tray_right_click, on_tray_click, self);
    }
};

fn on_app_init(event: *const Event, context: ?*anyopaque) Response {
    _ = event;

    const handler: *EventHandler = @ptrCast(@alignCast(context.?));
    handler.dispatcher.on_init();

    return .pass;
}

fn on_app_shutdown(event: *const Event, context: ?*anyopaque) Response {
    _ = event;

    const handler: *EventHandler = @ptrCast(@alignCast(context.?));
    handler.dispatcher.on_shutdown();

    return .pass;
}

fn on_icon_change(event: *const Event, context: ?*anyopaque) Response {
    const handler: *EventHandler = @ptrCast(@alignCast(context.?));
    const data = event.payload.icon_change;

    const icon = handler.app.get_icon().get(data.name) orelse return .pass;

    handler.app.get_tray().set_icon(icon) catch {};

    return .pass;
}

fn on_menu_select(event: *const Event, context: ?*anyopaque) Response {
    const handler: *EventHandler = @ptrCast(@alignCast(context.?));
    const data = event.payload.menu_select;

    handle_command(handler, data.id);

    return .pass;
}

fn on_menu_show(event: *const Event, context: ?*anyopaque) Response {
    _ = event;

    const handler: *EventHandler = @ptrCast(@alignCast(context.?));
    handler.dispatcher.on_menu_show();

    return .pass;
}

fn on_taskbar_restart(event: *const Event, context: ?*anyopaque) Response {
    _ = event;
    _ = context;

    return .pass;
}

fn on_timer_tick(event: *const Event, context: ?*anyopaque) Response {
    const handler: *EventHandler = @ptrCast(@alignCast(context.?));
    const data = event.payload.timer_tick;

    handler.dispatcher.on_timer_tick(data.id);

    return .pass;
}

fn on_tray_click(event: *const Event, context: ?*anyopaque) Response {
    _ = event;
    _ = context;

    return .pass;
}

fn handle_command(handler: *EventHandler, command: u32) void {
    switch (command) {
        constant.Menu.toggle => handler.dispatcher.on_toggle_state(),
        constant.Menu.exit => handler.dispatcher.on_exit(),
        else => {},
    }
}
