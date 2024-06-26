const std = @import("std");
const dt = @import("datetime.zig");
const c = @cImport(@cInclude("stdlib.h"));

const ColorScheme = enum { Light, Dark };

const Config = struct {
    wallpaper: ?Wallpaper = null,
    gtk: ?Gtk = null,
    kitty: ?Kitty = null,
    helix: ?Helix = null,
};

const Wallpaper = struct {
    wallpapers: [][]u8,

    fn getExpectedWallpaper(self: *const Wallpaper, seconds_since_midnight: u64) usize {
        const wallpaper_update_interval = 86400 / self.wallpapers.len;
        return seconds_since_midnight / wallpaper_update_interval;
    }

    fn updateWallpaper(self: *const Wallpaper, allocator: std.mem.Allocator, wallpaper: usize) !void {
        const runtime_dir = std.mem.span(c.getenv("XDG_RUNTIME_DIR"));
        const wallpaper_path_filename = try std.fs.path.join(allocator, &[_][]const u8{ runtime_dir, "dynamic_wallpaper" });

        const wallpaper_path = try std.fs.createFileAbsolute(wallpaper_path_filename, .{ .truncate = true });
        defer wallpaper_path.close();

        _ = try wallpaper_path.writeAll(self.wallpapers[wallpaper]);
        try setBackground(allocator, self.wallpapers[wallpaper]);
    }
};

const Gtk = struct {
    light_theme: []u8,
    dark_theme: []u8,

    fn setTheme(self: *const Gtk, allocator: std.mem.Allocator, scheme: ColorScheme) !void {
        try self.setGtkTheme(allocator, scheme);
        try self.setColorScheme(allocator, scheme);
    }

    fn setGtkTheme(self: *const Gtk, allocator: std.mem.Allocator, scheme: ColorScheme) !void {
        const theme = switch (scheme) {
            ColorScheme.Light => self.light_theme,
            ColorScheme.Dark => self.dark_theme,
        };
        const argv = [_][]const u8{ "gsettings", "set", "org.gnome.desktop.interface", "gtk-theme", theme };
        try runCommand(allocator, &argv);
    }

    fn setColorScheme(_: *const Gtk, allocator: std.mem.Allocator, scheme: ColorScheme) !void {
        const scheme_str = switch (scheme) {
            ColorScheme.Light => "prefer-light",
            ColorScheme.Dark => "prefer-dark",
        };
        const argv = [_][]const u8{ "gsettings", "set", "org.gnome.desktop.interface", "color-scheme", scheme_str };
        try runCommand(allocator, &argv);
    }
};

const Kitty = struct {
    light_theme: []const u8,
    dark_theme: []const u8,

    fn setTheme(self: *const Kitty, allocator: std.mem.Allocator, scheme: ColorScheme) !void {
        const home_dir = std.mem.span(c.getenv("HOME"));
        const kitty_dir = try std.fs.path.join(allocator, &[_][]const u8{ home_dir, ".config/kitty" });
        const theme_config = "theme.conf";
        const dir = try std.fs.cwd().openDir(kitty_dir, .{});
        dir.deleteFile(theme_config) catch {};
        const theme = switch (scheme) {
            ColorScheme.Dark => self.dark_theme,
            ColorScheme.Light => self.light_theme,
        };
        try dir.symLink(theme, theme_config, .{});
        try runCommand(allocator, &[_][]const u8{ "killall", "-SIGUSR1", "kitty" });
    }
};

const Helix = struct {
    light_theme: []const u8,
    dark_theme: []const u8,

    fn setTheme(self: *const Helix, allocator: std.mem.Allocator, scheme: ColorScheme) !void {
        const home_dir = std.mem.span(c.getenv("HOME"));
        const path = try std.fs.path.join(allocator, &[_][]const u8{ home_dir, ".config/helix/config.toml" });
        defer allocator.free(path);

        const data = try readFile(allocator, path);
        defer allocator.free(data);

        const theme_prefix = "theme = \"";
        const theme_position = std.mem.indexOf(u8, data, theme_prefix);

        var current_theme: ?[]const u8 = null;
        if (theme_position) |tp| {
            const theme_name_start = tp + theme_prefix.len;
            const theme_name_end = theme_name_start + std.mem.indexOf(u8, data[theme_name_start..], "\"").?;
            current_theme = data[theme_name_start..theme_name_end];
        }

        const theme = switch (scheme) {
            ColorScheme.Light => self.light_theme,
            ColorScheme.Dark => self.dark_theme,
        };

        if (current_theme) |ct| {
            if (!std.mem.eql(u8, ct, theme)) {
                const new_data = try replaceAlloc(allocator, data, ct, theme);
                defer allocator.free(new_data);
                try writeFile(path, new_data);
            }
        } else {
            const f = try std.fs.cwd().openFile(path, .{ .mode = .write_only });
            try f.writeAll("theme = \"");
            try f.writeAll(theme);
            try f.writeAll("\"\n");
            try f.writeAll(data);
            f.close();
        }

        try runCommand(allocator, &[_][]const u8{ "killall", "-SIGUSR1", "helix" });
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

fn getColorScheme(d: dt.DateTime) ColorScheme {
    // TODO calculations of sunrise and sunset
    const seconds_since_midnight = d.timestamp() - d.replace(.{ .hour = 0, .minute = 0, .second = 0 }).timestamp();
    const sunrise = 5 * 3600;
    const sunset = 19 * 3600;
    const color_scheme = switch (seconds_since_midnight) {
        sunrise...sunset => ColorScheme.Light,
        else => ColorScheme.Dark,
    };
    return color_scheme;
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

    const midnight = dt.DateTime.now().replace(.{ .hour = 0, .minute = 0, .second = 0 });

    var current_wallpaper: ?usize = null;
    var current_color_scheme: ?ColorScheme = null;

    while (true) {
        const now = dt.DateTime.now();
        const seconds_since_midnight: usize = @as(usize, @intCast(now.timestamp() - midnight.timestamp())) % 86400;

        const color_scheme = getColorScheme(now);
        if (color_scheme != current_color_scheme) {
            current_color_scheme = color_scheme;

            try setZedThemeMode(allocator, color_scheme);

            if (config.gtk) |gtk| {
                try gtk.setTheme(allocator, color_scheme);
            }

            if (config.kitty) |kitty| {
                try kitty.setTheme(allocator, color_scheme);
            }

            if (config.helix) |helix| {
                try helix.setTheme(allocator, color_scheme);
            }
        }
        if (config.wallpaper) |wallpaper| {
            const expected_wallpaper = wallpaper.getExpectedWallpaper(seconds_since_midnight);
            if (expected_wallpaper != current_wallpaper) {
                current_wallpaper = expected_wallpaper;
                try wallpaper.updateWallpaper(allocator, expected_wallpaper);
            }
        }

        std.time.sleep(1 * std.time.ns_per_s);
    }
}
