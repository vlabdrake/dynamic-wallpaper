const std = @import("std");
const dt = @import("datetime.zig");
const c = @cImport(@cInclude("stdlib.h"));

const ColorScheme = enum { Light, Dark };

const Config = struct {
    symlink: []u8,
    wallpapers: [][]u8,
    gtk: GTK,
};

const GTK = struct {
    light_theme: []u8,
    dark_theme: []u8,

    fn setTheme(self: *const GTK, allocator: std.mem.Allocator, scheme: ColorScheme) !void {
        try self.setGtkTheme(allocator, scheme);
        try self.setColorScheme(allocator, scheme);
    }

    fn setGtkTheme(self: *const GTK, allocator: std.mem.Allocator, scheme: ColorScheme) !void {
        const theme = switch (scheme) {
            ColorScheme.Light => self.light_theme,
            ColorScheme.Dark => self.dark_theme,
        };
        const argv = [_][]const u8{ "gsettings", "set", "org.gnome.desktop.interface", "gtk-theme", theme };
        try runCommand(allocator, &argv);
    }

    fn setColorScheme(_: *const GTK, allocator: std.mem.Allocator, scheme: ColorScheme) !void {
        const scheme_str = switch (scheme) {
            ColorScheme.Light => "prefer-light",
            ColorScheme.Dark => "prefer-dark",
        };
        const argv = [_][]const u8{ "gsettings", "set", "org.gnome.desktop.interface", "color-scheme", scheme_str };
        try runCommand(allocator, &argv);
    }
};

fn readFile(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    const file = try std.fs.cwd().openFile(path, .{ .mode = .read_only });
    defer file.close();
    const file_size = (try file.stat()).size;
    return try std.fs.cwd().readFileAlloc(allocator, path, file_size);
}

fn writeFile(path: []const u8, data: []const u8) !void {
    const f = try std.fs.cwd().openFile(path, .{ .mode = .write_only });
    try f.writeAll(data);
    f.close();
}

fn parseConfig(allocator: std.mem.Allocator, path: []const u8) !std.json.Parsed(Config) {
    const data = try readFile(allocator, path);
    defer allocator.free(data);

    const parsed = try std.json.parseFromSlice(Config, allocator, data, .{ .allocate = .alloc_always });
    return parsed;
}

fn runCommand(allocator: std.mem.Allocator, argv: []const []const u8) !void {
    const proc = try std.ChildProcess.run(.{ .allocator = allocator, .argv = argv });
    defer allocator.free(proc.stdout);
    defer allocator.free(proc.stderr);
}

fn setBackground(allocator: std.mem.Allocator, path: []const u8) !void {
    const argv = [_][]const u8{ "swww", "img", path };
    try runCommand(allocator, &argv);
}

fn replaceAlloc(allocator: std.mem.Allocator, str: []const u8, old: []const u8, new: []const u8) ![]const u8 {
    const found = std.mem.indexOf(u8, str, old);
    if (found) |start_index| {
        var result = std.ArrayList(u8).init(allocator);
        defer result.deinit();
        try result.appendSlice(str[0..start_index]);
        try result.appendSlice(new);
        try result.appendSlice(str[start_index + old.len ..]);
        return result.toOwnedSlice();
    }
    return str;
}

fn setZedThemeMode(allocator: std.mem.Allocator, scheme: ColorScheme) !void {
    const home_dir = std.mem.span(c.getenv("HOME"));

    const path = try std.fs.path.join(allocator, &[_][]const u8{ home_dir, ".config/zed/settings.json" });
    defer allocator.free(path);

    const data = try readFile(allocator, path);
    defer allocator.free(data);

    const dark_mode = "\"mode\": \"dark\"";
    const light_mode = "\"mode\": \"light\"";

    if (scheme == ColorScheme.Light and std.mem.indexOf(u8, data, dark_mode) != null) {
        const new_data = try replaceAlloc(allocator, data, dark_mode, light_mode);
        defer allocator.free(new_data);
        try writeFile(path, new_data);
        return;
    }
    if (scheme == ColorScheme.Dark and std.mem.indexOf(u8, data, light_mode) != null) {
        const new_data = try replaceAlloc(allocator, data, light_mode, dark_mode);
        defer allocator.free(new_data);
        try writeFile(path, new_data);
        return;
    }
}

fn setSystemdTimer(allocator: std.mem.Allocator, timestamp: i64, cmd: []const []const u8) !void {
    var buf: [16]u8 = undefined;
    const ts = try std.fmt.bufPrint(&buf, "@{}", .{timestamp});

    var set_timer_command = std.ArrayList([]const u8).init(allocator);
    defer set_timer_command.deinit();
    try set_timer_command.appendSlice(&[_][]const u8{
        "systemd-run",
        "--user",
        "--on-calendar",
        ts,
        "--timer-property=AccuracySec=1us",
    });
    try set_timer_command.appendSlice(cmd);
    try runCommand(allocator, set_timer_command.items);
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const config_path: []const u8 = args[1];

    const parsed = try parseConfig(allocator, config_path);
    defer parsed.deinit();

    const config = parsed.value;

    const wallpaper_update_interval = 86400 / config.wallpapers.len;
    var current_wallpaper: usize = undefined;

    const now = dt.DateTime.now();
    const midnight = now.replace(.{ .hour = 0, .minute = 0, .second = 0 });

    const seconds_since_midnight: usize = @intCast(now.timestamp() - midnight.timestamp());
    const expected_wallpaper = seconds_since_midnight / wallpaper_update_interval;
    if (expected_wallpaper != current_wallpaper) {
        current_wallpaper = expected_wallpaper;
        std.fs.cwd().deleteFile(config.symlink) catch {};
        try std.fs.cwd().symLink(config.wallpapers[current_wallpaper], config.symlink, .{});
        try setBackground(allocator, config.symlink);
    }
    const time_to_next_change: i64 = @intCast(wallpaper_update_interval - seconds_since_midnight % wallpaper_update_interval);
    const next_change_ts = now.timestamp() + time_to_next_change;

    try setSystemdTimer(allocator, next_change_ts, args);

    // TODO calculations of sunrise and sunset
    const sunrise = 5 * 3600;
    const sunset = 19 * 3600;
    const color_scheme = switch (seconds_since_midnight) {
        sunrise...sunset => ColorScheme.Light,
        else => ColorScheme.Dark,
    };
    try config.gtk.setTheme(allocator, color_scheme);
    try setZedThemeMode(allocator, color_scheme);
}
