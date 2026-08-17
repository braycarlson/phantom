const std = @import("std");

const nimble = @import("nimble");
const umbra = @import("umbra");

const constant = @import("constant.zig");

const assert = std.debug.assert;

const Client = nimble.remote.Client;
const Key = nimble.Key;

pub const Error = error{
    ConnectFailed,
    HookFailed,
};

pub const binding = "Ctrl+Alt+M";

comptime {
    assert(binding.len > 0);
}

pub const InputThread = struct {
    client: Client,

    pub fn init() InputThread {
        return InputThread{ .client = .{} };
    }

    pub fn deinit(thread: *InputThread) void {
        thread.stop();
    }

    pub fn start(thread: *InputThread) Error!void {
        thread.client.connect() catch {
            return Error.ConnectFailed;
        };

        errdefer thread.client.disconnect();

        _ = thread.client.bind_pattern(binding, .{ .consume = true }, on_toggle, thread) catch {
            return Error.HookFailed;
        };
    }

    pub fn stop(thread: *InputThread) void {
        thread.client.disconnect();

        assert(!thread.client.is_connected());
    }

    pub fn is_running(thread: *const InputThread) bool {
        return thread.client.is_connected();
    }

    pub fn move_relative(thread: *InputThread, offset_x: i32, offset_y: i32) void {
        thread.client.simulate_move(offset_x, offset_y);
    }
};

fn on_toggle(_: ?*anyopaque, _: ?*const Key) void {
    _ = umbra.loop.post(constant.Message.toggle);
}

const testing = std.testing;

test "an input thread starts disconnected" {
    var input = InputThread.init();
    defer input.deinit();

    try testing.expect(!input.is_running());
}

test "stopping an unstarted input thread is inert" {
    var input = InputThread.init();
    defer input.deinit();

    input.stop();

    try testing.expect(!input.is_running());
}
