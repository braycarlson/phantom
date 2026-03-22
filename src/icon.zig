const std = @import("std");

const wisp = @import("wisp");

const constant = @import("constant.zig");
const State = @import("state.zig").State;

const App = wisp.App;
const Icon = wisp.Icon;
const IconBuilder = wisp.IconBuilder;

pub const IconManager = struct {
    app: *App,

    pub fn init(app: *App) IconManager {
        return IconManager{
            .app = app,
        };
    }

    pub fn configure(self: *IconManager) void {
        _ = IconBuilder.init(self.app.get_icon())
            .resource("active", constant.Resource.active_icon)
            .resource("inactive", constant.Resource.inactive_icon)
            .system("active_fallback", .application)
            .system("inactive_fallback", .shield)
            .done();

        self.app.get_icon().set_current("inactive") catch {
            self.app.get_icon().set_current("inactive_fallback") catch {};
        };
    }

    pub fn get_icon_for_state(self: *IconManager, value: State) ?*const Icon {
        return self.app.get_icon().get(value.to_string());
    }

    pub fn update(self: *IconManager, value: State) void {
        const icon_name = value.to_string();
        const fallback_name = if (value.is_active()) "active_fallback" else "inactive_fallback";

        self.app.get_icon().set_current(icon_name) catch {
            self.app.get_icon().set_current(fallback_name) catch {};
        };

        const icon = self.app.get_icon().get_current() orelse return;

        self.app.get_tray().set_icon(icon) catch {};
    }
};
