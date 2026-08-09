pub const State = enum(u8) {
    active = 0,
    inactive = 1,

    pub fn is_active(state: State) bool {
        return state == .active;
    }

    pub fn toggle(state: State) State {
        return switch (state) {
            .active => .inactive,
            .inactive => .active,
        };
    }

    pub fn to_string(state: State) []const u8 {
        return switch (state) {
            .active => "active",
            .inactive => "inactive",
        };
    }

    pub fn to_action_string(state: State) []const u8 {
        return switch (state) {
            .active => "Deactivate",
            .inactive => "Activate",
        };
    }
};
