const std = @import("std");
const split = std.mem.splitAny;
const fs = std.fs;
const print = std.debug.print;
const assert = std.debug.assert;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit();
    const allocator = arena.allocator();
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const file = try std.fs.cwd().openFile(args[1], .{ .mode = .read_only });
    defer file.close();

    const file_len: usize = std.math.cast(usize, try file.getEndPos()) orelse std.math.maxInt(usize);
    const mapped_mem = try std.os.mmap(
        null,
        file_len,
        std.os.PROT.READ,
        .{ .TYPE = .PRIVATE },
        file.handle,
        0,
    );
    defer std.os.munmap(mapped_mem);
    try std.os.madvise(mapped_mem.ptr, file_len, std.os.MADV.HUGEPAGE);

    var ln = try Line.init(allocator);
    defer ln.deinit();

    var city_map = std.StringHashMap(City).init(allocator);
    defer city_map.deinit();

    var last_n: u64 = 0;
    for (mapped_mem, 0..) |b, i| {
        if (b == '\n') {
            try parseLine(&ln, mapped_mem[last_n + 1 .. i]);
            last_n = i;

            const key = try allocator.dupe(u8, ln.name);

            const city = try city_map.getOrPut(key);
            if (city.found_existing) {
                city.value_ptr.*.addItem(ln.temp);
            } else {
                city.value_ptr.* = City{
                    .min = ln.temp,
                    .max = ln.temp,
                    .sum = ln.temp,
                    .count = 1,
                };
            }
            if (city.found_existing) {
                defer allocator.free(key);
            }
        }
    }

    const cities = try allocator.alloc([]const u8, city_map.count());
    defer allocator.free(cities);

    var iter = city_map.keyIterator();
    var i: usize = 0;
    while (iter.next()) |k| {
        cities[i] = k.*;
        i += 1;
    }

    std.mem.sortUnstable([]const u8, cities, {}, strLessThan);
    for (cities) |c| {
        const city = city_map.get(c) orelse continue;
        const count: f64 = @floatFromInt(city.count);
        print("{s} min: {d}, max: {d}, avg: {d}\n", .{ c, city.min, city.max, city.sum / count });
    }
}

fn strLessThan(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.order(u8, a, b) == std.math.Order.lt;
}

const City = struct {
    const Self = @This();
    min: f64,
    max: f64,
    sum: f64,
    count: i64,

    pub fn addItem(self: *Self, item: f64) void {
        self.min = @min(self.min, item);
        self.max = @max(self.max, item);
        self.sum += item;
        self.count += 1;
    }
};

const Line = struct {
    const Self = @This();

    name: []u8,
    temp: f64,
    allocator: std.mem.Allocator,

    fn init(allocator: std.mem.Allocator) !Line {
        const name = try allocator.alloc(u8, 0);
        return Line{
            .name = name,
            .temp = 0,
            .allocator = allocator,
        };
    }

    fn set_name(self: *Self, n: []const u8) !void {
        const name = try self.allocator.realloc(self.name, n.len);
        @memcpy(name, n);
        self.name = name;
    }

    fn deinit(self: Self) void {
        self.allocator.free(self.name);
    }
};

// This is missing input checking intentionally
fn parseLine(ln: *Line, line: []const u8) !void {
    var s = split(u8, line, ";");
    var i: u8 = 0;
    while (s.next()) |l| {
        switch (i) {
            0 => {
                try ln.set_name(l);
            },
            1 => {
                const temp = try simpleFloatParse(l);
                ln.temp = temp;
            },
            99 => break,
            else => break,
        }

        i += 1;
    }
}

const @"48": f64 = 48;

fn simpleFloatParse(str: []const u8) !f64 {
    var v: i32 = 0;
    var negative = false;
    for (str) |s| {
        switch (s) {
            '-' => negative = true,
            '0'...'9' => {
                v *= 10;
                v += s - '0';
            },
            else => {},
        }
    }

    if (negative) {
        v *= -1;
    }
    return @as(f64, @floatFromInt(v)) / 10;
}

test "simpleFloatParse" {
    const testing = std.testing;

    try testing.expectEqual(1.2, try simpleFloatParse("1.2"));
    try testing.expectEqual(-1.2, try simpleFloatParse("-1.2"));

    try testing.expectEqual(10.23, try simpleFloatParse("10.23"));
    try testing.expectEqual(-10.23, try simpleFloatParse("-10.23"));
}

test "parseLine" {
    const testing = std.testing;
    const allocator = std.testing.allocator;
    var ln = try Line.init(allocator);
    defer ln.deinit();

    const text_line_1 = "Kansas City;-0.8";
    try parseLine(&ln, text_line_1);
    try testing.expect(std.mem.startsWith(u8, ln.name, "Kansas City"));
    try testing.expect(ln.temp == -0.8);

    const text_line_2 = "Damascus;19.8";
    try parseLine(&ln, text_line_2);
    try testing.expect(std.mem.startsWith(u8, ln.name, "Damascus"));
    try testing.expect(ln.temp == 19.8);

    const text_line_3 = "Kansas City;28.0";
    try parseLine(&ln, text_line_3);
    try testing.expect(std.mem.startsWith(u8, ln.name, "Kansas City"));
    try testing.expect(ln.temp == 28.0);

    const text_line_4 = "La Ceiba;17.0";
    try parseLine(&ln, text_line_4);
    try testing.expect(std.mem.startsWith(u8, ln.name, "La Ceiba"));
    try testing.expect(ln.temp == 17.0);
}
