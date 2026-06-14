const std = @import("std");
const path_util = @import("path.zig");
const nimble = @import("nimble");

pub const backup_count_max: u32 = 5;
pub const buffer_size: u32 = 4096;
pub const path_length_max: u32 = 512;

pub const RotationPolicy = union(enum) {
    both: usize,
    daily: void,
    size: usize,
};

pub const Date = struct {
    day: u5,
    month: u4,
    year: u16,

    pub fn current() Date {
        var threaded: std.Io.Threaded = .init_single_threaded;
        const io = threaded.io();
        const timestamp = std.Io.Timestamp.now(io, .real).toSeconds();
        std.debug.assert(timestamp >= 0);

        const datetime = std.time.epoch.EpochSeconds{ .secs = @intCast(timestamp) };
        const day = datetime.getEpochDay();
        const year_day = day.calculateYearDay();
        const month_day = year_day.calculateMonthDay();

        return Date{
            .year = year_day.year,
            .month = month_day.month.numeric(),
            .day = month_day.day_index + 1,
        };
    }

    pub fn eql(self: *const Date, other: *const Date) bool {
        return self.year == other.year and self.month == other.month and self.day == other.day;
    }
};

pub const LoggerError = error{
    InvalidPath,
    DirectoryCreationFailed,
    FileOpenFailed,
    StatFailed,
    SeekFailed,
    RotationFailed,
    FormatFailed,
    WriteFailed,
};

pub const Logger = struct {
    current_size: u32 = 0,
    file: ?std.Io.File = null,
    last_date: ?Date = null,
    mutex: nimble.Mutex = .{},
    path: [path_length_max]u8 = undefined,
    path_length: u32 = 0,
    policy: RotationPolicy = .{ .size = 5 * 1024 * 1024 },
    write_error: u32 = 0,

    pub const Options = struct {
        size: usize = 5 * 1024 * 1024,
    };

    pub fn init(options: Options) LoggerError!Logger {
        var logger = Logger{
            .policy = .{ .size = options.size },
        };

        try logger.load_path();
        try logger.open_file();

        logger.last_date = Date.current();

        return logger;
    }

    pub fn deinit(self: *Logger) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.file) |file| {
            var threaded: std.Io.Threaded = .init_single_threaded;
            const io = threaded.io();
            file.close(io);
            self.file = null;
        }
    }

    pub fn log(self: *Logger, comptime format: []const u8, argument: anytype) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        self.check_rotation();

        var buffer: [buffer_size]u8 = undefined;
        const content = self.format_message(&buffer, format, argument) catch return;

        self.write_to_file(content);
    }

    fn check_rotation(self: *Logger) void {
        const needs_rotation = switch (self.policy) {
            .size => |max_size| self.current_size >= @as(u32, @intCast(max_size)),
            .daily => self.has_date_changed(),
            .both => |max_size| self.current_size >= @as(u32, @intCast(max_size)) or self.has_date_changed(),
        };

        if (needs_rotation) {
            self.rotate() catch {};
        }
    }

    fn format_message(self: *Logger, buffer: *[buffer_size]u8, comptime format: []const u8, argument: anytype) LoggerError![]const u8 {
        _ = self;

        var writer = std.Io.Writer.fixed(buffer);

        write_timestamp(&writer) catch {
            return LoggerError.FormatFailed;
        };

        writer.print(format ++ "\n", argument) catch {
            return LoggerError.FormatFailed;
        };

        return writer.buffered();
    }

    fn get_path_slice(self: *const Logger) []const u8 {
        std.debug.assert(self.path_length > 0);
        std.debug.assert(self.path_length <= path_length_max);

        return self.path[0..self.path_length];
    }

    fn has_date_changed(self: *const Logger) bool {
        const today = Date.current();

        if (self.last_date) |last| {
            return !today.eql(&last);
        }

        return false;
    }

    fn load_path(self: *Logger) LoggerError!void {
        var buffer: [path_length_max]u8 = undefined;

        const base = path_util.get_appdata_path(&buffer, "phantom") catch {
            return LoggerError.InvalidPath;
        };

        const full_path = path_util.join_path(&self.path, base, "phantom.log") orelse {
            return LoggerError.InvalidPath;
        };

        self.path_length = @intCast(full_path.len);
    }

    fn open_file(self: *Logger) LoggerError!void {
        std.debug.assert(self.path_length > 0);

        var threaded: std.Io.Threaded = .init_single_threaded;
        const io = threaded.io();

        const path = self.get_path_slice();
        const directory = std.fs.path.dirname(path) orelse {
            return LoggerError.InvalidPath;
        };

        std.Io.Dir.createDirAbsolute(io, directory, .default_dir) catch |err| {
            if (err != error.PathAlreadyExists) {
                return LoggerError.DirectoryCreationFailed;
            }
        };

        self.file = std.Io.Dir.createFileAbsolute(io, path, .{ .read = true, .truncate = false }) catch {
            return LoggerError.FileOpenFailed;
        };

        const stat = self.file.?.stat(io) catch {
            return LoggerError.StatFailed;
        };

        self.current_size = @intCast(stat.size);
    }

    fn rotate(self: *Logger) LoggerError!void {
        var threaded: std.Io.Threaded = .init_single_threaded;
        const io = threaded.io();

        if (self.file) |file| {
            file.close(io);
            self.file = null;
        }

        self.current_size = 0;
        self.last_date = Date.current();

        const path = self.get_path_slice();

        var backup_path: [path_length_max]u8 = undefined;
        const backup = std.fmt.bufPrint(&backup_path, "{s}.1", .{path}) catch {
            return LoggerError.RotationFailed;
        };

        std.Io.Dir.deleteFileAbsolute(io, backup) catch {};
        std.Io.Dir.renameAbsolute(path, backup, io) catch {};

        self.open_file() catch {
            return LoggerError.FileOpenFailed;
        };
    }

    fn write_timestamp(writer: anytype) !void {
        var threaded: std.Io.Threaded = .init_single_threaded;
        const io = threaded.io();
        const timestamp = std.Io.Timestamp.now(io, .real).toSeconds();
        std.debug.assert(timestamp >= 0);

        const datetime = std.time.epoch.EpochSeconds{ .secs = @intCast(timestamp) };
        const day = datetime.getEpochDay();
        const year_day = day.calculateYearDay();
        const month_day = year_day.calculateMonthDay();
        const day_seconds = datetime.getDaySeconds();

        try writer.print("[{d:0>4}-{d:0>2}-{d:0>2} {d:0>2}:{d:0>2}:{d:0>2}] ", .{
            year_day.year,
            month_day.month.numeric(),
            month_day.day_index + 1,
            day_seconds.getHoursIntoDay(),
            day_seconds.getMinutesIntoHour(),
            day_seconds.getSecondsIntoMinute(),
        });
    }

    fn write_to_file(self: *Logger, content: []const u8) void {
        std.debug.assert(content.len > 0);

        const file = self.file orelse return;
        const length: u32 = @intCast(content.len);

        var threaded: std.Io.Threaded = .init_single_threaded;
        const io = threaded.io();

        file.writePositionalAll(io, content, self.current_size) catch {
            self.write_error += 1;
            return;
        };

        file.sync(io) catch {
            self.write_error += 1;
        };

        self.current_size += length;
    }
};
