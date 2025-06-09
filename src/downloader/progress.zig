const std = @import("std");

// ========================= //
// = Copyright (c) NullDev = //
// ========================= //

pub const ProgressBar = struct {
    const width = 50;
    const spinner = [_]u8{ '|', '/', '-', '\\' };
    var spinner_idx: usize = 0;
    var last_percent: usize = 0;
    var last_spinner: u8 = spinner[0];

    pub fn update(bytes_downloaded: usize, total_bytes: ?usize) void {
        const stdout = std.io.getStdOut().writer();
        const percent = if (total_bytes) |total|
            @min(100, (bytes_downloaded * 100) / total)
        else
            @min(100, (bytes_downloaded * 100) / (10 * 1024 * 1024)); // Assume 10MB if unknown

        if (percent != last_percent or spinner_idx % spinner.len == 0) {
            const filled = (percent * @as(u64, width)) / 100;
            const empty = width - @as(usize, @intCast(filled));

            stdout.writeAll("\r") catch return;
            stdout.writeAll(" " ** width) catch return;
            stdout.writeAll("\r") catch return;

            stdout.writeAll("[") catch return;
            var i: usize = 0;
            while (i < filled) : (i += 1) {
                stdout.writeAll("=") catch return;
            }
            if (empty > 0) {
                stdout.writeAll(">") catch return;
                i = 0;
                while (i < empty - 1) : (i += 1) {
                    stdout.writeAll(" ") catch return;
                }
            }
            stdout.writeAll("] ") catch return;

            last_spinner = spinner[spinner_idx % spinner.len];
            stdout.print("{c} {d}%", .{ last_spinner, percent }) catch return;

            last_percent = percent;
            spinner_idx += 1;
        }
    }

    pub fn finish() void {
        const stdout = std.io.getStdOut().writer();
        stdout.writeAll("\r") catch return;
        stdout.writeAll(" " ** width) catch return;
        stdout.writeAll("\r") catch return;

        stdout.writeAll("[") catch return;
        var i: usize = 0;
        while (i < width) : (i += 1) {
            stdout.writeAll("=") catch return;
        }
        stdout.writeAll("] ") catch return;
        stdout.writeAll("* 100%\n") catch return;
    }
};
