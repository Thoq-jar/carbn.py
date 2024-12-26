pub const OpCode = enum(i8) {
    PRINT = 1,
    LOAD_CONST = 2,
    LOAD_INT = 3,
    LOOP_START = 4,
    LOOP_END = 5,
    LOAD_VAR = 6,
    STDIN = 7,
    STORE = 8,
};
