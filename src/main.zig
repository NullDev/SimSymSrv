const std = @import("std");

// ========================= //
// = Copyright (c) NullDev = //
// ========================= //

const IMAGE_DIRECTORY_ENTRY_DEBUG = 6;
const IMAGE_DEBUG_TYPE_CODEVIEW = 2;

const DosHeader = extern struct {
    e_magic: u16, // "MZ"
    _pad: [58]u8,
    e_lfanew: u32, // PE header offset
};

const CoffFileHeader = extern struct {
    Machine: u16,
    NumberOfSections: u16,
    TimeDateStamp: u32,
    PointerToSymbolTable: u32,
    NumberOfSymbols: u32,
    SizeOfOptionalHeader: u16,
    Characteristics: u16,
};

const DataDirectory = extern struct {
    VirtualAddress: u32,
    Size: u32,
};

const OptionalHeader32 = extern struct {
    _pad1: [96]u8,
    DataDirectory: [16]DataDirectory,
};
const OptionalHeader64 = extern struct {
    _pad1: [112]u8,
    DataDirectory: [16]DataDirectory,
};

const SectionHeader = extern struct {
    Name: [8]u8,
    VirtualSize: u32,
    VirtualAddress: u32,
    SizeOfRawData: u32,
    PointerToRawData: u32,
    PointerToRelocations: u32,
    PointerToLinenumbers: u32,
    NumberOfRelocations: u16,
    NumberOfLinenumbers: u16,
    Characteristics: u32,
};

const DebugDirectory = extern struct {
    Characteristics: u32,
    TimeDateStamp: u32,
    MajorVersion: u16,
    MinorVersion: u16,
    Type: u32,
    SizeOfData: u32,
    AddressOfRawData: u32,
    PointerToRawData: u32,
};

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

    const pdb_info = extractCodeViewInfo(pe_data) catch |e| switch (e) {
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
    try download(url, out_path_buf, gpa.allocator(), 8);
    try stdout.print("\nDownloaded {s}\n", .{out_path_buf});
}

// Helpers

fn readLineAlloc(alloc: std.mem.Allocator, r: anytype) ![]u8 {
    var buf: [4096]u8 = undefined;
    const bytes = (try r.readUntilDelimiterOrEof(&buf, '\n')) orelse &[_]u8{};
    return alloc.dupe(u8, std.mem.trim(u8, bytes, " \r\n"));
}

fn extractCodeViewInfo(data: []const u8) !struct { name: []const u8, guid_age: []u8 } {
    const d = data;
    if (d.len < @sizeOf(DosHeader)) return error.BadFile;

    const dos: *align(1) const DosHeader = @ptrCast(d.ptr);
    if (dos.e_magic != 0x5A4D) return error.BadFile; // "MZ"

    const pe_off = dos.e_lfanew;
    if (pe_off + 4 + @sizeOf(CoffFileHeader) > d.len) return error.BadFile;
    const pe_sig = [_]u8{ 'P', 'E', 0, 0 };
    if (!std.mem.eql(u8, d[pe_off .. pe_off + 4], &pe_sig))
        return error.BadFile; // "PE\0\0"

    const coff: *align(1) const CoffFileHeader = @ptrCast(@as([*]const u8, d.ptr) + pe_off + 4);
    const opt_off = pe_off + 4 + @sizeOf(CoffFileHeader);
    // detect PE32 vs. PE32+ correctly
    // Optional-header “magic” field (0x10B = PE32, 0x20B = PE32+)
    // Pointer to the 2-byte “Magic” field (0x10B = PE32, 0x20B = PE32+)
    const magic_bytes: *align(1) const [2]u8 = @ptrCast(@as([*]const u8, d.ptr) + opt_off);
    // Read it as little-endian u16
    const magic: u16 = std.mem.readInt(u16, magic_bytes, .little);
    const is_pe32plus = magic == 0x20b; // 64-bit if 0x20B, otherwise 32-bit

    const optional32 = blk: {
        if (is_pe32plus) break :blk null;
        if (opt_off + @sizeOf(OptionalHeader32) > d.len) return error.BadFile;
        break :blk {
            const p32: *align(1) const OptionalHeader32 = @ptrCast(@as([*]const u8, d.ptr) + opt_off);
            break :blk p32;
        };
    };

    const optional64 = blk: {
        if (!is_pe32plus) break :blk null;
        if (opt_off + @sizeOf(OptionalHeader64) > d.len) return error.BadFile;
        break :blk {
            const p64: *align(1) const OptionalHeader64 = @ptrCast(@as([*]const u8, d.ptr) + opt_off);
            break :blk p64;
        };
    };

    const data_dir = if (is_pe32plus) optional64.?.DataDirectory[IMAGE_DIRECTORY_ENTRY_DEBUG] else optional32.?.DataDirectory[IMAGE_DIRECTORY_ENTRY_DEBUG];

    if (data_dir.Size == 0) return error.NoDebugDirectory;

    // read section headers (needed for RVA -> file-offset)
    const sect_off = opt_off + coff.SizeOfOptionalHeader;
    const sections_ptr: [*]align(1) const SectionHeader = @ptrCast(@as([*]const u8, d.ptr) + sect_off);
    const sections = sections_ptr[0..coff.NumberOfSections];

    const debug_dir_file_off = rvaToFileOffset(data_dir.VirtualAddress, sections) orelse
        return error.BadRva;
    if (debug_dir_file_off + data_dir.Size > d.len) return error.BadFile;

    const count = data_dir.Size / @sizeOf(DebugDirectory);
    const debug_ptr: [*]align(1) const DebugDirectory = @ptrCast(@as([*]const u8, d.ptr) + debug_dir_file_off);
    const debug_entries = debug_ptr[0..count];

    var cv_ptr: ?[]const u8 = null;
    for (debug_entries) |entry| {
        if (entry.Type == IMAGE_DEBUG_TYPE_CODEVIEW) {
            const off = if (entry.PointerToRawData != 0)
                entry.PointerToRawData
            else
                rvaToFileOffset(entry.AddressOfRawData, sections) orelse return error.BadRva;
            if (off + entry.SizeOfData > d.len) continue;
            cv_ptr = d[off .. off + entry.SizeOfData];
            break;
        }
    }
    const cv = cv_ptr orelse return error.NoCodeView;

    if (cv.len < 24 or !std.mem.eql(u8, cv[0..4], "RSDS")) return error.BadCodeView;

    const guid = cv[4..20]; // 16 bytes
    const age = std.mem.readInt(u32, cv[20..24], .little);
    const pdb_path = cv[24..]; // NUL-terminated UTF-8 path

    // Chop to basename
    const slash = std.mem.lastIndexOfScalar(u8, pdb_path, '\\') orelse std.mem.lastIndexOfScalar(u8, pdb_path, '/') orelse 0;
    const end_idx = std.mem.indexOfScalar(u8, pdb_path, 0) orelse pdb_path.len;
    const start_idx: usize = if (slash == 0) 0 else slash + 1;
    const name = pdb_path[start_idx..end_idx];

    // format GUID the way SymSrv expects (fields 1-3 big-endian)
    var guid_buf: [32]u8 = undefined;
    var ordered: [16]u8 = undefined;
    ordered[0] = guid[3];
    ordered[1] = guid[2];
    ordered[2] = guid[1];
    ordered[3] = guid[0];
    ordered[4] = guid[5];
    ordered[5] = guid[4];
    ordered[6] = guid[7];
    ordered[7] = guid[6];

    // copy the last 8 bytes of the RSDS GUID verbatim
    @memcpy(ordered[8..], guid[8..16]);

    const HEX = "0123456789ABCDEF";

    var idx: usize = 0;
    for (ordered) |b| {
        guid_buf[idx] = HEX[(b >> 4) & 0x0F]; // high nibble
        guid_buf[idx + 1] = HEX[b & 0x0F]; // low  nibble
        idx += 2;
    }
    const guid_str = guid_buf[0..idx];

    const guid_age = try std.fmt.allocPrint(
        std.heap.page_allocator,
        "{s}{d}",
        .{ guid_str, age },
    );

    return .{
        .name = name,
        .guid_age = guid_age,
    };
}

fn rvaToFileOffset(rva: u32, sections: []align(1) const SectionHeader) ?usize {
    for (sections) |s| {
        const size = @max(s.SizeOfRawData, s.VirtualSize);
        const start = s.VirtualAddress;
        const end = start + size;
        if (rva >= start and rva < end)
            return (rva - start) + s.PointerToRawData;
    }
    return null;
}

inline fn componentSlice(comp: std.Uri.Component) []const u8 {
    return switch (comp) {
        .raw, .percent_encoded => |s| s,
    };
}

fn download(
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
