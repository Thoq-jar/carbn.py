const std = @import("std");
const builtin = @import("builtin");

pub fn printvm(message: []const u8) void {
    switch (comptime builtin.os.tag) {
        .linux => switch (comptime builtin.cpu.arch) {
            .x86_64 => {
                asm volatile ("syscall"
                    :
                    : [number] "{rax}" (1),
                      [arg1] "{rdi}" (1),
                      [arg2] "{rsi}" (message.ptr),
                      [arg3] "{rdx}" (message.len),
                    : "rcx", "r11", "memory"
                );
            },
            .aarch64 => {
                asm volatile ("svc #0"
                    :
                    : [number] "{x8}" (1),
                      [arg1] "{x0}" (1),
                      [arg2] "{x1}" (message.ptr),
                      [arg3] "{x2}" (message.len),
                    : "memory"
                );
            },
            else => {
                const stdout = std.io.getStdOut().writer();
                stdout.writeAll(message) catch {};
            },
        },
        .macos => switch (comptime builtin.cpu.arch) {
            .x86_64 => {
                asm volatile ("syscall"
                    :
                    : [number] "{rax}" (0x2000004),
                      [arg1] "{rdi}" (1),
                      [arg2] "{rsi}" (message.ptr),
                      [arg3] "{rdx}" (message.len),
                    : "rcx", "r11", "memory"
                );
            },
            .aarch64 => {
                asm volatile ("svc #0x80"
                    :
                    : [number] "{x16}" (0x2000004),
                      [arg1] "{x0}" (1),
                      [arg2] "{x1}" (message.ptr),
                      [arg3] "{x2}" (message.len),
                    : "memory"
                );
            },
            else => {
                const stdout = std.io.getStdOut().writer();
                stdout.writeAll(message) catch {};
            },
        },
        else => {
            const stdout = std.io.getStdOut().writer();
            stdout.writeAll(message) catch {};
        },
    }
}

pub inline fn print(comptime fmt: []const u8, args: anytype) !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print(fmt, args);
}