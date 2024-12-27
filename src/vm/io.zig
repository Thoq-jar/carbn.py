const std = @import("std");

pub fn printvm(message: []const u8) void {
    const STDOUT = 1;
    var written: usize = undefined;

    switch (@import("builtin").os.tag) {
        .linux => {
            const SYS_write = 1;
            asm volatile ("syscall"
                : [ret] "={rax}" (written),
                : [number] "{rax}" (SYS_write),
                  [arg1] "{rdi}" (STDOUT),
                  [arg2] "{rsi}" (message.ptr),
                  [arg3] "{rdx}" (message.len),
                : "rcx", "r11", "memory"
            );
        },
        .macos => {
            const SYS_write = 0x2000004;
            asm volatile ("syscall"
                : [ret] "={rax}" (written),
                : [number] "{rax}" (SYS_write),
                  [arg1] "{rdi}" (STDOUT),
                  [arg2] "{rsi}" (message.ptr),
                  [arg3] "{rdx}" (message.len),
                : "rcx", "r11", "memory"
            );
        },
        else => {
            const stdout = std.io.getStdOut().writer();
            stdout.writeAll(message) catch return;
        },
    }
}
