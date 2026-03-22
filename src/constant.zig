pub const Menu = struct {
    pub const toggle: u32 = 1;
    pub const exit: u32 = 2;
};

pub const Resource = struct {
    pub const active_icon: u32 = 101;
    pub const inactive_icon: u32 = 102;
};

pub const Timer = struct {
    pub const move_id: u32 = 1;
    pub const move_interval_ms: u32 = 10 * 1000;
};

pub const Movement = struct {
    pub const offset_min: i32 = -50;
    pub const offset_max: i32 = 50;
};
