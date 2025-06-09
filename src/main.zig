const std = @import("std");
const pe = @import("pe.zig");
const downloader = @import("downloader.zig");
const h = @import("headers.zig");

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

    const stdin = std.io.getStdIn().reader();
    const stdout = std.io.getStdOut().writer();

    // gather user input
    try stdout.print("Path to EXE/DLL/SYS: ", .{});
    const exe_path = try readLineAlloc(alloc, stdin);
    defer alloc.free(exe_path);
    try stdout.print("Path to Output Folder: ", .{});
    const out_dir_path = try readLineAlloc(alloc, stdin);
    defer alloc.free(out_dir_path);

    // open and load the PE
    const pe_file = try std.fs.openFileAbsolute(exe_path, .{});
    defer pe_file.close();
    const pe_data = try pe_file.readToEndAlloc(alloc, 64 * 1024 * 1024); // ≤ 64 MB
    defer alloc.free(pe_data);

    const pdb_info = pe.extractCodeViewInfo(pe_data) catch |e| switch (e) {
        error.NoCodeView, error.NoDebugDirectory => {
            std.log.err("file '{s}' has no CodeView info. cannot build URL\n", .{exe_path});
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
    const out_path_buf = try std.mem.concat(alloc, u8, &.{ out_dir_path, std.fs.path.sep_str, pdb_name });
    defer alloc.free(out_path_buf);

    try stdout.print("Downloading '{s}' to {s}", .{ url, out_path_buf });
    try downloader.download(url, out_path_buf, gpa.allocator(), 8);
    try stdout.print("\nDownloaded {s}\n", .{out_path_buf});
}
