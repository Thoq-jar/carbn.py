pub const OpCode = enum(u8) {
    PRINT = 1,
    LOAD_CONST = 2,
    LOAD_INT = 3,
    LOOP_START = 4,
    LOOP_END = 5,
    LOAD_VAR = 6,
    STDIN = 7,
    STORE = 8,

    ADD = 9,
    SUB = 10,
    MUL = 11,
    DIV = 12,
    MOD = 13,

    EQ = 14,
    NE = 15,
    LT = 16,
    LE = 17,
    GT = 18,
    GE = 19,

    AND = 20,
    OR = 21,
    NOT = 22,

    JMP = 23,
    JMP_IF_FALSE = 24,
    JMP_IF_TRUE = 25,
    CALL = 26,
    RET = 27,

    LOAD_FLOAT = 28,
    CAST_INT = 29,
    CAST_FLOAT = 30,
    ARRAY_NEW = 31,
    ARRAY_GET = 32,
    ARRAY_SET = 33,
    ARRAY_LEN = 34,

    DUP = 35,
    SWAP = 36,
    POP = 37,

    LOAD_NULL = 38,
    IS_NULL = 39,

    LOAD_BOOL = 40,
    BUILD_LIST = 41,
    BUILD_TUPLE = 42,
    BUILD_DICT = 43,
};
