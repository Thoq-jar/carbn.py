const std = @import("std");
const Value = @import("value.zig").Value;
const OpCode = @import("opcodes.zig").OpCode;
const io = @import("io.zig");

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const HashMap = std.HashMap;

pub const VMError = error{
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
};

pub const VM = struct {
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

        self.stack.deinit();
        self.call_stack.deinit();
        self.variables.deinit();
    }

    fn push(self: *Self, value: Value) !void {
        try self.stack.append(value);
    }

    fn pop(self: *Self) !Value {
        if (self.stack.items.len == 0) return VMError.StackUnderflow;
        return self.stack.pop().?;
    }

    fn peek(self: *Self) !Value {
        if (self.stack.items.len == 0) return VMError.StackUnderflow;
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

    fn readString(self: *Self, code: []const u8, ip: *usize) ![]const u8 {
        const len = readU8(code, ip);
        const str = code[ip.* .. ip.* + len];
        ip.* += len;
        return try self.allocator.dupe(u8, str);
    }

    pub fn execute(self: *Self, code: []const u8) !void {
        var ip: usize = 0;

        while (ip < code.len) {
            const op = @as(OpCode, @enumFromInt(code[ip]));
            ip += 1;

            switch (op) {
                .PRINT => {
                    const value = try self.pop();
                    defer value.deinit(self.allocator);

                    const str = try value.toString(self.allocator);
                    defer self.allocator.free(str);

                    io.printvm(str);
                    io.printvm("\n");
                },

                .LOAD_CONST => {
                    const str = try self.readString(code, &ip);
                    try self.push(.{ .string = str });
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
                    const name = try self.readString(code, &ip);
                    defer self.allocator.free(name);

                    if (self.variables.get(name)) |value| {
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
                                        .integer, .float, .boolean, .null_value => item,
                                    };
                                }
                                break :blk Value{ .array = new_arr };
                            },
                            else => value,
                        };
                        try self.push(copied);
                    } else {
                        try self.push(.{ .integer = 0 });
                    }
                },
                .STORE => {
                    const name = try self.readString(code, &ip);
                    const value = try self.pop();

                    const owned_name = try self.allocator.dupe(u8, name);

                    const result = try self.variables.getOrPut(owned_name);
                    if (result.found_existing) {
                        result.value_ptr.deinit(self.allocator);
                        self.allocator.free(owned_name);
                    }
                    result.value_ptr.* = value;

                    self.allocator.free(name);
                },

                .STDIN => {
                    var buf: [1024]u8 = undefined;
                    const input = try std.io.getStdIn().reader().readUntilDelimiter(&buf, '\n');
                    const str = try self.allocator.dupe(u8, input);
                    try self.push(.{ .string = str });
                },

                .ADD => {
                    const b = try self.pop();
                    const a = try self.pop();
                    defer a.deinit(self.allocator);
                    defer b.deinit(self.allocator);

                    const result = switch (a) {
                        .integer => |ai| switch (b) {
                            .integer => |bi| Value{ .integer = ai + bi },
                            .float => |bf| Value{ .float = @as(f64, @floatFromInt(ai)) + bf },
                            else => return VMError.InvalidCast,
                        },
                        .float => |af| switch (b) {
                            .integer => |bi| Value{ .float = af + @as(f64, @floatFromInt(bi)) },
                            .float => |bf| Value{ .float = af + bf },
                            else => return VMError.InvalidCast,
                        },
                        .string => |as| switch (b) {
                            .string => |bs| blk: {
                                const combined = try std.fmt.allocPrint(self.allocator, "{s}{s}", .{ as, bs });
                                break :blk Value{ .string = combined };
                            },
                            else => return VMError.InvalidCast,
                        },
                        else => return VMError.InvalidCast,
                    };
                    try self.push(result);
                },
                .SUB, .MUL, .DIV, .MOD => {
                    const b = try self.pop();
                    const a = try self.pop();
                    defer a.deinit(self.allocator);
                    defer b.deinit(self.allocator);

                    const result = switch (a) {
                        .integer => |ai| switch (b) {
                            .integer => |bi| blk: {
                                if (op == .DIV and bi == 0) return VMError.DivisionByZero;
                                break :blk switch (op) {
                                    .SUB => Value{ .integer = ai - bi },
                                    .MUL => Value{ .integer = ai * bi },
                                    .DIV => Value{ .integer = @divTrunc(ai, bi) },
                                    .MOD => Value{ .integer = @mod(ai, bi) },
                                    else => unreachable,
                                };
                            },
                            .float => |bf| blk: {
                                if (op == .DIV and bf == 0.0) return VMError.DivisionByZero;
                                const af = @as(f64, @floatFromInt(ai));
                                break :blk switch (op) {
                                    .SUB => Value{ .float = af - bf },
                                    .MUL => Value{ .float = af * bf },
                                    .DIV => Value{ .float = af / bf },
                                    .MOD => Value{ .float = @mod(af, bf) },
                                    else => unreachable,
                                };
                            },
                            else => return VMError.InvalidCast,
                        },
                        .float => |af| switch (b) {
                            .integer => |bi| blk: {
                                const bf = @as(f64, @floatFromInt(bi));
                                if (op == .DIV and bf == 0.0) return VMError.DivisionByZero;
                                break :blk switch (op) {
                                    .SUB => Value{ .float = af - bf },
                                    .MUL => Value{ .float = af * bf },
                                    .DIV => Value{ .float = af / bf },
                                    .MOD => Value{ .float = @mod(af, bf) },
                                    else => unreachable,
                                };
                            },
                            .float => |bf| blk: {
                                if (op == .DIV and bf == 0.0) return VMError.DivisionByZero;
                                break :blk switch (op) {
                                    .SUB => Value{ .float = af - bf },
                                    .MUL => Value{ .float = af * bf },
                                    .DIV => Value{ .float = af / bf },
                                    .MOD => Value{ .float = @mod(af, bf) },
                                    else => unreachable,
                                };
                            },
                            else => return VMError.InvalidCast,
                        },
                        else => return VMError.InvalidCast,
                    };
                    try self.push(result);
                },

                .EQ, .NE, .LT, .LE, .GT, .GE => {
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
                                    .float => |bf| @as(f64, @floatFromInt(ai)) < bf,
                                    else => false,
                                },
                                .float => |af| switch (b) {
                                    .integer => |bi| af < @as(f64, @floatFromInt(bi)),
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
                                    .float => |bf| @as(f64, @floatFromInt(ai)) <= bf,
                                    else => false,
                                },
                                .float => |af| switch (b) {
                                    .integer => |bi| af <= @as(f64, @floatFromInt(bi)),
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
                                    .float => |bf| @as(f64, @floatFromInt(ai)) > bf,
                                    else => false,
                                },
                                .float => |af| switch (b) {
                                    .integer => |bi| af > @as(f64, @floatFromInt(bi)),
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
                                    .float => |bf| @as(f64, @floatFromInt(ai)) >= bf,
                                    else => false,
                                },
                                .float => |af| switch (b) {
                                    .integer => |bi| af >= @as(f64, @floatFromInt(bi)),
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
                        return VMError.InvalidJump;
                    }
                    ip = @intCast(target);
                },

                .JMP_IF_FALSE => {
                    const target = readU64(code, &ip);
                    const condition = try self.pop();
                    defer condition.deinit(self.allocator);

                    if (!condition.toBool()) {
                        if (target > code.len) {
                            return VMError.InvalidJump;
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
                            return VMError.InvalidJump;
                        }
                        ip = @intCast(target);
                    }
                },
                .DUP => {
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
                    if (self.stack.items.len < 2) return VMError.StackUnderflow;
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
                        else => return VMError.InvalidCast,
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

                    const int_val = try value.toInt();
                    try self.push(.{ .integer = int_val });
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

                else => return VMError.InvalidOpcode,
            }
        }
    }
};
