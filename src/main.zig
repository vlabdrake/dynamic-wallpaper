const std = @import("std");
const c = @cImport({
    @cInclude("time.h");
});

const Config = struct { symlink: []u8, wallpapers: [][]u8 };

fn load_config(allocator: std.mem.Allocator, path: []const u8) !Config {
    const data = try std.fs.cwd().readFileAlloc(allocator, path, 4096);
    defer allocator.free(data);

    const parsed = try std.json.parseFromSlice(Config, allocator, data, .{ .allocate = .alloc_always });
    // defer parsed.deinit();

    const config = parsed.value;
    return config;
}

fn set_background(allocator: std.mem.Allocator, path: []const u8) !void {
    const argv = [_][]const u8{ "swww", "img", path };
    var proc = try std.ChildProcess.exec(.{ .allocator = allocator, .argv = &argv });
    defer allocator.free(proc.stdout);
    defer allocator.free(proc.stderr);
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

    while (true) {
        const now = c.time(null);
        var tm = c.localtime(&now);
        tm.*.tm_hour = 0;
        tm.*.tm_min = 0;
        tm.*.tm_sec = 0;
        const midnight = c.mktime(tm);
        const seconds_since_midnight: usize = @intFromFloat(c.difftime(now, midnight));
        const expected_wallpaper = seconds_since_midnight / wallpaper_update_interval;
        if (expected_wallpaper != current_wallpaper) {
            current_wallpaper = expected_wallpaper;
            try std.fs.deleteFileAbsolute(config.symlink);
            try std.fs.symLinkAbsolute(config.wallpapers[current_wallpaper], config.symlink, .{});
            try set_background(allocator, config.symlink);
        }
        std.time.sleep(1 * std.time.ns_per_min);
    }
}
