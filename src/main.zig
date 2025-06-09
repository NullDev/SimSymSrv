const std = @import("std");
const pe = @import("pe.zig");
const downloader = @import("downloader/downloader.zig");
const h = @import("headers.zig");
const cli = @import("cli.zig");

// ========================= //
// = Copyright (c) NullDev = //
// ========================= //

fn readLineAlloc(alloc: std.mem.Allocator, r: anytype) ![]u8 {
    var buf: [4096]u8 = undefined;
    const bytes = (try r.readUntilDelimiterOrEof(&buf, '\n')) orelse &[_]u8{};
    return alloc.dupe(u8, std.mem.trim(u8, bytes, " \r\n"));
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    // abort if the leak checker reports anything but ".ok"
    const alloc = gpa.allocator();

    const stdout = std.io.getStdOut().writer();

    const options = try cli.parseArgs(alloc);
    defer {
        if (options.exe_path) |path| alloc.free(path);
        if (options.out_dir_path) |path| alloc.free(path);
    }

    const stdin = std.io.getStdIn().reader();

    // If arguments weren't provided, prompt for them
    const final_exe_path = if (options.exe_path) |path| path else blk: {
        try stdout.print("Path to EXE/DLL/SYS: ", .{});
        break :blk try readLineAlloc(alloc, stdin);
    };
    defer if (options.exe_path == null) alloc.free(final_exe_path);

    const final_out_dir = if (options.out_dir_path) |path| path else blk: {
        try stdout.print("Path to Output Folder: ", .{});
        break :blk try readLineAlloc(alloc, stdin);
    };
    defer if (options.out_dir_path == null) alloc.free(final_out_dir);

    // open and load the PE
    const pe_file = try std.fs.openFileAbsolute(final_exe_path, .{});
    defer pe_file.close();
    const pe_data = try pe_file.readToEndAlloc(alloc, 64 * 1024 * 1024); // ≤ 64 MB
    defer alloc.free(pe_data);

    const pdb_info = pe.extractCodeViewInfo(pe_data) catch |e| switch (e) {
        error.NoCodeView, error.NoDebugDirectory => {
            std.log.err("file '{s}' has no CodeView info. cannot build URL\n", .{final_exe_path});
            return;
        },
        else => return e,
    };
    const pdb_name = pdb_info.name;
    const guid_age = pdb_info.guid_age;

    const url = try std.fmt.allocPrint(
        alloc,
        "https://msdl.microsoft.com/download/symbols/{s}/{s}/{s}",
        .{ pdb_name, guid_age, pdb_name },
    );
    defer alloc.free(url);

    // prepare output path
    const out_path_buf = try std.mem.concat(alloc, u8, &.{ final_out_dir, std.fs.path.sep_str, pdb_name });
    defer alloc.free(out_path_buf);

    try stdout.print("Downloading '{s}' to {s}\n", .{ url, out_path_buf });
    try downloader.download(url, out_path_buf, gpa.allocator(), 8);
    try stdout.print("Downloaded {s}\n", .{out_path_buf});
}
