const std = @import("std");
const c = @cImport({
    @cInclude("time.h");
});

pub const DateTime = struct {
    tm: c.struct_tm,
    ts: i64,

    pub fn now() DateTime {
        const ts = c.time(null);
        var dt = DateTime{ .tm = undefined, .ts = ts };
        _ = c.localtime_r(&ts, &dt.tm);
        return dt;
    }

    pub fn replace(self: DateTime, replacement: anytype) DateTime {
        var result = self;
        inline for (std.meta.fields(@TypeOf(replacement))) |field| {
            if (std.mem.eql(u8, field.name, "hour")) {
                result.tm.tm_hour = @field(replacement, field.name);
            }
            if (std.mem.eql(u8, field.name, "minute")) {
                result.tm.tm_min = @field(replacement, field.name);
            }
            if (std.mem.eql(u8, field.name, "second")) {
                result.tm.tm_sec = @field(replacement, field.name);
            }
        }

        // normalize tm and update timestamp
        result.ts = c.mktime(&result.tm);
        return result;
    }

    pub fn timestamp(self: *const DateTime) i64 {
        return self.ts;
    }
};
