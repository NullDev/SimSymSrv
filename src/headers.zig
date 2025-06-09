// ========================= //
// = Copyright (c) NullDev = //
// ========================= //

pub const IMAGE_DIRECTORY_ENTRY_DEBUG = 6;
pub const IMAGE_DEBUG_TYPE_CODEVIEW = 2;

pub const DosHeader = extern struct {
    e_magic: u16, // "MZ"
    _pad: [58]u8,
    e_lfanew: u32, // PE header offset
};

pub const CoffFileHeader = extern struct {
    Machine: u16,
    NumberOfSections: u16,
    TimeDateStamp: u32,
    PointerToSymbolTable: u32,
    NumberOfSymbols: u32,
    SizeOfOptionalHeader: u16,
    Characteristics: u16,
};

pub const DataDirectory = extern struct {
    VirtualAddress: u32,
    Size: u32,
};

pub const OptionalHeader32 = extern struct {
    _pad1: [96]u8,
    DataDirectory: [16]DataDirectory,
};

pub const OptionalHeader64 = extern struct {
    _pad1: [112]u8,
    DataDirectory: [16]DataDirectory,
};

pub const SectionHeader = extern struct {
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

pub const DebugDirectory = extern struct {
    Characteristics: u32,
    TimeDateStamp: u32,
    MajorVersion: u16,
    MinorVersion: u16,
    Type: u32,
    SizeOfData: u32,
    AddressOfRawData: u32,
    PointerToRawData: u32,
};
