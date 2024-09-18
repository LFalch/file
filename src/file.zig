const std = @import("std");

pub const Class = enum {
    empty,
    ascii,
    latin1,
    utf8,
    utf16_le,
    utf16_be,
    data,

    pub fn name(self: @This()) []const u8 {
        return switch (self) {
            .empty => "empty",
            .ascii => "ASCII text",
            .latin1 => "ISO-8859 text",
            .utf8 => "UTF-8 Unicode text",
            .utf16_le => "Little-endian UTF-16 Unicode text",
            .utf16_be => "Big-endian UTF-16 Unicode text",
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
fn codepoint(low_surrogate: u16, high_surrogate: u16) u21 {
    const low_half: u21 = low_surrogate;
    const high_half: u21 = high_surrogate;
    return 0x10000 + ((high_half & 0x03ff) << 10) | (low_half & 0x03ff);
}
const MAX_CODEPOINT: u21 = 0x10FFFF;
const BOM_LE: [2]u8 = [_]u8{ 0xff, 0xfe };
const BOM_BE: [2]u8 = [_]u8{ 0xfe, 0xff };

pub const Classifier = struct {
    const State = packed struct(u6) {
        empty: bool = true,
        ascii: bool = true,
        latin1: bool = true,
        utf8: bool = true,
        utf16: enum(u2) {
            none = 0,
            le,
            be,
            no_bom_yet,
        } = .no_bom_yet,
    };
    possible_text: State = .{},
    expected_follow_bytes: u2 = 0,

    first_utf16_byte: ?u8 = null,
    first_surrogate: ?u16 = null,

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
                    const seq_length = std.unicode.utf8ByteSequenceLength(byte) catch {
                        self.possible_text.utf8 = false;
                        break :utf8;
                    };
                    const follow_bytes = seq_length - 1;

                    if (follow_bytes == 0) {
                        if (!isAsciiText(byte)) self.possible_text.utf8 = false;
                    } else {
                        self.expected_follow_bytes = @intCast(follow_bytes);
                    }
                }
            }
        }

        utf16: {
            if (self.first_utf16_byte) |prev_byte| {
                self.first_utf16_byte = null;
                const u8_u8 = [2]u8{ prev_byte, byte };

                const endian: std.builtin.Endian = switch (self.possible_text.utf16) {
                    .no_bom_yet => {
                        self.possible_text.utf16 = if (std.mem.eql(u8, &u8_u8, &BOM_LE)) .le else if (std.mem.eql(u8, &u8_u8, &BOM_BE)) .be else .none;
                        break :utf16;
                    },
                    .none => break :utf16,
                    .le => .little,
                    .be => .big,
                };

                const code_unit = std.mem.readInt(u16, &u8_u8, endian);

                if (self.first_surrogate) |high_surrogate| {
                    self.first_surrogate = null;
                    if (!std.unicode.utf16IsLowSurrogate(code_unit) or codepoint(code_unit, high_surrogate) > MAX_CODEPOINT)
                        self.possible_text.utf16 = .none;
                } else if (std.unicode.utf16IsHighSurrogate(code_unit)) {
                    self.first_surrogate = code_unit;
                } else {
                    // the code unit is the whole code point
                    if (!(code_unit >= 160 or isAsciiText(@intCast(code_unit))))
                        self.possible_text.utf16 = .none;
                }
            } else {
                self.first_utf16_byte = byte;
            }
        }

        // say we're done if they are no possible classifications
        return @as(u6, @bitCast(self.possible_text)) == 0;
    }
    pub fn finish(self: Self) Class {
        if (self.possible_text.empty) return .empty;

        if (self.first_utf16_byte == null and self.first_surrogate == null) {
            switch (self.possible_text.utf16) {
                .le => return .utf16_le,
                .be => return .utf16_be,
                else => {},
            }
        }

        if (self.possible_text.ascii) return .ascii;
        if (self.possible_text.utf8 and self.expected_follow_bytes == 0) return .utf8;
        if (self.possible_text.latin1) return .latin1;

        return .data;
    }
};
