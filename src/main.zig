const std = @import("std");
const dt = @import("datetime.zig");

const Config = struct { symlink: []u8, wallpapers: [][]u8 };

fn load_config(allocator: std.mem.Allocator, path: []const u8) !Config {
    const data = try std.fs.cwd().readFileAlloc(allocator, path, 4096);
    defer allocator.free(data);

    const parsed = try std.json.parseFromSlice(Config, allocator, data, .{ .allocate = .alloc_always });
    // defer parsed.deinit();

    const config = parsed.value;
    return config;
}

fn run_command(allocator: std.mem.Allocator, argv: []const []const u8) !void {
    var proc = try std.ChildProcess.exec(.{ .allocator = allocator, .argv = argv });
    defer allocator.free(proc.stdout);
    defer allocator.free(proc.stderr);
}

fn set_background(allocator: std.mem.Allocator, path: []const u8) !void {
    const argv = [_][]const u8{ "swww", "img", path };
    try run_command(allocator, &argv);
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var config_path: []const u8 = args[1];

    const config = try load_config(allocator, config_path);
    const wallpaper_update_interval = 86400 / config.wallpapers.len;
    var current_wallpaper: usize = undefined;

    const now = dt.DateTime.now();
    const midnight = now.replace(.{ .hour = 0, .minute = 0, .second = 0 });

    const seconds_since_midnight: usize = @intCast(now.timestamp() - midnight.timestamp());
    const expected_wallpaper = seconds_since_midnight / wallpaper_update_interval;
    if (expected_wallpaper != current_wallpaper) {
        current_wallpaper = expected_wallpaper;
        try std.fs.deleteFileAbsolute(config.symlink);
        try std.fs.symLinkAbsolute(config.wallpapers[current_wallpaper], config.symlink, .{});
        try set_background(allocator, config.symlink);
    }
    const time_to_next_change: i64 = @intCast(wallpaper_update_interval - seconds_since_midnight % wallpaper_update_interval);
    var next_change_ts = now.timestamp() + time_to_next_change;
    var set_timer_command = std.ArrayList([]const u8).init(allocator);
    try set_timer_command.appendSlice(&[_][]const u8{
        "systemd-run",
        "--user",
        "--on-calendar",
        try std.fmt.allocPrint(allocator, "@{}", .{next_change_ts}),
        "--timer-property=AccuracySec=1us",
    });
    for (args) |arg| {
        try set_timer_command.append(arg);
    }
    try run_command(allocator, set_timer_command.items);
}
