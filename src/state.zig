const std = @import("std");

pub const State = enum(u8) {
    active = 0,
    inactive = 1,

    pub fn is_active(state: State) bool {
        return state == .active;
    }

    pub fn to_label(state: State) []const u8 {
        return switch (state) {
            .active => "Deactivate",
            .inactive => "Activate",
        };
    }

    pub fn to_notification_body(state: State) []const u8 {
        return switch (state) {
            .active => "Phantom is active",
            .inactive => "Phantom is inactive",
        };
    }

    pub fn to_string(state: State) []const u8 {
        return switch (state) {
            .active => "active",
            .inactive => "inactive",
        };
    }
};

const testing = std.testing;

test State {
    const states = [_]State{ .active, .inactive };

    for (states) |state| {
        try testing.expect(state.to_label().len > 0);
        try testing.expect(state.to_notification_body().len > 0);
        try testing.expect(state.to_string().len > 0);
    }

    try testing.expect(State.active.is_active());
    try testing.expect(!State.inactive.is_active());
    try testing.expectEqualStrings("Activate", State.inactive.to_label());
    try testing.expectEqualStrings("Phantom is active", State.active.to_notification_body());
    try testing.expectEqualStrings("inactive", State.inactive.to_string());

    try testing.expect(!std.mem.eql(
        u8,
        State.active.to_notification_body(),
        State.inactive.to_notification_body(),
    ));
}
