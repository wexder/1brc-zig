const std = @import("std");
const split = std.mem.splitAny;
const fs = std.fs;
const print = std.debug.print;
const assert = std.debug.assert;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    var tsa = std.heap.ThreadSafeAllocator{
        .child_allocator = arena.allocator(),
    };
    defer arena.deinit();
    const allocator = tsa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const file_name = args[1];
    const file = try std.fs.cwd().openFile(file_name, .{ .mode = .read_only });
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

    var pool: std.Thread.Pool = undefined;
    try pool.init(std.Thread.Pool.Options{
        .allocator = allocator,
    });
    var wg = std.Thread.WaitGroup{};

    var city_map = std.StringHashMap(City).init(allocator);
    var ctx = WorkerCtx{
        .city_map = &city_map,
    };
    var main_lock = std.Thread.Mutex{};

    var chunk_start: usize = 0;
    const job_count = if (file_len < 1_000_000) 1 else try std.Thread.getCpuCount() - 1;
    for (0..job_count) |i| {
        const search_start = mapped_mem.len / job_count * (i + 1);
        const chunk_end = std.mem.indexOfScalarPos(u8, mapped_mem, search_start, '\n') orelse mapped_mem.len;
        wg.start();
        try pool.spawn(threadRun, .{ allocator, mapped_mem[chunk_start..chunk_end], &ctx, &wg, &main_lock });
        chunk_start = chunk_end + 1;
        if (chunk_start >= mapped_mem.len) break;
    }
    wg.wait();

    var cities = std.ArrayList([]const u8).init(allocator);
    defer cities.deinit();

    var iter = city_map.keyIterator();
    while (iter.next()) |k| {
        try cities.append(k.*);
    }

    std.mem.sortUnstable([]const u8, cities.items, {}, strLessThan);
    for (cities.items) |c| {
        if (c.len == 0) {
            continue;
        }
        const city = city_map.get(c) orelse continue;
        const count: f64 = @floatFromInt(city.count);
        print("{s} min: {d}, max: {d}, avg: {d}\n", .{ c, city.min, city.max, city.sum / count });
    }
}
const MAP_CAPACITY = 512 * 2 * 2;

const WorkerCtx = struct {
    city_map: *std.StringHashMap(City),
};

fn threadRun(
    allocator: std.mem.Allocator,
    mapped_mem: []u8,
    ctx: *WorkerCtx,
    wg: *std.Thread.WaitGroup,
    lock: *std.Thread.Mutex,
) void {
    defer wg.finish();
    var ln = try Line.init();
    defer ln.deinit();
    var city_map = std.StringHashMap(City).init(allocator);

    var last_n: u64 = 0;
    for (mapped_mem, 0..) |b, i| {
        if (b == '\n') {
            parseLine(&ln, mapped_mem[last_n..i]) catch break;
            const key = mapped_mem[last_n .. last_n + ln.name_length];

            const city = city_map.getOrPut(key) catch break;
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

            last_n = i + 1;
        }
    }

    var iter = city_map.iterator();
    lock.lock();
    while (iter.next()) |kv| {
        const city = ctx.city_map.getOrPut(kv.key_ptr.*) catch return;
        if (city.found_existing) {
            city.value_ptr.*.merge(kv.value_ptr);
        } else {
            city.value_ptr.* = kv.value_ptr.*;
        }
    }
    lock.unlock();
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

    pub fn merge(self: *Self, item: *Self) void {
        self.min = @min(self.min, item.min);
        self.max = @max(self.max, item.max);
        self.sum += item.sum;
        self.count += 1;
    }

    pub fn addItem(self: *Self, item: f64) void {
        self.min = @min(self.min, item);
        self.max = @max(self.max, item);
        self.sum += item;
        self.count += 1;
    }
};

const Line = struct {
    const Self = @This();

    name_length: usize,
    temp: f64,

    fn init() !Line {
        return Line{
            .name_length = 0,
            .temp = 0,
        };
    }

    fn deinit(self: Self) void {
        _ = self;
    }
};

// This is missing input checking intentionally
fn parseLine(ln: *Line, line: []const u8) !void {
    const div = std.mem.indexOfScalarPos(u8, line, 0, ';') orelse line.len;
    ln.name_length = div;
    const temp = try simpleFloatParse(line[div..]);
    ln.temp = temp;
}

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
