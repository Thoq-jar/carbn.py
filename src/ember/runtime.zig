const std = @import("std");
const Value = @import("value.zig").Value;
const OpCode = @import("opcodes.zig").OpCode;
const io = @import("io.zig");

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const HashMap = std.HashMap;

pub const RuntimeError = error{
StackUnderflow,
InvalidOpcode,
DivisionByZero,
IndexOutOfBounds,
InvalidCast,
OutOfMemory,
InvalidJump,
};

pub const CallFrame = struct {
    return_address: usize,
    base_pointer: usize,
    local_vars: std.StringHashMap(Value),

    local_var_buffer: [8]struct { key: []const u8, value: Value },
    local_var_count: usize,

    pub fn init(allocator: Allocator, return_addr: usize, base_ptr: usize) CallFrame {
        return .{
            .return_address = return_addr,
            .base_pointer = base_ptr,
            .local_vars = std.StringHashMap(Value).init(allocator),
            .local_var_buffer = undefined,
            .local_var_count = 0,
        };
    }

    pub fn getLocalVar(self: *CallFrame, name: []const u8) ?*Value {
        for (0..self.local_var_count) |i| {
            if (std.mem.eql(u8, self.local_var_buffer[i].key, name)) {
                return &self.local_var_buffer[i].value;
            }
        }

        return self.local_vars.getPtr(name);
    }

    pub fn putLocalVar(self: *CallFrame, allocator: Allocator, name: []const u8, value: Value) !void {
        if (self.local_var_count < self.local_var_buffer.len) {
            for (0..self.local_var_count) |i| {
                if (std.mem.eql(u8, self.local_var_buffer[i].key, name)) {
                    self.local_var_buffer[i].value.deinit(allocator);

                    self.local_var_buffer[i].value = value;
                    return;
                }
            }

            const owned_name = try allocator.dupe(u8, name);
            self.local_var_buffer[self.local_var_count] = .{ .key = owned_name, .value = value };
            self.local_var_count += 1;
            return;
        }

        const owned_name = try allocator.dupe(u8, name);
        const result = try self.local_vars.getOrPut(owned_name);
        if (result.found_existing) {
            result.value_ptr.deinit(allocator);
            allocator.free(owned_name);
        }
        result.value_ptr.* = value;
    }

    pub fn deinit(self: *CallFrame, allocator: Allocator) void {
        for (0..self.local_var_count) |i| {
            allocator.free(self.local_var_buffer[i].key);
            self.local_var_buffer[i].value.deinit(allocator);
        }

        var iterator = self.local_vars.iterator();
        while (iterator.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            entry.value_ptr.deinit(allocator);
        }
        self.local_vars.deinit();
    }
};

pub const Runtime = struct {
    allocator: Allocator,
    stack: ArrayList(Value),
    call_stack: ArrayList(CallFrame),
    variables: std.StringHashMap(Value),
    current_loop_index: u64,
    loop_end: u64,

    const Self = @This();

    pub fn init(allocator: Allocator) Self {
        return .{
            .allocator = allocator,
            .stack = ArrayList(Value).init(allocator),
            .call_stack = ArrayList(CallFrame).init(allocator),
            .variables = std.StringHashMap(Value).init(allocator),
            .current_loop_index = 0,
            .loop_end = 0,
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.stack.items) |value| {
            value.deinit(self.allocator);
        }

        var iterator = self.variables.iterator();
        while (iterator.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            entry.value_ptr.deinit(self.allocator);
        }

        for (self.call_stack.items) |*frame| {
            frame.deinit(self.allocator);
        }

        self.stack.deinit();
        self.call_stack.deinit();
        self.variables.deinit();
    }

    fn push(self: *Self, value: Value) !void {
        try self.stack.append(value);
    }

    fn pop(self: *Self) !Value {
        if (self.stack.items.len == 0) return RuntimeError.StackUnderflow;
        return self.stack.pop().?;
    }

    fn peek(self: *Self) !Value {
        if (self.stack.items.len == 0) return RuntimeError.StackUnderflow;
        return self.stack.items[self.stack.items.len - 1];
    }

    fn readU8(code: []const u8, ip: *usize) u8 {
        const val = code[ip.*];
        ip.* += 1;
        return val;
    }

    fn readU64(code: []const u8, ip: *usize) u64 {
        const val = @as(u64, code[ip.*]) << 56 |
            @as(u64, code[ip.* + 1]) << 48 |
            @as(u64, code[ip.* + 2]) << 40 |
            @as(u64, code[ip.* + 3]) << 32 |
            @as(u64, code[ip.* + 4]) << 24 |
            @as(u64, code[ip.* + 5]) << 16 |
            @as(u64, code[ip.* + 6]) << 8 |
            @as(u64, code[ip.* + 7]);
        ip.* += 8;
        return val;
    }

    fn readF64(code: []const u8, ip: *usize) f64 {
        const bytes = code[ip.* .. ip.* + 8];
        ip.* += 8;
        return @bitCast(std.mem.readInt(u64, bytes[0..8], .big));
    }

    fn readString(self: *Self, code: []const u8, ip: *usize) !Value {
        const len = readU8(code, ip);
        const str = code[ip.* .. ip.* + len];
        ip.* += len;

        return Value{ .string = try self.allocator.dupe(u8, str) };
    }

    fn getCurrentVariables(self: *Self) *std.StringHashMap(Value) {
        if (self.call_stack.items.len > 0) {
            return &self.call_stack.items[self.call_stack.items.len - 1].local_vars;
        } else {
            return &self.variables;
        }
    }

    fn getVariable(self: *Self, name: []const u8) ?*Value {
        if (self.call_stack.items.len > 0) {
            if (self.call_stack.items[self.call_stack.items.len - 1].getLocalVar(name)) |value| {
                return value;
            }
        }

        return self.variables.getPtr(name);
    }

    fn storeVariable(self: *Self, name: []const u8, value: Value) !void {
        if (self.call_stack.items.len > 0) {
            try self.call_stack.items[self.call_stack.items.len - 1].putLocalVar(self.allocator, name, value);
        } else {
            const owned_name = try self.allocator.dupe(u8, name);
            const result = try self.variables.getOrPut(owned_name);
            if (result.found_existing) {
                result.value_ptr.deinit(self.allocator);
                self.allocator.free(owned_name);
            }
            result.value_ptr.* = value;
        }
    }

    pub fn execute(self: *Self, code: []const u8) !void {
        var ip: usize = 0;

        try self.stack.ensureTotalCapacity(256);

        while (ip < code.len) {
            const op = @as(OpCode, @enumFromInt(code[ip]));
            ip += 1;

            switch (op) {
                .PRINT => {
                    const value = try self.pop();
                    defer value.deinit(self.allocator);

                    const str = try value.toString(self.allocator);
                    defer self.allocator.free(str);

                    io.printRuntime(str);
                    io.printRuntime("\n");
                },

                .LOAD_CONST => {
                    const value = try self.readString(code, &ip);
                    try self.push(value);
                },

                .LOAD_INT => {
                    const val = readU64(code, &ip);
                    try self.push(.{ .integer = @intCast(@as(i64, @bitCast(val))) });
                },

                .LOAD_FLOAT => {
                    const val = readF64(code, &ip);
                    try self.push(.{ .float = val });
                },

                .LOAD_BOOL => {
                    const val = readU64(code, &ip);
                    try self.push(.{ .boolean = val != 0 });
                },

                .LOAD_VAR => {
                    const name_value = try self.readString(code, &ip);

                    const name = name_value.string;

                    defer self.allocator.free(name);

                    if (self.getVariable(name)) |value_ptr| {
                        const value = value_ptr.*;
                        const copied = switch (value) {
                            .string => |s| Value{ .string = try self.allocator.dupe(u8, s) },
                            .array => |arr| blk: {
                                var new_arr = try self.allocator.alloc(Value, arr.len);
                                for (arr, 0..) |item, i| {
                                    new_arr[i] = switch (item) {
                                        .string => |s| Value{ .string = try self.allocator.dupe(u8, s) },
                                        .array => |nested_arr| nested_blk: {
                                            var nested_new_arr = try self.allocator.alloc(Value, nested_arr.len);
                                            for (nested_arr, 0..) |nested_item, j| {
                                                nested_new_arr[j] = switch (nested_item) {
                                                    .string => |ns| Value{ .string = try self.allocator.dupe(u8, ns) },
                                                    else => nested_item,
                                                };
                                            }
                                            break :nested_blk Value{ .array = nested_new_arr };
                                        },
                                        .integer, .big_integer, .float, .boolean, .null_value => item,
                                    };
                                }
                                break :blk Value{ .array = new_arr };
                            },
                            .integer, .big_integer, .float, .boolean, .null_value => value,
                        };
                        try self.push(copied);
                    } else {
                        try self.push(.{ .integer = 0 });
                    }
                },

                .STORE => {
                    const name_value = try self.readString(code, &ip);
                    const value = try self.pop();

                    const name = name_value.string;

                    try self.storeVariable(name, value);

                    self.allocator.free(name);
                },

                .STDIN => {
                    var buf: [1024]u8 = undefined;
                    const input = try std.io.getStdIn().reader().readUntilDelimiter(&buf, '\n');
                    const str = try self.allocator.dupe(u8, input);
                    try self.push(.{ .string = str });
                },

                .ADD => {
                    if (self.stack.items.len >= 2) {
                        const len = self.stack.items.len;
                        const a = self.stack.items[len - 2];
                        const b = self.stack.items[len - 1];

                        if (a == .integer and b == .integer) {

                            const ai: i128 = a.integer;
                            const bi: i128 = b.integer;
                            const sum: i128 = ai + bi;

                            if (sum >= std.math.minInt(i64) and sum <= std.math.maxInt(i64)) {
                                const result = Value{ .integer = @intCast(sum) };
                                _ = self.stack.pop();
                                _ = self.stack.pop();
                                try self.push(result);
                            } else {

                                const result = Value{ .big_integer = sum };
                                _ = self.stack.pop();
                                _ = self.stack.pop();
                                try self.push(result);
                            }
                            continue;
                        } else if (a == .big_integer and b == .big_integer) {
                            const result = Value{ .big_integer = a.big_integer + b.big_integer };
                            _ = self.stack.pop();
                            _ = self.stack.pop();
                            try self.push(result);
                            continue;
                        } else if (a == .integer and b == .big_integer) {
                            const result = Value{ .big_integer = @as(i128, a.integer) + b.big_integer };
                            _ = self.stack.pop();
                            _ = self.stack.pop();
                            try self.push(result);
                            continue;
                        } else if (a == .big_integer and b == .integer) {
                            const result = Value{ .big_integer = a.big_integer + @as(i128, b.integer) };
                            _ = self.stack.pop();
                            _ = self.stack.pop();
                            try self.push(result);
                            continue;
                        }
                    }

                    const b = try self.pop();
                    const a = try self.pop();
                    defer a.deinit(self.allocator);
                    defer b.deinit(self.allocator);

                    const result = switch (a) {
                        .integer => |ai| switch (b) {
                            .integer => |bi| blk: {

                                const a128: i128 = ai;
                                const b128: i128 = bi;
                                const sum: i128 = a128 + b128;

                                if (sum >= std.math.minInt(i64) and sum <= std.math.maxInt(i64)) {
                                    break :blk Value{ .integer = @intCast(sum) };
                                } else {

                                    break :blk Value{ .big_integer = sum };
                                }
                            },
                            .big_integer => |bi| Value{ .big_integer = @as(i128, ai) + bi },
                            .float => |bf| Value{ .float = @as(f64, @floatFromInt(ai)) + bf },
                            .string => |bs| blk: {
                                const as_str = try std.fmt.allocPrint(self.allocator, "{d}", .{ai});
                                defer self.allocator.free(as_str);
                                const combined = try std.fmt.allocPrint(self.allocator, "{s}{s}", .{ as_str, bs });
                                break :blk Value{ .string = combined };
                            },
                            .boolean => |bb| blk: {
                                const as_str = try std.fmt.allocPrint(self.allocator, "{d}", .{ai});
                                defer self.allocator.free(as_str);
                                const bs_str = if (bb) "true" else "false";
                                const combined = try std.fmt.allocPrint(self.allocator, "{s}{s}", .{ as_str, bs_str });
                                break :blk Value{ .string = combined };
                            },
                            else => return RuntimeError.InvalidCast,
                        },
                        .big_integer => |ai| switch (b) {
                            .integer => |bi| Value{ .big_integer = ai + @as(i128, bi) },
                            .big_integer => |bi| Value{ .big_integer = ai + bi },
                            .float => |bf| Value{ .float = @as(f64, @floatFromInt(ai)) + bf },
                            .string => |bs| blk: {
                                const as_str = try std.fmt.allocPrint(self.allocator, "{d}", .{ai});
                                defer self.allocator.free(as_str);
                                const combined = try std.fmt.allocPrint(self.allocator, "{s}{s}", .{ as_str, bs });
                                break :blk Value{ .string = combined };
                            },
                            .boolean => |bb| blk: {
                                const as_str = try std.fmt.allocPrint(self.allocator, "{d}", .{ai});
                                defer self.allocator.free(as_str);
                                const bs_str = if (bb) "true" else "false";
                                const combined = try std.fmt.allocPrint(self.allocator, "{s}{s}", .{ as_str, bs_str });
                                break :blk Value{ .string = combined };
                            },
                            else => return RuntimeError.InvalidCast,
                        },
                        .float => |af| switch (b) {
                            .integer => |bi| Value{ .float = af + @as(f64, @floatFromInt(bi)) },
                            .float => |bf| Value{ .float = af + bf },
                            .string => |bs| blk: {
                                const as_str = try std.fmt.allocPrint(self.allocator, "{d}", .{af});
                                defer self.allocator.free(as_str);
                                const combined = try std.fmt.allocPrint(self.allocator, "{s}{s}", .{ as_str, bs });
                                break :blk Value{ .string = combined };
                            },
                            .boolean => |bb| blk: {
                                const as_str = try std.fmt.allocPrint(self.allocator, "{d}", .{af});
                                defer self.allocator.free(as_str);
                                const bs_str = if (bb) "true" else "false";
                                const combined = try std.fmt.allocPrint(self.allocator, "{s}{s}", .{ as_str, bs_str });
                                break :blk Value{ .string = combined };
                            },
                            else => return RuntimeError.InvalidCast,
                        },
                        .string => |as| switch (b) {
                            .string => |bs| blk: {
                                const combined = try std.fmt.allocPrint(self.allocator, "{s}{s}", .{ as, bs });
                                break :blk Value{ .string = combined };
                            },
                            .integer => |bi| blk: {
                                const bs_str = try std.fmt.allocPrint(self.allocator, "{d}", .{bi});
                                defer self.allocator.free(bs_str);
                                const combined = try std.fmt.allocPrint(self.allocator, "{s}{s}", .{ as, bs_str });
                                break :blk Value{ .string = combined };
                            },
                            .big_integer => |bi| blk: {
                                const bs_str = try std.fmt.allocPrint(self.allocator, "{d}", .{bi});
                                defer self.allocator.free(bs_str);
                                const combined = try std.fmt.allocPrint(self.allocator, "{s}{s}", .{ as, bs_str });
                                break :blk Value{ .string = combined };
                            },
                            .float => |bf| blk: {
                                const bs_str = try std.fmt.allocPrint(self.allocator, "{d}", .{bf});
                                defer self.allocator.free(bs_str);
                                const combined = try std.fmt.allocPrint(self.allocator, "{s}{s}", .{ as, bs_str });
                                break :blk Value{ .string = combined };
                            },
                            .boolean => |bb| blk: {
                                const bs_str = if (bb) "true" else "false";
                                const combined = try std.fmt.allocPrint(self.allocator, "{s}{s}", .{ as, bs_str });
                                break :blk Value{ .string = combined };
                            },
                            else => return RuntimeError.InvalidCast,
                        },
                        .boolean => |ab| switch (b) {
                            .string => |bs| blk: {
                                const as_str = if (ab) "true" else "false";
                                const combined = try std.fmt.allocPrint(self.allocator, "{s}{s}", .{ as_str, bs });
                                break :blk Value{ .string = combined };
                            },
                            .integer => |bi| blk: {
                                const as_str = if (ab) "true" else "false";
                                const bs_str = try std.fmt.allocPrint(self.allocator, "{d}", .{bi});
                                defer self.allocator.free(bs_str);
                                const combined = try std.fmt.allocPrint(self.allocator, "{s}{s}", .{ as_str, bs_str });
                                break :blk Value{ .string = combined };
                            },
                            .big_integer => |bi| blk: {
                                const as_str = if (ab) "true" else "false";
                                const bs_str = try std.fmt.allocPrint(self.allocator, "{d}", .{bi});
                                defer self.allocator.free(bs_str);
                                const combined = try std.fmt.allocPrint(self.allocator, "{s}{s}", .{ as_str, bs_str });
                                break :blk Value{ .string = combined };
                            },
                            .float => |bf| blk: {
                                const as_str = if (ab) "true" else "false";
                                const bs_str = try std.fmt.allocPrint(self.allocator, "{d}", .{bf});
                                defer self.allocator.free(bs_str);
                                const combined = try std.fmt.allocPrint(self.allocator, "{s}{s}", .{ as_str, bs_str });
                                break :blk Value{ .string = combined };
                            },
                            .boolean => |bb| blk: {
                                const as_str = if (ab) "true" else "false";
                                const bs_str = if (bb) "true" else "false";
                                const combined = try std.fmt.allocPrint(self.allocator, "{s}{s}", .{ as_str, bs_str });
                                break :blk Value{ .string = combined };
                            },
                            else => return RuntimeError.InvalidCast,
                        },
                        else => return RuntimeError.InvalidCast,
                    };
                    try self.push(result);
                },

                .SUB, .MUL, .DIV, .MOD => {
                    if (self.stack.items.len >= 2) {
                        const len = self.stack.items.len;
                        const a = self.stack.items[len - 2];
                        const b = self.stack.items[len - 1];

                        if (a == .integer and b == .integer) {
                            if (op == .DIV and b.integer == 0) return RuntimeError.DivisionByZero;
                            if (op == .MOD and b.integer == 0) return RuntimeError.DivisionByZero;

                            const ai: i128 = a.integer;
                            const bi: i128 = b.integer;

                            var result_i128: i128 = undefined;
                            switch (op) {
                                .SUB => result_i128 = ai - bi,
                                .MUL => result_i128 = ai * bi,
                                .DIV => result_i128 = @divTrunc(ai, bi),
                                .MOD => result_i128 = @mod(ai, bi),
                                else => unreachable,
                            }

                            if (result_i128 >= std.math.minInt(i64) and result_i128 <= std.math.maxInt(i64)) {
                                const result = switch (op) {
                                    .SUB => Value{ .integer = @intCast(result_i128) },
                                    .MUL => Value{ .integer = @intCast(result_i128) },
                                    .DIV => Value{ .integer = @intCast(result_i128) },
                                    .MOD => Value{ .integer = @intCast(result_i128) },
                                    else => unreachable,
                                };
                                _ = self.stack.pop();
                                _ = self.stack.pop();
                                try self.push(result);
                            } else {

                                const result = switch (op) {
                                    .SUB => Value{ .big_integer = result_i128 },
                                    .MUL => Value{ .big_integer = result_i128 },
                                    .DIV => Value{ .big_integer = result_i128 },
                                    .MOD => Value{ .big_integer = result_i128 },
                                    else => unreachable,
                                };
                                _ = self.stack.pop();
                                _ = self.stack.pop();
                                try self.push(result);
                            }
                            continue;
                        }

                        else if (a == .big_integer and b == .big_integer) {
                            if (op == .DIV and b.big_integer == 0) return RuntimeError.DivisionByZero;
                            if (op == .MOD and b.big_integer == 0) return RuntimeError.DivisionByZero;

                            const result = switch (op) {
                                .SUB => Value{ .big_integer = a.big_integer - b.big_integer },
                                .MUL => Value{ .big_integer = a.big_integer * b.big_integer },
                                .DIV => Value{ .big_integer = @divTrunc(a.big_integer, b.big_integer) },
                                .MOD => Value{ .big_integer = @mod(a.big_integer, b.big_integer) },
                                else => unreachable,
                            };
                            _ = self.stack.pop();
                            _ = self.stack.pop();
                            try self.push(result);
                            continue;
                        }

                        else if (a == .integer and b == .big_integer) {
                                if (op == .DIV and b.big_integer == 0) return RuntimeError.DivisionByZero;
                                if (op == .MOD and b.big_integer == 0) return RuntimeError.DivisionByZero;

                                const result = switch (op) {
                                    .SUB => Value{ .big_integer = @as(i128, a.integer) - b.big_integer },
                                    .MUL => Value{ .big_integer = @as(i128, a.integer) * b.big_integer },
                                    .DIV => Value{ .big_integer = @divTrunc(@as(i128, a.integer), b.big_integer) },
                                    .MOD => Value{ .big_integer = @mod(@as(i128, a.integer), b.big_integer) },
                                    else => unreachable,
                                };
                                _ = self.stack.pop();
                                _ = self.stack.pop();
                                try self.push(result);
                                continue;
                            }
                            else if (a == .big_integer and b == .integer) {
                                    if (op == .DIV and b.integer == 0) return RuntimeError.DivisionByZero;
                                    if (op == .MOD and b.integer == 0) return RuntimeError.DivisionByZero;

                                    const result = switch (op) {
                                        .SUB => Value{ .big_integer = a.big_integer - @as(i128, b.integer) },
                                        .MUL => Value{ .big_integer = a.big_integer * @as(i128, b.integer) },
                                        .DIV => Value{ .big_integer = @divTrunc(a.big_integer, @as(i128, b.integer)) },
                                        .MOD => Value{ .big_integer = @mod(a.big_integer, @as(i128, b.integer)) },
                                        else => unreachable,
                                    };
                                    _ = self.stack.pop();
                                    _ = self.stack.pop();
                                    try self.push(result);
                                    continue;
                                }
                    }

                    const b = try self.pop();
                    const a = try self.pop();
                    defer a.deinit(self.allocator);
                    defer b.deinit(self.allocator);

                    const result = switch (a) {
                        .integer => |ai| switch (b) {
                            .integer => |bi| blk: {
                                if (op == .DIV and bi == 0) return RuntimeError.DivisionByZero;
                                if (op == .MOD and bi == 0) return RuntimeError.DivisionByZero;

                                const a128: i128 = ai;
                                const b128: i128 = bi;

                                var result_i128: i128 = undefined;
                                switch (op) {
                                    .SUB => result_i128 = a128 - b128,
                                    .MUL => result_i128 = a128 * b128,
                                    .DIV => result_i128 = @divTrunc(a128, b128),
                                    .MOD => result_i128 = @mod(a128, b128),
                                    else => unreachable,
                                }

                                if (result_i128 >= std.math.minInt(i64) and result_i128 <= std.math.maxInt(i64)) {
                                    break :blk switch (op) {
                                        .SUB => Value{ .integer = @intCast(result_i128) },
                                        .MUL => Value{ .integer = @intCast(result_i128) },
                                        .DIV => Value{ .integer = @intCast(result_i128) },
                                        .MOD => Value{ .integer = @intCast(result_i128) },
                                        else => unreachable,
                                    };
                                } else {

                                    break :blk switch (op) {
                                        .SUB => Value{ .big_integer = result_i128 },
                                        .MUL => Value{ .big_integer = result_i128 },
                                        .DIV => Value{ .big_integer = result_i128 },
                                        .MOD => Value{ .big_integer = result_i128 },
                                        else => unreachable,
                                    };
                                }
                            },
                            .big_integer => |bi| blk: {
                                if (op == .DIV and bi == 0) return RuntimeError.DivisionByZero;
                                if (op == .MOD and bi == 0) return RuntimeError.DivisionByZero;

                                break :blk switch (op) {
                                    .SUB => Value{ .big_integer = @as(i128, ai) - bi },
                                    .MUL => Value{ .big_integer = @as(i128, ai) * bi },
                                    .DIV => Value{ .big_integer = @divTrunc(@as(i128, ai), bi) },
                                    .MOD => Value{ .big_integer = @mod(@as(i128, ai), bi) },
                                    else => unreachable,
                                };
                            },
                            .float => |bf| blk: {
                                if (op == .DIV and bf == 0.0) return RuntimeError.DivisionByZero;
                                const af = @as(f64, @floatFromInt(ai));
                                break :blk switch (op) {
                                    .SUB => Value{ .float = af - bf },
                                    .MUL => Value{ .float = af * bf },
                                    .DIV => Value{ .float = af / bf },
                                    .MOD => Value{ .float = @mod(af, bf) },
                                    else => unreachable,
                                };
                            },
                            else => return RuntimeError.InvalidCast,
                        },
                        .big_integer => |ai| switch (b) {
                            .integer => |bi| blk: {
                                if (op == .DIV and bi == 0) return RuntimeError.DivisionByZero;
                                if (op == .MOD and bi == 0) return RuntimeError.DivisionByZero;

                                break :blk switch (op) {
                                    .SUB => Value{ .big_integer = ai - @as(i128, bi) },
                                    .MUL => Value{ .big_integer = ai * @as(i128, bi) },
                                    .DIV => Value{ .big_integer = @divTrunc(ai, @as(i128, bi)) },
                                    .MOD => Value{ .big_integer = @mod(ai, @as(i128, bi)) },
                                    else => unreachable,
                                };
                            },
                            .big_integer => |bi| blk: {
                                if (op == .DIV and bi == 0) return RuntimeError.DivisionByZero;
                                if (op == .MOD and bi == 0) return RuntimeError.DivisionByZero;

                                break :blk switch (op) {
                                    .SUB => Value{ .big_integer = ai - bi },
                                    .MUL => Value{ .big_integer = ai * bi },
                                    .DIV => Value{ .big_integer = @divTrunc(ai, bi) },
                                    .MOD => Value{ .big_integer = @mod(ai, bi) },
                                    else => unreachable,
                                };
                            },
                            .float => |bf| blk: {
                                if (op == .DIV and bf == 0.0) return RuntimeError.DivisionByZero;
                                const af = @as(f64, @floatFromInt(ai));
                                break :blk switch (op) {
                                    .SUB => Value{ .float = af - bf },
                                    .MUL => Value{ .float = af * bf },
                                    .DIV => Value{ .float = af / bf },
                                    .MOD => Value{ .float = @mod(af, bf) },
                                    else => unreachable,
                                };
                            },
                            else => return RuntimeError.InvalidCast,
                        },
                        .float => |af| switch (b) {
                            .integer => |bi| blk: {
                                const bf = @as(f64, @floatFromInt(bi));
                                if (op == .DIV and bf == 0.0) return RuntimeError.DivisionByZero;
                                break :blk switch (op) {
                                    .SUB => Value{ .float = af - bf },
                                    .MUL => Value{ .float = af * bf },
                                    .DIV => Value{ .float = af / bf },
                                    .MOD => Value{ .float = @mod(af, bf) },
                                    else => unreachable,
                                };
                            },
                            .big_integer => |bi| blk: {
                                const bf = @as(f64, @floatFromInt(bi));
                                if (op == .DIV and bf == 0.0) return RuntimeError.DivisionByZero;
                                break :blk switch (op) {
                                    .SUB => Value{ .float = af - bf },
                                    .MUL => Value{ .float = af * bf },
                                    .DIV => Value{ .float = af / bf },
                                    .MOD => Value{ .float = @mod(af, bf) },
                                    else => unreachable,
                                };
                            },
                            .float => |bf| blk: {
                                if (op == .DIV and bf == 0.0) return RuntimeError.DivisionByZero;
                                break :blk switch (op) {
                                    .SUB => Value{ .float = af - bf },
                                    .MUL => Value{ .float = af * bf },
                                    .DIV => Value{ .float = af / bf },
                                    .MOD => Value{ .float = @mod(af, bf) },
                                    else => unreachable,
                                };
                            },
                            else => return RuntimeError.InvalidCast,
                        },
                        else => return RuntimeError.InvalidCast,
                    };
                    try self.push(result);
                },

                .EQ, .NE, .LT, .LE, .GT, .GE => {
                    if (self.stack.items.len >= 2) {
                        const len = self.stack.items.len;
                        const a = self.stack.items[len - 2];
                        const b = self.stack.items[len - 1];

                        if (a == .integer and b == .integer) {
                            const result = switch (op) {
                                .EQ => a.integer == b.integer,
                                .NE => a.integer != b.integer,
                                .LT => a.integer < b.integer,
                                .LE => a.integer <= b.integer,
                                .GT => a.integer > b.integer,
                                .GE => a.integer >= b.integer,
                                else => unreachable,
                            };
                            _ = self.stack.pop();
                            _ = self.stack.pop();
                            try self.push(.{ .boolean = result });
                            continue;
                        }
                    }

                    const b = try self.pop();
                    const a = try self.pop();
                    defer a.deinit(self.allocator);
                    defer b.deinit(self.allocator);

                    const result = switch (op) {
                        .EQ => a.equals(b),
                        .NE => !a.equals(b),
                        .LT => blk: {
                            break :blk switch (a) {
                                .integer => |ai| switch (b) {
                                    .integer => |bi| ai < bi,
                                    .big_integer => |bi| @as(i128, ai) < bi,
                                    .float => |bf| @as(f64, @floatFromInt(ai)) < bf,
                                    else => false,
                                },
                                .big_integer => |ai| switch (b) {
                                    .integer => |bi| ai < @as(i128, bi),
                                    .big_integer => |bi| ai < bi,
                                    .float => |bf| @as(f64, @floatFromInt(ai)) < bf,
                                    else => false,
                                },
                                .float => |af| switch (b) {
                                    .integer => |bi| af < @as(f64, @floatFromInt(bi)),
                                    .big_integer => |bi| af < @as(f64, @floatFromInt(bi)),
                                    .float => |bf| af < bf,
                                    else => false,
                                },
                                else => false,
                            };
                        },
                        .LE => blk: {
                            break :blk switch (a) {
                                .integer => |ai| switch (b) {
                                    .integer => |bi| ai <= bi,
                                    .big_integer => |bi| @as(i128, ai) <= bi,
                                    .float => |bf| @as(f64, @floatFromInt(ai)) <= bf,
                                    else => false,
                                },
                                .big_integer => |ai| switch (b) {
                                    .integer => |bi| ai <= @as(i128, bi),
                                    .big_integer => |bi| ai <= bi,
                                    .float => |bf| @as(f64, @floatFromInt(ai)) <= bf,
                                    else => false,
                                },
                                .float => |af| switch (b) {
                                    .integer => |bi| af <= @as(f64, @floatFromInt(bi)),
                                    .big_integer => |bi| af <= @as(f64, @floatFromInt(bi)),
                                    .float => |bf| af <= bf,
                                    else => false,
                                },
                                else => false,
                            };
                        },
                        .GT => blk: {
                            break :blk switch (a) {
                                .integer => |ai| switch (b) {
                                    .integer => |bi| ai > bi,
                                    .big_integer => |bi| @as(i128, ai) > bi,
                                    .float => |bf| @as(f64, @floatFromInt(ai)) > bf,
                                    else => false,
                                },
                                .big_integer => |ai| switch (b) {
                                    .integer => |bi| ai > @as(i128, bi),
                                    .big_integer => |bi| ai > bi,
                                    .float => |bf| @as(f64, @floatFromInt(ai)) > bf,
                                    else => false,
                                },
                                .float => |af| switch (b) {
                                    .integer => |bi| af > @as(f64, @floatFromInt(bi)),
                                    .big_integer => |bi| af > @as(f64, @floatFromInt(bi)),
                                    .float => |bf| af > bf,
                                    else => false,
                                },
                                else => false,
                            };
                        },
                        .GE => blk: {
                            const ge_result = switch (a) {
                                .integer => |ai| switch (b) {
                                    .integer => |bi| ai >= bi,
                                    .big_integer => |bi| @as(i128, ai) >= bi,
                                    .float => |bf| @as(f64, @floatFromInt(ai)) >= bf,
                                    else => false,
                                },
                                .big_integer => |ai| switch (b) {
                                    .integer => |bi| ai >= @as(i128, bi),
                                    .big_integer => |bi| ai >= bi,
                                    .float => |bf| @as(f64, @floatFromInt(ai)) >= bf,
                                    else => false,
                                },
                                .float => |af| switch (b) {
                                    .integer => |bi| af >= @as(f64, @floatFromInt(bi)),
                                    .big_integer => |bi| af >= @as(f64, @floatFromInt(bi)),
                                    .float => |bf| af >= bf,
                                    else => false,
                                },
                                else => false,
                            };
                            break :blk ge_result;
                        },
                        else => unreachable,
                    };
                    try self.push(.{ .boolean = result });
                },

                .AND => {
                    const b = try self.pop();
                    const a = try self.pop();
                    defer a.deinit(self.allocator);
                    defer b.deinit(self.allocator);

                    try self.push(.{ .boolean = a.toBool() and b.toBool() });
                },

                .OR => {
                    const b = try self.pop();
                    const a = try self.pop();
                    defer a.deinit(self.allocator);
                    defer b.deinit(self.allocator);

                    try self.push(.{ .boolean = a.toBool() or b.toBool() });
                },

                .NOT => {
                    const a = try self.pop();
                    defer a.deinit(self.allocator);

                    try self.push(.{ .boolean = !a.toBool() });
                },
                .JMP => {
                    const target = readU64(code, &ip);
                    if (target > code.len) {
                        return RuntimeError.InvalidJump;
                    }
                    ip = @intCast(target);
                },

                .JMP_IF_FALSE => {
                    const target = readU64(code, &ip);
                    const condition = try self.pop();
                    defer condition.deinit(self.allocator);

                    if (!condition.toBool()) {
                        if (target > code.len) {
                            return RuntimeError.InvalidJump;
                        }
                        ip = @intCast(target);
                    }
                },

                .JMP_IF_TRUE => {
                    const target = readU64(code, &ip);
                    const condition = try self.pop();
                    defer condition.deinit(self.allocator);

                    if (condition.toBool()) {
                        if (target > code.len) {
                            return RuntimeError.InvalidJump;
                        }
                        ip = @intCast(target);
                    }
                },

                .CALL => {
                    const target = readU64(code, &ip);

                    if (self.call_stack.items.len == self.call_stack.capacity) {
                        try self.call_stack.ensureUnusedCapacity(8);
                    }

                    const frame = CallFrame.init(self.allocator, ip, self.stack.items.len);
                    try self.call_stack.append(frame);

                    if (target > code.len) {
                        return RuntimeError.InvalidJump;
                    }
                    ip = @intCast(target);
                },

                .RET => {
                    if (self.call_stack.items.len == 0) {
                        return;
                    }

                    const return_address = self.call_stack.items[self.call_stack.items.len - 1].return_address;

                    var frame = self.call_stack.pop().?;
                    frame.deinit(self.allocator);

                    ip = return_address;
                },

                .DUP => {
                    if (self.stack.items.len > 0) {
                        const value = self.stack.items[self.stack.items.len - 1];
                        switch (value) {
                            .integer, .float, .boolean, .null_value => {
                                try self.push(value);
                                continue;
                            },
                            else => {},
                        }
                    }

                    const value = try self.peek();
                    const copied = switch (value) {
                        .string => |s| Value{ .string = try self.allocator.dupe(u8, s) },
                        .array => |arr| blk: {
                            var new_arr = try self.allocator.alloc(Value, arr.len);
                            for (arr, 0..) |item, i| {
                                new_arr[i] = switch (item) {
                                    .string => |s| Value{ .string = try self.allocator.dupe(u8, s) },
                                    else => item,
                                };
                            }
                            break :blk Value{ .array = new_arr };
                        },
                        else => value,
                    };
                    try self.push(copied);
                },

                .SWAP => {
                    if (self.stack.items.len < 2) return RuntimeError.StackUnderflow;
                    const len = self.stack.items.len;
                    const tmp = self.stack.items[len - 1];
                    self.stack.items[len - 1] = self.stack.items[len - 2];
                    self.stack.items[len - 2] = tmp;
                },

                .POP => {
                    const value = try self.pop();
                    value.deinit(self.allocator);
                },

                .ARRAY_NEW => {
                    const size = try self.pop();
                    defer size.deinit(self.allocator);

                    const len = try size.toInt();
                    const arr = try self.allocator.alloc(Value, @intCast(len));

                    for (arr) |*item| {
                        item.* = .{ .null_value = {} };
                    }

                    try self.push(.{ .array = arr });
                },

                .BUILD_LIST => {
                    const count = readU64(code, &ip);
                    const arr = try self.allocator.alloc(Value, @intCast(count));

                    var i: usize = @intCast(count);
                    while (i > 0) {
                        i -= 1;
                        arr[i] = try self.pop();
                    }

                    try self.push(.{ .array = arr });
                },

                .ARRAY_LEN => {
                    const arr_val = try self.pop();
                    defer arr_val.deinit(self.allocator);

                    switch (arr_val) {
                        .array => |arr| try self.push(.{ .integer = @intCast(arr.len) }),
                        .string => |s| try self.push(.{ .integer = @intCast(s.len) }),
                        else => return RuntimeError.InvalidCast,
                    }
                },

                .LOAD_NULL => {
                    try self.push(.{ .null_value = {} });
                },

                .IS_NULL => {
                    const value = try self.pop();
                    defer value.deinit(self.allocator);

                    try self.push(.{ .boolean = value == .null_value });
                },

                .LOOP_START => {
                    const start = readU64(code, &ip);
                    const end = readU64(code, &ip);
                    const loop_body_start = ip;

                    var nested: u64 = 0;
                    var loop_end_ip = ip;
                    while (loop_end_ip < code.len) : (loop_end_ip += 1) {
                        if (code[loop_end_ip] == @intFromEnum(OpCode.LOOP_START)) nested += 1;
                        if (code[loop_end_ip] == @intFromEnum(OpCode.LOOP_END)) {
                            if (nested == 0) break;
                            nested -= 1;
                        }
                    }

                    self.current_loop_index = start;
                    self.loop_end = end;

                    while (self.current_loop_index < self.loop_end) : (self.current_loop_index += 1) {
                        try self.execute(code[loop_body_start..loop_end_ip]);
                    }

                    ip = loop_end_ip + 1;
                },

                .LOOP_END => return,

                .CAST_INT => {
                    const value = try self.pop();
                    defer value.deinit(self.allocator);

                    if (value == .big_integer) {

                        if (value.big_integer > std.math.maxInt(i64) or value.big_integer < std.math.minInt(i64)) {

                            try self.push(.{ .big_integer = value.big_integer });
                        } else {

                            try self.push(.{ .integer = @intCast(value.big_integer) });
                        }
                    } else {

                        const int_val = try value.toInt();
                        try self.push(.{ .integer = int_val });
                    }
                },

                .CAST_FLOAT => {
                    const value = try self.pop();
                    defer value.deinit(self.allocator);

                    const float_val = try value.toFloat();
                    try self.push(.{ .float = float_val });
                },

                .BUILD_TUPLE => {
                    const count = readU64(code, &ip);
                    const arr = try self.allocator.alloc(Value, @intCast(count));

                    var i: usize = @intCast(count);
                    while (i > 0) {
                        i -= 1;
                        arr[i] = try self.pop();
                    }

                    try self.push(.{ .array = arr });
                },

                .BUILD_DICT => {
                    const count = readU64(code, &ip);

                    var i: usize = 0;
                    while (i < count * 2) : (i += 1) {
                        const val = try self.pop();
                        val.deinit(self.allocator);
                    }

                    const empty_arr = try self.allocator.alloc(Value, 0);
                    try self.push(.{ .array = empty_arr });
                },

                else => return RuntimeError.InvalidOpcode,
            }
        }
    }
};