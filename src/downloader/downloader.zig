const std = @import("std");
const ProgressBar = @import("progress.zig").ProgressBar;

// ========================= //
// = Copyright (c) NullDev = //
// ========================= //

fn ensureOutputDir(outfile_path: []const u8) !void {
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

fn getNextAvailableFilename(allocator: std.mem.Allocator, base_path: []const u8) ![]const u8 {
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

inline fn componentSlice(comp: std.Uri.Component) []const u8 {
    return switch (comp) {
        .raw, .percent_encoded => |s| s,
    };
}

pub fn download(
    url: []const u8,
    outfile_path: []const u8,
    allocator: std.mem.Allocator,
    max_redirects: usize,
) !void {
    // Ensure output directory exists before attempting download
    try ensureOutputDir(outfile_path);

    var redirects: usize = 0;
    var current = try allocator.dupe(u8, url);
    defer allocator.free(current);

    while (true) : (redirects += 1) {
        if (redirects > max_redirects) return error.TooManyRedirects;

        // build & send request
        var client = std.http.Client{ .allocator = allocator };
        defer client.deinit();

        var hdr_buf: [16 * 1024]u8 = undefined;
        const uri = try std.Uri.parse(current);

        var req = try client.open(
            .GET,
            uri,
            .{
                .server_header_buffer = &hdr_buf,
                .extra_headers = &.{},
            },
        );
        defer req.deinit();

        try req.send();
        try req.wait();

        const status = req.response.status;

        // deal with redirects
        if (status == .moved_permanently or status == .found or
            status == .see_other or status == .temporary_redirect or
            status == .permanent_redirect)
        {
            const loc = req.response.location orelse return error.MissingLocationHeader;

            // absolute Location means just follow it
            if (std.mem.startsWith(u8, loc, "http")) {
                allocator.free(current);
                current = try allocator.dupe(u8, loc);
                continue;
            }

            // relative Location: build <scheme>://<host><loc>
            const host_comp = uri.host orelse return error.MissingHost;
            const host_str = componentSlice(host_comp);
            if (host_str.len == 0)
                return error.MissingHost;

            const origin = try std.fmt.allocPrint(
                allocator,
                "{s}://{s}",
                .{ uri.scheme, host_str },
            );
            defer allocator.free(origin);

            allocator.free(current);
            current = try std.fmt.allocPrint(allocator, "{s}{s}", .{ origin, loc });
            continue;
        }

        if (status != .ok) return error.UnexpectedStatusCode;

        // Get next available filename
        const final_path = try getNextAvailableFilename(allocator, outfile_path);
        defer allocator.free(final_path);

        // Get content length if available
        const content_length = if (req.response.content_length) |len| len else null;

        // stream body to file
        var file = try std.fs.cwd().createFile(final_path, .{});
        defer file.close();

        var body_reader = req.reader();
        var buf: [4 * 1024]u8 = undefined;
        var bytes_downloaded: usize = 0;

        while (true) {
            const n = try body_reader.read(&buf);
            if (n == 0) break;
            try file.writeAll(buf[0..n]);
            bytes_downloaded += n;
            ProgressBar.update(bytes_downloaded, content_length);
        }
        ProgressBar.finish();
        break;
    }
}
