import struct
from enum import IntEnum
from typing import List, Dict, Any
from .ast_nodes import *
from .logger import Logger
from .errors import CompilerError

class OpCode(IntEnum):
    PRINT = 1
    LOAD_CONST = 2
    LOAD_INT = 3
    LOOP_START = 4
    LOOP_END = 5
    LOAD_VAR = 6
    STDIN = 7
    STORE = 8
    ADD = 9
    SUB = 10
    MUL = 11
    DIV = 12
    MOD = 13
    EQ = 14
    NE = 15
    LT = 16
    LE = 17
    GT = 18
    GE = 19
    AND = 20
    OR = 21
    NOT = 22
    JMP = 23
    JMP_IF_FALSE = 24
    JMP_IF_TRUE = 25
    CALL = 26
    RET = 27
    LOAD_FLOAT = 28
    CAST_INT = 29
    CAST_FLOAT = 30
    ARRAY_NEW = 31
    ARRAY_GET = 32
    ARRAY_SET = 33
    ARRAY_LEN = 34
    DUP = 35
    SWAP = 36
    POP = 37
    LOAD_NULL = 38
    IS_NULL = 39
    LOAD_BOOL = 40
    BUILD_LIST = 41
    BUILD_TUPLE = 42
    BUILD_DICT = 43

class CodeGenerator:
    def __init__(self, logger: Logger):
        self.logger = logger
        self.bytecode = []
        self.variables = {}
        self.functions = {}
        self.function_addresses = {}

    def generate(self, ast_node: ASTNode) -> bytes:
        self.logger.phase("Carbn Codegen")
        self.logger.print_progress("Generating bytecode", 1)

        try:
            self.visit_node(ast_node)
            self.logger.print_result(True, "Bytecode generation complete", 2)

            self.logger.print_progress("Optimizing bytecode", 1)
            self.optimize_bytecode()
            self.logger.print_result(True, "Bytecode optimization complete", 2)

            self.logger.emit_phase("Carbn")
            return bytes(self.bytecode)

        except Exception as e:
            self.logger.print_result(False, f"Code generation failed: {e}", 1, str(e))
            raise CompilerError(f"Codegen error: {e}")

    def emit(self, opcode, *args):
        if isinstance(opcode, str):
            self.bytecode.append(getattr(OpCode, opcode))
        else:
            self.bytecode.append(opcode)

        for arg in args:
            if isinstance(arg, int):
                self.bytecode.extend(struct.pack(">Q", arg & ((1 << 64) - 1)))
            elif isinstance(arg, float):
                self.bytecode.extend(struct.pack(">d", arg))
            elif isinstance(arg, str):
                encoded = arg.encode('utf-8')
                self.bytecode.append(len(encoded))
                self.bytecode.extend(encoded)
            elif isinstance(arg, bytes):
                self.bytecode.extend(arg)

    def visit_node(self, node: ASTNode):
        if isinstance(node, Module):
            main_start_pos = len(self.bytecode)
            self.emit('JMP', 0)

            for stmt in node.body:
                if isinstance(stmt, FunctionDef):
                    self.generate_function(stmt)

            main_start = len(self.bytecode)
            self.bytecode[main_start_pos + 1:main_start_pos + 9] = struct.pack(">Q", main_start)

            for stmt in node.body:
                if not isinstance(stmt, FunctionDef):
                    self.visit_node(stmt)

        elif isinstance(node, Assignment):
            self.visit_node(node.value)
            self.emit('STORE', node.target)

        elif isinstance(node, Expr):
            self.visit_node(node.value)
            if not isinstance(node.value, Call):
                self.emit('POP')

        elif isinstance(node, Call):
            if node.func == 'print':
                if node.args:
                    for arg in node.args:
                        self.visit_node(arg)
                    self.emit('PRINT')
                else:
                    self.emit('LOAD_CONST', '')
                    self.emit('PRINT')
            elif node.func == 'input':
                self.emit('STDIN')
            elif node.func == 'len':
                if node.args:
                    self.visit_node(node.args[0])
                    self.emit('ARRAY_LEN')
            elif node.func == 'int':
                if node.args:
                    self.visit_node(node.args[0])
                    self.emit('CAST_INT')
            elif node.func == 'float':
                if node.args:
                    self.visit_node(node.args[0])
                    self.emit('CAST_FLOAT')
            elif node.func == 'range':
                if len(node.args) >= 2:
                    start_val = node.args[0]
                    end_val = node.args[1]
                    if isinstance(start_val, Constant) and isinstance(end_val, Constant):
                        values = list(range(start_val.value, end_val.value))
                        for val in values:
                            self.emit('LOAD_INT', val)
                        self.emit('BUILD_LIST', len(values))
            elif node.func in self.function_addresses:
                for arg in node.args:
                    self.visit_node(arg)
                self.emit('CALL', self.function_addresses[node.func])

        elif isinstance(node, Name):
            self.emit('LOAD_VAR', node.id)

        elif isinstance(node, Constant):
            if isinstance(node.value, str):
                self.emit('LOAD_CONST', node.value)
            elif isinstance(node.value, int):
                self.emit('LOAD_INT', node.value)
            elif isinstance(node.value, float):
                self.emit('LOAD_FLOAT', node.value)
            elif isinstance(node.value, bool):
                self.emit('LOAD_BOOL', 1 if node.value else 0)
            elif node.value is None:
                self.emit('LOAD_NULL')

        elif isinstance(node, FString):
            result_parts = []
            for part in node.parts:
                if isinstance(part, Constant):
                    result_parts.append(part.value)
                else:
                    self.visit_node(part)
                    result_parts.append(None)

            if len(result_parts) == 1 and result_parts[0] is not None:
                self.emit('LOAD_CONST', result_parts[0])
            else:
                for i, part in enumerate(node.parts):
                    if isinstance(part, Constant):
                        self.emit('LOAD_CONST', part.value)
                    else:
                        self.visit_node(part)

                    if i > 0:
                        self.emit('ADD')

        elif isinstance(node, BinaryOp):
            self.visit_node(node.left)
            self.visit_node(node.right)
            self.emit(node.op)

        elif isinstance(node, Compare):
            self.visit_node(node.left)
            for i, (op, comparator) in enumerate(zip(node.ops, node.comparators)):
                self.visit_node(comparator)
                self.emit(op)

        elif isinstance(node, BoolOp):
            if node.op == 'AND':
                self.visit_node(node.values[0])
                for i in range(1, len(node.values)):
                    self.visit_node(node.values[i])
                    self.emit('AND')
            elif node.op == 'OR':
                self.visit_node(node.values[0])
                for i in range(1, len(node.values)):
                    self.visit_node(node.values[i])
                    self.emit('OR')

        elif isinstance(node, UnaryOp):
            self.visit_node(node.operand)
            if node.op == 'NOT':
                self.emit('NOT')
            elif node.op == 'NEG':
                self.emit('LOAD_INT', -1)
                self.emit('MUL')

        elif isinstance(node, If):
            self.visit_node(node.test)
            jmp_pos = len(self.bytecode)
            self.emit('JMP_IF_FALSE', 0)

            for stmt in node.body:
                self.visit_node(stmt)

            if node.orelse:
                else_jmp_pos = len(self.bytecode)
                self.emit('JMP', 0)

                if_end = len(self.bytecode)
                self.bytecode[jmp_pos + 1:jmp_pos + 9] = struct.pack(">Q", if_end)

                for stmt in node.orelse:
                    self.visit_node(stmt)

                final_end = len(self.bytecode)
                self.bytecode[else_jmp_pos + 1:else_jmp_pos + 9] = struct.pack(">Q", final_end)
            else:
                if_end = len(self.bytecode)
                self.bytecode[jmp_pos + 1:jmp_pos + 9] = struct.pack(">Q", if_end)

        elif isinstance(node, For):
            if (isinstance(node.iter, Call) and node.iter.func == 'range'):
                target_var = node.target.id if isinstance(node.target, Name) else None

                if target_var and len(node.iter.args) >= 2:
                    start_node = node.iter.args[0]
                    end_node = node.iter.args[1]

                    internal_counter = f"__{target_var}_counter"

                    self.visit_node(start_node)
                    self.emit('STORE', internal_counter)

                    loop_start = len(self.bytecode)

                    self.emit('LOAD_VAR', internal_counter)
                    self.visit_node(end_node)
                    self.emit('GE')

                    jmp_pos = len(self.bytecode)
                    self.emit('JMP_IF_TRUE', 0)

                    self.emit('LOAD_VAR', internal_counter)
                    self.emit('STORE', target_var)

                    for stmt in node.body:
                        self.visit_node(stmt)

                    self.emit('LOAD_VAR', internal_counter)
                    self.emit('LOAD_INT', 1)
                    self.emit('ADD')
                    self.emit('STORE', internal_counter)
                    self.emit('JMP', loop_start)

                    loop_end = len(self.bytecode)
                    self.bytecode[jmp_pos + 1:jmp_pos + 9] = struct.pack(">Q", loop_end)

        elif isinstance(node, While):
            loop_start = len(self.bytecode)
            self.visit_node(node.test)

            jmp_pos = len(self.bytecode)
            self.emit('JMP_IF_FALSE', 0)

            for stmt in node.body:
                self.visit_node(stmt)

            self.emit('JMP', loop_start)

            loop_end = len(self.bytecode)
            self.bytecode[jmp_pos + 1:jmp_pos + 9] = struct.pack(">Q", loop_end)

        elif isinstance(node, ListNode):
            for item in node.elts:
                self.visit_node(item)
            self.emit('BUILD_LIST', len(node.elts))

        elif isinstance(node, Return):
            if node.value:
                self.visit_node(node.value)
            else:
                self.emit('LOAD_NULL')
            self.emit('RET')

    def generate_function(self, func_def: FunctionDef):
        func_start = len(self.bytecode)
        self.function_addresses[func_def.name] = func_start

        for param in reversed(func_def.args):
            self.emit('STORE', param)

        for stmt in func_def.body:
            self.visit_node(stmt)

        self.emit('LOAD_NULL')
        self.emit('RET')

    def optimize_bytecode(self):
        pass
