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
            .latin1 => "ISO 8859 text",
            .utf8 => "UTF-8 Unicode text",
            .data => "data",
        };
    }
};

pub const Classifier = packed struct(u8) {
    const State = packed struct(u4) {
        empty: bool = true,
        ascii: bool = true,
        latin1: bool = true,
        utf8: bool = true,
    };
    possible_text: State = .{},
    expected_follow_bytes: u4 = 0,

    const Self = @This();

    pub fn init() Self {
        return .{};
    }
    pub fn step(self: *Self, byte: u8) bool {
        self.possible_text.empty = false;
        if (self.possible_text.ascii) {
            switch (byte) {
                0x07...0xd => {},
                0x1b => {},
                0x20...0x7e => {},
                else => self.possible_text.ascii = false,
            }
        }
        if (self.possible_text.latin1) {
            switch (byte) {
                0x07...0xd => {},
                0x1b => {},
                0x20...0x7e => {},
                160...255 => {},
                else => self.possible_text.latin1 = false,
            }
        }
        if (self.possible_text.utf8) {
            const leading_ones = @clz(~byte);
            if (self.expected_follow_bytes > 0) {
                self.expected_follow_bytes -= 1;
                if (leading_ones != 1) self.possible_text.utf8 = false;
            } else if (leading_ones == 0) {
                self.possible_text.utf8 = std.ascii.isASCII(byte);
            } else if (leading_ones == 1) {
                self.possible_text.utf8 = false;
            } else {
                self.expected_follow_bytes = leading_ones - 1;
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
