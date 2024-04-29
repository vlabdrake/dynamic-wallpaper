const std = @import("std");
const c = @cImport({
    @cInclude("time.h");
});

pub const DateTime = struct {
    tm: c.struct_tm,

    pub fn now() DateTime {
        const ts = c.time(null);
        return DateTime{ .tm = c.localtime(&ts).* };
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
        return result;
    }

    pub fn timestamp(self: *const DateTime) i64 {
        var _tm = self.tm;
        return c.mktime(&_tm);
    }
};
