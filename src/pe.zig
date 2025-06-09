const std = @import("std");
const h = @import("headers.zig");

// ========================= //
// = Copyright (c) NullDev = //
// ========================= //

fn rvaToFileOffset(rva: u32, sections: []align(1) const h.SectionHeader) ?usize {
    for (sections) |s| {
        const size = @max(s.SizeOfRawData, s.VirtualSize);
        const start = s.VirtualAddress;
        const end = start + size;
        if (rva >= start and rva < end)
            return (rva - start) + s.PointerToRawData;
    }
    return null;
}

pub fn extractCodeViewInfo(data: []const u8) !struct { name: []const u8, guid_age: []u8 } {
    const d = data;
    if (d.len < @sizeOf(h.DosHeader)) return error.BadFile;

    const dos: *align(1) const h.DosHeader = @ptrCast(d.ptr);
    if (dos.e_magic != 0x5A4D) return error.BadFile; // "MZ"

    const pe_off = dos.e_lfanew;
    if (pe_off + 4 + @sizeOf(h.CoffFileHeader) > d.len) return error.BadFile;
    const pe_sig = [_]u8{ 'P', 'E', 0, 0 };
    if (!std.mem.eql(u8, d[pe_off .. pe_off + 4], &pe_sig))
        return error.BadFile; // "PE\0\0"

    const coff: *align(1) const h.CoffFileHeader = @ptrCast(@as([*]const u8, d.ptr) + pe_off + 4);
    const opt_off = pe_off + 4 + @sizeOf(h.CoffFileHeader);
    // detect PE32 vs. PE32+ correctly
    // Pointer to the 2-byte optional-header "Magic" field (0x10B = PE32, 0x20B = PE32+)
    const magic_bytes: *align(1) const [2]u8 = @ptrCast(@as([*]const u8, d.ptr) + opt_off);
    // Read it as little-endian u16
    const magic: u16 = std.mem.readInt(u16, magic_bytes, .little);
    const is_pe32plus = magic == 0x20b; // 64-bit if 0x20B, otherwise 32-bit

    const optional32 = blk: {
        if (is_pe32plus) break :blk null;
        if (opt_off + @sizeOf(h.OptionalHeader32) > d.len) return error.BadFile;
        break :blk {
            const p32: *align(1) const h.OptionalHeader32 = @ptrCast(@as([*]const u8, d.ptr) + opt_off);
            break :blk p32;
        };
    };

    const optional64 = blk: {
        if (!is_pe32plus) break :blk null;
        if (opt_off + @sizeOf(h.OptionalHeader64) > d.len) return error.BadFile;
        break :blk {
            const p64: *align(1) const h.OptionalHeader64 = @ptrCast(@as([*]const u8, d.ptr) + opt_off);
            break :blk p64;
        };
    };

    const data_dir = if (is_pe32plus) optional64.?.DataDirectory[h.IMAGE_DIRECTORY_ENTRY_DEBUG] else optional32.?.DataDirectory[h.IMAGE_DIRECTORY_ENTRY_DEBUG];

    if (data_dir.Size == 0) return error.NoDebugDirectory;

    // read section headers (needed for RVA -> file-offset)
    const sect_off = opt_off + coff.SizeOfOptionalHeader;
    const sections_ptr: [*]align(1) const h.SectionHeader = @ptrCast(@as([*]const u8, d.ptr) + sect_off);
    const sections = sections_ptr[0..coff.NumberOfSections];

    const debug_dir_file_off = rvaToFileOffset(data_dir.VirtualAddress, sections) orelse
        return error.BadRva;
    if (debug_dir_file_off + data_dir.Size > d.len) return error.BadFile;

    const count = data_dir.Size / @sizeOf(h.DebugDirectory);
    const debug_ptr: [*]align(1) const h.DebugDirectory = @ptrCast(@as([*]const u8, d.ptr) + debug_dir_file_off);
    const debug_entries = debug_ptr[0..count];

    var cv_ptr: ?[]const u8 = null;
    for (debug_entries) |entry| {
        if (entry.Type == h.IMAGE_DEBUG_TYPE_CODEVIEW) {
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
        guid_buf[idx + 1] = HEX[b & 0x0F]; // low nibble
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
