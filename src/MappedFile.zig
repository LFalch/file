const std = @import("std");
const builtin = @import("builtin");
const fs = std.fs;

const Self = @This();

const WINDOWS = builtin.os.tag == .windows;

const Buf = if (WINDOWS) []u8 else []align(std.mem.page_size) u8;

buf: Buf,
alloc: if (WINDOWS) std.mem.Allocator else void,

/// Allocator is only used on Windows currently
pub fn init(filename: []const u8, alloc: std.mem.Allocator) !Self {
    const file = try fs.cwd().openFile(filename, .{});
    defer file.close();

    const state = try file.stat();
    const f_size = state.size;
    if (f_size == 0) return .{ .buf = &[0]u8{}, .alloc = undefined };

    if (WINDOWS) {
        const buf = try alloc.alloc(u8, f_size);
        _ = try file.readAll(buf);

        return .{ .buf = buf, .alloc = alloc };
    } else {
        const ptr = try std.posix.mmap(
            null,
            f_size,
            std.posix.PROT.READ,
            .{ .TYPE = .PRIVATE },
            file.handle,
            0,
        );

        return .{ .buf = ptr, .alloc = {} };
    }
}
pub fn deinit(self: Self) void {
    if (self.buf.len == 0) return;
    if (WINDOWS) {
        self.alloc.free(self.buf);
    } else {
        std.posix.munmap(self.buf);
    }
}
