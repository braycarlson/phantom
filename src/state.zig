pub const State = enum(u8) {
    active = 0,
    inactive = 1,

    pub fn is_active(self: State) bool {
        return self == .active;
    }

    pub fn toggle(self: State) State {
        return switch (self) {
            .active => .inactive,
            .inactive => .active,
        };
    }

    pub fn to_string(self: State) []const u8 {
        return switch (self) {
            .active => "active",
            .inactive => "inactive",
        };
    }

    pub fn to_action_string(self: State) []const u8 {
        return switch (self) {
            .active => "Deactivate",
            .inactive => "Activate",
        };
    }
};
