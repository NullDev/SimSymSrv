const std = @import("std");

// ========================= //
// = Copyright (c) NullDev = //
// ========================= //

pub const CliOptions = struct {
    exe_path: ?[]const u8,
    out_dir_path: ?[]const u8,
};

pub fn printUsage(writer: anytype) !void {
    try writer.writeAll(
        \\SimSymSrv is a tool to download PDB files from Microsoft's Symbol Server.
        \\Copyright (c) 2025 NullDev
        \\
        \\Usage: SimSymSrv [options]
        \\
        \\Options:
        \\  -i, --input <PATH>   Path to EXE/DLL/SYS file
        \\  -o, --output <PATH>  Path to output folder
        \\  -h, --help           Print this help message
        \\
        \\If options are not provided, you will be prompted for the missing input.
        \\
    );
}

pub fn parseArgs(allocator: std.mem.Allocator) !CliOptions {
    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    var options = CliOptions{
        .exe_path = null,
        .out_dir_path = null,
    };

    // Skip the program name argv[0]
    _ = args.skip();

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            try printUsage(std.io.getStdOut().writer());
            std.process.exit(0);
        } else if (std.mem.eql(u8, arg, "-i") or std.mem.eql(u8, arg, "--input")) {
            const path = args.next() orelse {
                try std.io.getStdErr().writer().writeAll("Error: -i/--input requires a path argument\n");
                try printUsage(std.io.getStdErr().writer());
                return error.InvalidArgument;
            };
            options.exe_path = try allocator.dupe(u8, path);
        } else if (std.mem.eql(u8, arg, "-o") or std.mem.eql(u8, arg, "--output")) {
            const path = args.next() orelse {
                try std.io.getStdErr().writer().writeAll("Error: -o/--output requires a path argument\n");
                try printUsage(std.io.getStdErr().writer());
                return error.InvalidArgument;
            };
            options.out_dir_path = try allocator.dupe(u8, path);
        } else {
            try std.io.getStdErr().writer().print("Error: Unknown argument '{s}'\n", .{arg});
            try printUsage(std.io.getStdErr().writer());
            return error.InvalidArgument;
        }
    }

    return options;
}
