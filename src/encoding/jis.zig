const tables = @import("jis_tables.zig");

pub fn decode0208(row: u8, col: u8) ?u32 {
    return decode(&tables.jis0208_to_unicode, row, col);
}

pub fn decode0212(row: u8, col: u8) ?u32 {
    return decode(&tables.jis0212_to_unicode, row, col);
}

pub fn encode0208(codepoint: u32) ?u16 {
    return encode(&tables.unicode_to_jis0208, codepoint);
}

pub fn encode0212(codepoint: u32) ?u16 {
    return encode(&tables.unicode_to_jis0212, codepoint);
}

fn decode(table: []const u16, row: u8, col: u8) ?u32 {
    if (row < 0x21 or row > 0x7E or col < 0x21 or col > 0x7E) return null;
    const codepoint = table[(@as(usize, row) - 0x21) * 94 + col - 0x21];
    return if (codepoint == 0) null else codepoint;
}

fn encode(table: []const u32, codepoint: u32) ?u16 {
    if (codepoint > 0xFFFF) return null;
    var low: usize = 0;
    var high: usize = table.len;
    while (low < high) {
        const mid = low + (high - low) / 2;
        const entry = table[mid];
        if (entry >> 16 < codepoint) {
            low = mid + 1;
        } else {
            high = mid;
        }
    }
    if (low == table.len or table[low] >> 16 != codepoint) return null;
    return @truncate(table[low]);
}
