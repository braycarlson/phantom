pub const Icon = struct {
    pub const dimension: u32 = 32;
};

pub const Menu = struct {
    pub const toggle: u32 = 1001;
    pub const exit: u32 = 1002;
};

pub const Message = struct {
    pub const toggle: u32 = 1;
};

pub const Movement = struct {
    pub const offset_max: i32 = 50;
    pub const offset_min: i32 = -50;
};

pub const Timer = struct {
    pub const move_id: u32 = 1;
    pub const move_interval_ms: u32 = 10 * 1000;
};
