pub const State = enum(u8) {
    active = 0,
    inactive = 1,

    pub fn is_active(self: State) bool {
        return self == .active;
    }

    pub fn toggle(self: State) State {
        return if (self == .active) State.inactive else State.active;
    }

    pub fn to_string(self: State) []const u8 {
        return if (self == .active) "active" else "inactive";
    }

    pub fn to_action_string(self: State) []const u8 {
        return if (self == .active) "Deactivate" else "Activate";
    }
};
