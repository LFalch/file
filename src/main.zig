const std = @import("std");
const file = @import("file.zig");

var args_buf: [4096]u8 = undefined;

fn getArgs() ![]const [:0]const u8 {
    var arena_alloc = std.heap.FixedBufferAllocator.init(&args_buf);
    const arena = arena_alloc.allocator();

    return std.process.argsAlloc(arena);
}

pub fn main() !u8 {
    const stdout_file = std.io.getStdOut().writer();
    const stderr_file = std.io.getStdErr().writer();
    const args = try getArgs();

    var ret: u8 = 0;

    if (args.len == 1) {
        try stderr_file.print("Usage: {s} <files..>\n", .{args[0]});
        return 1;
    }

    for (args[1..]) |path| {
        const class = classify_file(path) catch |e| {
            try stderr_file.print("{s}: error {s}\n", .{ path, @errorName(e) });
            ret = 1;
            continue;
        };

        try stdout_file.print("{s}: {s}\n", .{ path, class.name() });
    }

    return ret;
}

fn classify_file(path: []const u8) !file.Class {
    var f = try std.fs.cwd().openFile(path, .{});
    var buf_reader = std.io.bufferedReader(f.reader());
    const reader = buf_reader.reader();

    var classifier = file.Classifier.init();
    while (true) {
        const b = reader.readByte() catch |e|
            if (e == error.EndOfStream) break else return e;
        if (classifier.step(b)) break;
    }
    return classifier.finish();
}
