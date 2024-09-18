const std = @import("std");

pub const Class = enum {
    empty,
    ascii,
    latin1,
    utf8,
    data,

    pub fn name(self: @This()) []const u8 {
        return switch (self) {
            .empty => "empty",
            .ascii => "ASCII text",
            .latin1 => "ISO-8859 text",
            .utf8 => "UTF-8 Unicode text",
            .data => "data",
        };
    }
};

fn isAsciiText(byte: u8) bool {
    return switch (byte) {
        0x07...0xd => true,
        0x1b => true,
        0x20...0x7e => true,
        else => false,
    };
}

pub const Classifier = struct {
    const State = packed struct(u4) {
        empty: bool = true,
        ascii: bool = true,
        latin1: bool = true,
        utf8: bool = true,
    };
    possible_text: State = .{},
    expected_follow_bytes: u2 = 0,

    const Self = @This();

    pub fn init() Self {
        return .{};
    }
    pub fn step(self: *Self, byte: u8) bool {
        self.possible_text.empty = false;
        if (self.possible_text.ascii and !isAsciiText(byte)) {
            self.possible_text.ascii = false;
        }
        if (self.possible_text.latin1) {
            if (!(isAsciiText(byte) or byte >= 160))
                self.possible_text.latin1 = false;
        }
        utf8: {
            if (self.possible_text.utf8) {
                if (self.expected_follow_bytes > 0) {
                    self.expected_follow_bytes -= 1;
                    // if it isn't a follow byte, it is not UTF-8
                    if (@clz(~byte) != 1) self.possible_text.utf8 = false;
                } else {
                    const follow_bytes = std.unicode.utf8ByteSequenceLength(byte) catch {
                        self.possible_text.utf8 = false;
                        break :utf8;
                    } - 1;

                    if (follow_bytes == 0) {
                        if (!isAsciiText(byte)) self.possible_text.utf8 = false;
                    } else {
                        self.expected_follow_bytes = @intCast(follow_bytes);
                    }
                }
            }
        }

        // say we're done if they are no possible classifications
        return @as(u4, @bitCast(self.possible_text)) == 0;
    }
    pub fn finish(self: Self) Class {
        if (self.possible_text.empty) return .empty;

        if (self.possible_text.ascii) return .ascii;
        if (self.possible_text.utf8 and self.expected_follow_bytes == 0) return .utf8;
        if (self.possible_text.latin1) return .latin1;

        return .data;
    }
};
