const std = @import("std");

// ========================= //
// = Copyright (c) NullDev = //
// ========================= //

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

        // stream body to file
        var file = try std.fs.cwd().createFile(outfile_path, .{});
        defer file.close();

        var body_reader = req.reader();
        var buf: [4 * 1024]u8 = undefined;
        while (true) {
            const n = try body_reader.read(&buf);
            if (n == 0) break;
            try file.writeAll(buf[0..n]);
        }
        break;
    }
}
