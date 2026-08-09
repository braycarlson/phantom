const std = @import("std");

const wisp = @import("wisp");

const State = @import("state.zig").State;

const assert = std.debug.assert;

const App = wisp.App;

pub const title = "Phantom";

comptime {
    assert(title.len > 0);
}

pub const NotificationManager = struct {
    app: *App,
    enabled: bool,

    pub fn init(app: *App, enabled: bool) NotificationManager {
        const result = NotificationManager{
            .app = app,
            .enabled = enabled,
        };

        return result;
    }

    pub fn set_enabled(manager: *NotificationManager, value: bool) void {
        manager.enabled = value;

        assert(manager.enabled == value);
    }

    pub fn show(manager: *NotificationManager, value: State) void {
        if (!manager.enabled) {
            return;
        }

        const body = body_of(value);

        assert(body.len > 0);

        manager.app.notification.send_simple(title, body) catch {
            return;
        };
    }
};

fn body_of(value: State) []const u8 {
    const result = switch (value) {
        .active => "Phantom is active",
        .inactive => "Phantom is inactive",
    };

    assert(result.len > 0);

    return result;
}

const testing = std.testing;

test "every state carries a distinct notification body" {
    try testing.expectEqualStrings("Phantom is active", body_of(.active));
    try testing.expectEqualStrings("Phantom is inactive", body_of(.inactive));
    try testing.expect(!std.mem.eql(u8, body_of(.active), body_of(.inactive)));
}
