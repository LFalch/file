const std = @import("std");
const file = @import("file.zig");

pub fn main() !u8 {
    const stdout_file = std.io.getStdOut().writer();
    const stderr_file = std.io.getStdErr().writer();

    var ret: u8 = 0;

    if (std.os.argv.len == 1) {
        try stderr_file.print("Usage: {s} <files..>\n", .{std.mem.span(std.os.argv[0])});
        return 1;
    }

    for (std.os.argv[1..]) |arg| {
        const path = std.mem.span(arg);
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
