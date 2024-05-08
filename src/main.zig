const std = @import("std");
const dt = @import("datetime.zig");

const ColorScheme = enum { Light, Dark };

const Config = struct {
    symlink: []u8,
    wallpapers: [][]u8,

    fn fromFile(allocator: std.mem.Allocator, path: []const u8) !Config {
        const data = try std.fs.cwd().readFileAlloc(allocator, path, 4096);
        defer allocator.free(data);

        const parsed = try std.json.parseFromSlice(Config, allocator, data, .{ .allocate = .alloc_always });
        defer parsed.deinit();

        var config = Config{ .symlink = undefined, .wallpapers = undefined };
        config.symlink = try allocator.alloc(u8, parsed.value.symlink.len);
        @memcpy(config.symlink, parsed.value.symlink);

        config.wallpapers = try allocator.alloc([]u8, parsed.value.wallpapers.len);
        for (0..config.wallpapers.len) |i| {
            config.wallpapers[i] = try allocator.alloc(u8, parsed.value.wallpapers[i].len);
            @memcpy(config.wallpapers[i], parsed.value.wallpapers[i]);
        }
        return config;
    }

    fn deinit(self: *const Config, allocator: std.mem.Allocator) void {
        allocator.free(self.symlink);

        for (0..self.wallpapers.len) |i| {
            allocator.free(self.wallpapers[i]);
        }

        allocator.free(self.wallpapers);
    }
};

fn runCommand(allocator: std.mem.Allocator, argv: []const []const u8) !void {
    const proc = try std.ChildProcess.run(.{ .allocator = allocator, .argv = argv });
    defer allocator.free(proc.stdout);
    defer allocator.free(proc.stderr);
}

fn setBackground(allocator: std.mem.Allocator, path: []const u8) !void {
    const argv = [_][]const u8{ "swww", "img", path };
    try runCommand(allocator, &argv);
}

const GTK = struct {
    light_theme: []u8,
    dark_theme: []u8,

    fn setTheme(self: *GTK, allocator: std.mem.Allocator, scheme: ColorScheme) !void {
        try self.setGtkTheme(allocator, scheme);
        try self.setColorScheme(allocator, scheme);
    }

    fn setGtkTheme(self: *GTK, allocator: std.mem.Allocator, scheme: ColorScheme) !void {
        const theme = switch (scheme) {
            ColorScheme.Light => self.light_theme,
            ColorScheme.Dark => self.dark_theme,
        };
        const argv = [_][]const u8{ "gsettings", "set", "org.gnome.desktop.interface", "gtk-theme", theme };
        try runCommand(allocator, &argv);
    }

    fn setColorScheme(_: *GTK, allocator: std.mem.Allocator, scheme: ColorScheme) !void {
        const scheme_str = switch (scheme) {
            ColorScheme.Light => "prefer-light",
            ColorScheme.Dark => "prefer-dark",
        };
        const argv = [_][]const u8{ "gsettings", "set", "org.gnome.desktop.interface", "color-scheme", scheme_str };
        try runCommand(allocator, argv);
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const config_path: []const u8 = args[1];

    const config = try Config.fromFile(allocator, config_path);
    defer config.deinit(allocator);

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
        try setBackground(allocator, config.symlink);
    }
    const time_to_next_change: i64 = @intCast(wallpaper_update_interval - seconds_since_midnight % wallpaper_update_interval);
    const next_change_ts = now.timestamp() + time_to_next_change;

    var buf: [16]u8 = undefined;
    const ts = try std.fmt.bufPrint(&buf, "@{}", .{next_change_ts});

    var set_timer_command = std.ArrayList([]const u8).init(allocator);
    defer set_timer_command.deinit();
    try set_timer_command.appendSlice(&[_][]const u8{
        "systemd-run",
        "--user",
        "--on-calendar",
        ts,
        "--timer-property=AccuracySec=1us",
    });
    for (args) |arg| {
        try set_timer_command.append(arg);
    }
    try runCommand(allocator, set_timer_command.items);
}
