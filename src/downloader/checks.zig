const std = @import("std");

// ========================= //
// = Copyright (c) NullDev = //
// ========================= //

pub fn ensureOutputDir(outfile_path: []const u8) !void {
    const dir = std.fs.path.dirname(outfile_path) orelse return error.InvalidPath;

    // Try to open the directory to see if it exists
    var dir_handle = std.fs.cwd().openDir(dir, .{}) catch |err| switch (err) {
        error.FileNotFound => {
            // Directory doesn't exist, try to create it
            std.fs.cwd().makeDir(dir) catch |create_err| {
                // If we get FileNotFound, it means a parent directory doesn't exist
                if (create_err == error.FileNotFound) {
                    return error.ParentDirNotFound;
                }
                return create_err;
            };
            return;
        },
        else => return err,
    };
    dir_handle.close();
}

pub fn getNextAvailableFilename(allocator: std.mem.Allocator, base_path: []const u8) ![]const u8 {
    var counter: usize = 0;
    var path = try allocator.dupe(u8, base_path);
    defer allocator.free(path);

    while (true) {
        const file = std.fs.cwd().openFile(path, .{}) catch |err| switch (err) {
            error.FileNotFound => {
                // Return a new copy of the path since we'll free the original
                return try allocator.dupe(u8, path);
            },
            else => return err,
        };
        file.close();

        counter += 1;

        const dir = std.fs.path.dirname(base_path) orelse ".";
        const basename = std.fs.path.basename(base_path);

        // Split the basename into name and extension
        const last_dot = std.mem.lastIndexOfScalar(u8, basename, '.') orelse basename.len;
        const name = basename[0..last_dot];
        const ext = if (last_dot < basename.len) basename[last_dot..] else "";

        const new_path = try std.fmt.allocPrint(allocator, "{s}/{s} ({d}){s}", .{ dir, name, counter, ext });
        allocator.free(path);
        path = new_path;
    }
}
