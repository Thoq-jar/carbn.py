const std = @import("std");
const Allocator = std.mem.Allocator;

pub const ValueType = enum {
    integer,
    big_integer,
    float,
    string,
    boolean,
    array,
    null_value,
};

pub const Value = union(ValueType) {
    integer: i64,
    big_integer: i128,
    float: f64,
    string: []const u8,
    boolean: bool,
    array: []Value,
    null_value: void,

    const Self = @This();

    pub fn createValue(allocator: Allocator, value: anytype) !Self {
        const T = @TypeOf(value);
        return switch (@typeInfo(T)) {
            .Int => |info| {

                if (info.bits <= 64 or @as(i128, value) >= std.math.minInt(i64) and @as(i128, value) <= std.math.maxInt(i64)) {
                    return Self{ .integer = @intCast(value) };
                } else {

                    return Self{ .big_integer = @intCast(value) };
                }
            },
            .Float => Self{ .float = @floatCast(value) },
            .Bool => Self{ .boolean = value },
            .Null => Self{ .null_value = {} },
            .Pointer => |ptr| {
                if (ptr.child == u8) {
                    return Self{ .string = try allocator.dupe(u8, value) };
                } else {
                    @compileError("Unsupported pointer type");
                }
            },
            else => @compileError("Unsupported type"),
        };
    }

    pub fn toString(self: Self, allocator: Allocator) ![]u8 {
        switch (self) {
            .integer => |i| {

                if (i >= 0 and i < 10) {
                    var buf = try allocator.alloc(u8, 1);
                    buf[0] = '0' + @as(u8, @intCast(i));
                    return buf;
                }
                return std.fmt.allocPrint(allocator, "{d}", .{i});
            },
            .big_integer => |i| {

                return std.fmt.allocPrint(allocator, "{d}", .{i});
            },
            .float => |f| return std.fmt.allocPrint(allocator, "{d}", .{f}),
            .string => |s| return allocator.dupe(u8, s),
            .boolean => |b| {
                const str = if (b) "true" else "false";
                return allocator.dupe(u8, str);
            },
            .array => |arr| {
                var result = std.ArrayList(u8).init(allocator);
                try result.append('[');
                for (arr, 0..) |item, i| {
                    if (i > 0) try result.appendSlice(", ");
                    const item_str = try item.toString(allocator);
                    defer allocator.free(item_str);
                    try result.appendSlice(item_str);
                }
                try result.append(']');
                return result.toOwnedSlice();
            },
            .null_value => return allocator.dupe(u8, "null"),
        }
    }

    pub fn toBool(self: Self) bool {
        switch (self) {
            .integer => |i| return i != 0,
            .big_integer => |i| return i != 0,
            .float => |f| return f != 0.0,
            .string => |s| return s.len > 0,
            .boolean => |b| return b,
            .array => |arr| return arr.len > 0,
            .null_value => return false,
        }
    }

    pub fn toInt(self: Self) !i64 {
        switch (self) {
            .integer => |i| return i,
            .big_integer => |i| {

                if (i > std.math.maxInt(i64) or i < std.math.minInt(i64)) {
                    return error.IntegerOverflow;
                }
                return @intCast(i);
            },
            .float => |f| return @intFromFloat(f),
            .string => |s| return std.fmt.parseInt(i64, s, 10),
            .boolean => |b| return if (b) 1 else 0,
            else => return error.InvalidCast,
        }
    }

    pub fn toBigInt(self: Self) !i128 {
        switch (self) {
            .integer => |i| return @as(i128, i),
            .big_integer => |i| return i,
            .float => |f| return @intFromFloat(f),
            .string => |s| return std.fmt.parseInt(i128, s, 10),
            .boolean => |b| return if (b) 1 else 0,
            else => return error.InvalidCast,
        }
    }

    pub fn toFloat(self: Self) !f64 {
        switch (self) {
            .integer => |i| return @floatFromInt(i),
            .big_integer => |i| return @floatFromInt(i),
            .float => |f| return f,
            .string => |s| return std.fmt.parseFloat(f64, s),
            .boolean => |b| return if (b) 1.0 else 0.0,
            else => return error.InvalidCast,
        }
    }

    pub fn equals(self: Self, other: Self) bool {
        switch (self) {
            .integer => |a| switch (other) {
                .integer => |b| return a == b,
                .big_integer => |b| return @as(i128, a) == b,
                .float => |b| return @as(f64, @floatFromInt(a)) == b,
                else => return false,
            },
            .big_integer => |a| switch (other) {
                .big_integer => |b| return a == b,
                .integer => |b| return a == @as(i128, b),
                .float => |b| return @as(f64, @floatFromInt(a)) == b,
                else => return false,
            },
            .float => |a| switch (other) {
                .float => |b| return a == b,
                .integer => |b| return a == @as(f64, @floatFromInt(b)),
                .big_integer => |b| return a == @as(f64, @floatFromInt(b)),
                else => return false,
            },
            .string => |a| switch (other) {
                .string => |b| return std.mem.eql(u8, a, b),
                else => return false,
            },
            .boolean => |a| switch (other) {
                .boolean => |b| return a == b,
                else => return false,
            },
            .null_value => switch (other) {
                .null_value => return true,
                else => return false,
            },
            .array => |a| switch (other) {
                .array => |b| {
                    if (a.len != b.len) return false;
                    for (a, b) |item_a, item_b| {
                        if (!item_a.equals(item_b)) return false;
                    }
                    return true;
                },
                else => return false,
            },
        }
    }

    pub fn deinit(self: Self, allocator: Allocator) void {
        switch (self) {
            .string => |s| allocator.free(s),
            .array => |arr| {
                for (arr) |item| {
                    item.deinit(allocator);
                }
                allocator.free(arr);
            },
            else => {},
        }
    }
};