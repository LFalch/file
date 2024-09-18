const std = @import("std");
const file = @import("file.zig");
const MappedFile = @import("MappedFile.zig");

pub fn main() !u8 {
    var sfb_alloc = std.heap.stackFallback(16 * 4096, std.heap.page_allocator);
    const alloc = sfb_alloc.get();

    const stdout_raw_file = std.io.getStdOut().writer();
    var stdout_buf_writer = std.io.bufferedWriter(stdout_raw_file);
    const stdout_file = stdout_buf_writer.writer();
    const stderr_file = std.io.getStdErr().writer();
    const args = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, args);

    var ret: u8 = 0;

    if (args.len == 1) {
        try stderr_file.print("Usage: {s} <files..>\n", .{args[0]});
        return 1;
    }

    for (args[1..]) |path| {
        const class = classify_file(path, alloc) catch |e| {
            try stderr_file.print("{s}: error {s}\n", .{ path, @errorName(e) });
            ret = 1;
            continue;
        };

        try stdout_file.print("{s}: {s}\n", .{ path, class.name() });
        try stdout_buf_writer.flush();
    }

    return ret;
}

fn classify_file(path: []const u8, alloc: std.mem.Allocator) !file.Class {
    const mapped_file = try MappedFile.init(path, alloc);
    defer mapped_file.deinit();

    var classifier = file.Classifier.init();
    for (mapped_file.buf) |b| {
        if (classifier.step(b)) break;
    }
    return classifier.finish();
}
