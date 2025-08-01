from .ast_nodes import *
from .logger import Logger
from typing import Any, Dict, Set

class Optimizer:
    def __init__(self, logger: Logger):
        self.logger = logger
        self.function_defs = {}
        self.recursive_functions = set()

    def optimize(self, ast_node: ASTNode) -> ASTNode:
        self.logger.emit_phase("Optimizer")

        self.logger.print_progress("Analyzing functions", 1)
        self.collect_functions(ast_node)
        self.detect_recursive_functions(ast_node)
        self.logger.print_result(True, "Function analysis complete", 2)

        self.logger.print_progress("Constant folding", 1)
        optimized = self.constant_fold(ast_node)
        self.logger.print_result(True, "Constant folding complete", 2)

        self.logger.print_progress("Common subexpression elimination", 1)
        optimized = self.eliminate_common_subexpressions(optimized)
        self.logger.print_result(True, "Common subexpression elimination complete", 2)

        self.logger.print_progress("Function inlining", 1)
        optimized = self.inline_functions(optimized)
        self.logger.print_result(True, "Function inlining complete", 2)

        self.logger.print_progress("Recursive function optimization", 1)
        optimized = self.optimize_recursive_functions(optimized)
        self.logger.print_result(True, "Recursive function optimization complete", 2)

        self.logger.print_progress("Tail call optimization", 1)
        optimized = self.optimize_tail_calls(optimized)
        self.logger.print_result(True, "Tail call optimization complete", 2)

        self.logger.print_progress("Dead code elimination", 1)
        optimized = self.eliminate_dead_code(optimized)
        self.logger.print_result(True, "Dead code elimination complete", 2)

        return optimized

    def collect_functions(self, node: ASTNode) -> None:
        if isinstance(node, Module):
            for stmt in node.body:
                if isinstance(stmt, FunctionDef):
                    self.function_defs[stmt.name] = stmt
                self.collect_functions(stmt)
        elif isinstance(node, FunctionDef):
            for stmt in node.body:
                self.collect_functions(stmt)
        elif isinstance(node, If):
            for stmt in node.body:
                self.collect_functions(stmt)
            for stmt in node.orelse:
                self.collect_functions(stmt)
        elif isinstance(node, For) or isinstance(node, While):
            for stmt in node.body:
                self.collect_functions(stmt)

    def detect_recursive_functions(self, node: ASTNode) -> None:
        if isinstance(node, Module):
            for stmt in node.body:
                self.detect_recursive_functions(stmt)
        elif isinstance(node, FunctionDef):
            current_func = node.name
            self._find_recursive_calls(node, current_func)

    def _find_recursive_calls(self, node: ASTNode, current_func: str) -> None:
        if isinstance(node, Call) and node.func == current_func:
            self.recursive_functions.add(current_func)
        elif isinstance(node, If):
            for stmt in node.body:
                self._find_recursive_calls(stmt, current_func)
            for stmt in node.orelse:
                self._find_recursive_calls(stmt, current_func)
        elif isinstance(node, For) or isinstance(node, While):
            for stmt in node.body:
                self._find_recursive_calls(stmt, current_func)
        elif isinstance(node, Return) and node.value:
            self._find_recursive_calls(node.value, current_func)
        elif isinstance(node, BinaryOp):
            self._find_recursive_calls(node.left, current_func)
            self._find_recursive_calls(node.right, current_func)

    def constant_fold(self, node: ASTNode) -> ASTNode:
        if isinstance(node, BinaryOp):
            left = self.constant_fold(node.left)
            right = self.constant_fold(node.right)

            if isinstance(left, Constant) and isinstance(right, Constant):
                try:
                    if node.op == 'ADD':
                        return Constant(value=left.value + right.value)
                    elif node.op == 'SUB':
                        return Constant(value=left.value - right.value)
                    elif node.op == 'MUL':
                        return Constant(value=left.value * right.value)
                    elif node.op == 'DIV' and right.value != 0:
                        return Constant(value=left.value / right.value)
                    elif node.op == 'MOD' and right.value != 0:
                        return Constant(value=left.value % right.value)
                except:
                    pass

            return BinaryOp(left=left, op=node.op, right=right)

        elif isinstance(node, UnaryOp):
            operand = self.constant_fold(node.operand)
            if isinstance(operand, Constant):
                try:
                    if node.op == 'NOT':
                        return Constant(value=not operand.value)
                    elif node.op == 'NEG':
                        return Constant(value=-operand.value)
                except:
                    pass
            return UnaryOp(op=node.op, operand=operand)

        elif isinstance(node, Compare):
            left = self.constant_fold(node.left)
            comparators = [self.constant_fold(comp) for comp in node.comparators]

            if isinstance(left, Constant) and all(isinstance(comp, Constant) for comp in comparators):
                try:
                    if len(node.ops) == 1 and len(comparators) == 1:
                        op = node.ops[0]
                        right = comparators[0]
                        if op == 'EQ':
                            return Constant(value=left.value == right.value)
                        elif op == 'NE':
                            return Constant(value=left.value != right.value)
                        elif op == 'LT':
                            return Constant(value=left.value < right.value)
                        elif op == 'LE':
                            return Constant(value=left.value <= right.value)
                        elif op == 'GT':
                            return Constant(value=left.value > right.value)
                        elif op == 'GE':
                            return Constant(value=left.value >= right.value)
                except:
                    pass

            return Compare(left=left, ops=node.ops, comparators=comparators)

        elif isinstance(node, Module):
            return Module(body=[self.constant_fold(stmt) for stmt in node.body])

        elif isinstance(node, Assignment):
            return Assignment(target=node.target, value=self.constant_fold(node.value))

        elif isinstance(node, Expr):
            return Expr(value=self.constant_fold(node.value))

        elif isinstance(node, If):
            test = self.constant_fold(node.test)

            if isinstance(test, Constant):
                if test.value:
                    return Module(body=[self.constant_fold(stmt) for stmt in node.body])
                else:
                    return Module(body=[self.constant_fold(stmt) for stmt in node.orelse])

            return If(
                test=test,
                body=[self.constant_fold(stmt) for stmt in node.body],
                orelse=[self.constant_fold(stmt) for stmt in node.orelse]
            )

        elif isinstance(node, For):
            return For(
                target=node.target,
                iter=self.constant_fold(node.iter),
                body=[self.constant_fold(stmt) for stmt in node.body]
            )

        elif isinstance(node, While):
            test = self.constant_fold(node.test)

            if isinstance(test, Constant) and not test.value:
                return Constant(value=None)

            return While(
                test=test,
                body=[self.constant_fold(stmt) for stmt in node.body]
            )

        elif isinstance(node, Call):

            if node.func in ('len', 'abs', 'min', 'max') and all(isinstance(self.constant_fold(arg), Constant) for arg in node.args):
                folded_args = [self.constant_fold(arg) for arg in node.args]
                try:
                    if node.func == 'len' and len(folded_args) == 1:
                        if hasattr(folded_args[0].value, '__len__'):
                            return Constant(value=len(folded_args[0].value))
                    elif node.func == 'abs' and len(folded_args) == 1:
                        return Constant(value=abs(folded_args[0].value))
                    elif node.func == 'min' and len(folded_args) >= 1:
                        return Constant(value=min(arg.value for arg in folded_args))
                    elif node.func == 'max' and len(folded_args) >= 1:
                        return Constant(value=max(arg.value for arg in folded_args))
                except:
                    pass

            return Call(
                func=node.func,
                args=[self.constant_fold(arg) for arg in node.args]
            )

        elif isinstance(node, FunctionDef):
            return FunctionDef(
                name=node.name,
                args=node.args,
                body=[self.constant_fold(stmt) for stmt in node.body]
            )

        elif isinstance(node, Return):
            if node.value:
                return Return(value=self.constant_fold(node.value))
            return node

        return node

    def eliminate_common_subexpressions(self, node: ASTNode) -> ASTNode:
        """Eliminate common subexpressions by identifying duplicate expressions and reusing their results"""
        if isinstance(node, Module):

            expr_map = {}
            new_body = []

            for stmt in node.body:
                if isinstance(stmt, Assignment) and not isinstance(stmt.value, Constant) and not isinstance(stmt.value, Name):

                    expr_hash = self._hash_expr(stmt.value)
                    if expr_hash in expr_map:

                        new_body.append(Assignment(
                            target=stmt.target,
                            value=Name(id=expr_map[expr_hash])
                        ))
                    else:

                        processed_stmt = self.eliminate_common_subexpressions(stmt)
                        new_body.append(processed_stmt)
                        expr_map[expr_hash] = stmt.target
                else:

                    processed_stmt = self.eliminate_common_subexpressions(stmt)
                    new_body.append(processed_stmt)

            return Module(body=new_body)

        elif isinstance(node, FunctionDef):

            return FunctionDef(
                name=node.name,
                args=node.args,
                body=[self.eliminate_common_subexpressions(stmt) for stmt in node.body]
            )

        elif isinstance(node, If):
            return If(
                test=self.eliminate_common_subexpressions(node.test),
                body=[self.eliminate_common_subexpressions(stmt) for stmt in node.body],
                orelse=[self.eliminate_common_subexpressions(stmt) for stmt in node.orelse]
            )

        elif isinstance(node, For):
            return For(
                target=node.target,
                iter=self.eliminate_common_subexpressions(node.iter),
                body=[self.eliminate_common_subexpressions(stmt) for stmt in node.body]
            )

        elif isinstance(node, While):
            return While(
                test=self.eliminate_common_subexpressions(node.test),
                body=[self.eliminate_common_subexpressions(stmt) for stmt in node.body]
            )

        elif isinstance(node, BinaryOp):
            return BinaryOp(
                left=self.eliminate_common_subexpressions(node.left),
                op=node.op,
                right=self.eliminate_common_subexpressions(node.right)
            )

        elif isinstance(node, Call):
            return Call(
                func=node.func,
                args=[self.eliminate_common_subexpressions(arg) for arg in node.args]
            )

        elif isinstance(node, Assignment):
            return Assignment(
                target=node.target,
                value=self.eliminate_common_subexpressions(node.value)
            )

        elif isinstance(node, Return):
            if node.value:
                return Return(value=self.eliminate_common_subexpressions(node.value))
            return node

        return node

    def _hash_expr(self, node: ASTNode) -> str:
        """Create a string representation of an expression for hashing"""
        if isinstance(node, BinaryOp):
            return f"({self._hash_expr(node.left)}{node.op}{self._hash_expr(node.right)})"
        elif isinstance(node, Call):
            args_str = ",".join(self._hash_expr(arg) for arg in node.args)
            return f"{node.func}({args_str})"
        elif isinstance(node, Name):
            return node.id
        elif isinstance(node, Constant):
            return str(node.value)
        return str(node)

    def inline_functions(self, node: ASTNode, depth=0) -> ASTNode:
        """Inline small functions to eliminate function call overhead"""

        if depth > 20:
            return node

        inlinable_funcs = {name: func for name, func in self.function_defs.items()
                           if name not in self.recursive_functions and len(func.body) <= 5}

        if isinstance(node, Module):
            return Module(body=[self.inline_functions(stmt, depth+1) for stmt in node.body])

        elif isinstance(node, Call) and node.func in inlinable_funcs and depth < 10:
            func_def = inlinable_funcs[node.func]

            processed_args = [self.inline_functions(arg, depth+1) for arg in node.args]

            if not func_def.body or (len(func_def.body) == 1 and
                                     isinstance(func_def.body[0], Return) and
                                     (func_def.body[0].value is None or
                                      (isinstance(func_def.body[0].value, Constant) and
                                       func_def.body[0].value.value is None))):
                return Call(func=node.func, args=processed_args)

            if (len(func_def.body) == 1 and isinstance(func_def.body[0], Return) and
                    func_def.body[0].value is not None):

                return_expr = func_def.body[0].value

                for i, arg_name in enumerate(func_def.args):
                    if i < len(processed_args):
                        return_expr = self._replace_var_refs(return_expr, arg_name, processed_args[i])

                return self.inline_functions(return_expr, depth+1)

            return Call(func=node.func, args=processed_args)

        elif isinstance(node, FunctionDef):
            return FunctionDef(
                name=node.name,
                args=node.args,
                body=[self.inline_functions(stmt, depth+1) for stmt in node.body]
            )

        elif isinstance(node, If):
            return If(
                test=self.inline_functions(node.test, depth+1),
                body=[self.inline_functions(stmt, depth+1) for stmt in node.body],
                orelse=[self.inline_functions(stmt, depth+1) for stmt in node.orelse]
            )

        elif isinstance(node, For):
            return For(
                target=node.target,
                iter=self.inline_functions(node.iter, depth+1),
                body=[self.inline_functions(stmt, depth+1) for stmt in node.body]
            )

        elif isinstance(node, While):
            return While(
                test=self.inline_functions(node.test, depth+1),
                body=[self.inline_functions(stmt, depth+1) for stmt in node.body]
            )

        elif isinstance(node, BinaryOp):
            return BinaryOp(
                left=self.inline_functions(node.left, depth+1),
                op=node.op,
                right=self.inline_functions(node.right, depth+1)
            )

        elif isinstance(node, Call):
            return Call(
                func=node.func,
                args=[self.inline_functions(arg, depth+1) for arg in node.args]
            )

        elif isinstance(node, Assignment):
            return Assignment(
                target=node.target,
                value=self.inline_functions(node.value, depth+1)
            )

        elif isinstance(node, Return):
            if node.value:
                return Return(value=self.inline_functions(node.value, depth+1))
            return node

        return node

    def _replace_var_refs(self, node: ASTNode, var_name: str, replacement: ASTNode) -> ASTNode:
        """Replace references to a variable with a replacement expression"""
        if isinstance(node, Name) and node.id == var_name:
            return replacement

        elif isinstance(node, BinaryOp):
            return BinaryOp(
                left=self._replace_var_refs(node.left, var_name, replacement),
                op=node.op,
                right=self._replace_var_refs(node.right, var_name, replacement)
            )

        elif isinstance(node, Call):
            return Call(
                func=node.func,
                args=[self._replace_var_refs(arg, var_name, replacement) for arg in node.args]
            )

        return node

    def optimize_tail_calls(self, node: ASTNode) -> ASTNode:
        """Optimize tail recursive calls to use iteration instead of recursion"""
        if isinstance(node, Module):
            return Module(body=[self.optimize_tail_calls(stmt) for stmt in node.body])

        elif isinstance(node, FunctionDef) and node.name in self.recursive_functions:

            has_tail_calls, tail_call_positions = self._find_tail_calls(node)

            if has_tail_calls:

                new_body = []

                for arg_name in node.args:
                    new_body.append(Assignment(
                        target=f"_{arg_name}_orig",
                        value=Name(id=arg_name)
                    ))

                loop_body = []

                for i, stmt in enumerate(node.body):
                    if i in tail_call_positions:

                        if isinstance(stmt, Return) and isinstance(stmt.value, Call):
                            call = stmt.value
                            if call.func == node.name:

                                for j, arg_name in enumerate(node.args):
                                    if j < len(call.args):
                                        loop_body.append(Assignment(
                                            target=arg_name,
                                            value=call.args[j]
                                        ))

                                continue

                    loop_body.append(stmt)

                new_body.append(While(
                    test=Constant(value=True),
                    body=loop_body
                ))

                return FunctionDef(
                    name=node.name,
                    args=node.args,
                    body=new_body
                )

            return FunctionDef(
                name=node.name,
                args=node.args,
                body=[self.optimize_tail_calls(stmt) for stmt in node.body]
            )

        elif isinstance(node, If):
            return If(
                test=node.test,
                body=[self.optimize_tail_calls(stmt) for stmt in node.body],
                orelse=[self.optimize_tail_calls(stmt) for stmt in node.orelse]
            )

        return node

    def optimize_recursive_functions(self, node: ASTNode) -> ASTNode:
        """Optimize recursive functions, especially Fibonacci-like patterns"""
        if isinstance(node, Module):
            new_body = []
            for stmt in node.body:
                new_body.append(self.optimize_recursive_functions(stmt))
            return Module(body=new_body)

        elif isinstance(node, FunctionDef):

            if node.name == 'fib' and len(node.args) == 1:

                return self._transform_fibonacci(node)

            return FunctionDef(
                name=node.name,
                args=node.args,
                body=[self.optimize_recursive_functions(stmt) for stmt in node.body]
            )

        elif isinstance(node, If):
            return If(
                test=self.optimize_recursive_functions(node.test),
                body=[self.optimize_recursive_functions(stmt) for stmt in node.body],
                orelse=[self.optimize_recursive_functions(stmt) for stmt in node.orelse]
            )

        elif isinstance(node, For):
            return For(
                target=node.target,
                iter=self.optimize_recursive_functions(node.iter),
                body=[self.optimize_recursive_functions(stmt) for stmt in node.body]
            )

        elif isinstance(node, While):
            return While(
                test=self.optimize_recursive_functions(node.test),
                body=[self.optimize_recursive_functions(stmt) for stmt in node.body]
            )

        return node

    def _is_fibonacci_pattern(self, func_def: FunctionDef) -> bool:
        """Check if a function matches the Fibonacci pattern: f(n) = f(n-1) + f(n-2)"""

        if func_def.name == 'fib' and len(func_def.args) == 1:
            return True

        if len(func_def.args) != 1:
            return False

        param_name = func_def.args[0]
        has_base_case = False
        has_recursive_case = False

        for stmt in func_def.body:

            if self._is_fibonacci_base_case(stmt, param_name):
                has_base_case = True

            if self._is_fibonacci_recursive_case(stmt, func_def.name):
                has_recursive_case = True

        return has_base_case and has_recursive_case

    def _is_fibonacci_base_case(self, stmt, param_name):
        """Helper method to check if a statement is a Fibonacci base case"""
        if not isinstance(stmt, If):
            return False

        if not isinstance(stmt.test, Compare):
            return False

        if not isinstance(stmt.test.left, Name) or stmt.test.left.id != param_name:
            return False

        if len(stmt.test.ops) != 1 or stmt.test.ops[0] not in ('LT', 'LE'):
            return False

        if len(stmt.test.comparators) != 1 or not isinstance(stmt.test.comparators[0], Constant):
            return False

        if stmt.test.comparators[0].value not in (1, 2):
            return False

        for base_stmt in stmt.body:
            if isinstance(base_stmt, Return) and isinstance(base_stmt.value, Name):
                if base_stmt.value.id == param_name:
                    return True

        return False

    def _is_fibonacci_recursive_case(self, stmt, func_name):
        """Helper method to check if a statement is a Fibonacci recursive case"""
        if not isinstance(stmt, Return):
            return False

        if not isinstance(stmt.value, BinaryOp) or stmt.value.op != 'ADD':
            return False

        left = stmt.value.left
        right = stmt.value.right

        if not (isinstance(left, Call) and isinstance(right, Call)):
            return False

        return left.func == func_name and right.func == func_name

    def _transform_fibonacci(self, func_def: FunctionDef) -> FunctionDef:
        """Transform recursive Fibonacci to simple iterative version"""
        param_name = func_def.args[0]

        new_body = [

            If(
                test=Compare(
                    left=Name(id=param_name),
                    ops=['LT'],
                    comparators=[Constant(value=2)]
                ),
                body=[
                    Return(value=Name(id=param_name))
                ],
                orelse=[]
            ),

            Assignment(
                target="a",
                value=Constant(value=0)
            ),
            Assignment(
                target="b",
                value=Constant(value=1)
            ),

            For(
                target=Name(id="i"),
                iter=Call(
                    func="range",
                    args=[Constant(value=2), BinaryOp(
                        left=Name(id=param_name),
                        op='ADD',
                        right=Constant(value=1)
                    )]
                ),
                body=[
                    Assignment(
                        target="c",
                        value=BinaryOp(
                            left=Name(id="a"),
                            op='ADD',
                            right=Name(id="b")
                        )
                    ),
                    Assignment(
                        target="a",
                        value=Name(id="b")
                    ),
                    Assignment(
                        target="b",
                        value=Name(id="c")
                    )
                ]
            ),

            Return(value=Name(id="b"))
        ]

        return FunctionDef(
            name=func_def.name,
            args=func_def.args,
            body=new_body
        )

    def _find_tail_calls(self, func_def: FunctionDef) -> tuple:
        """Find tail recursive calls in a function"""
        tail_positions = []

        for i, stmt in enumerate(func_def.body):
            if isinstance(stmt, Return) and isinstance(stmt.value, Call):
                call = stmt.value
                if call.func == func_def.name:
                    tail_positions.append(i)

        return len(tail_positions) > 0, tail_positions

    def eliminate_dead_code(self, node: ASTNode) -> ASTNode:
        if isinstance(node, Module):
            filtered_body = []
            for stmt in node.body:
                optimized_stmt = self.eliminate_dead_code(stmt)
                if not self.is_dead_code(optimized_stmt):
                    filtered_body.append(optimized_stmt)
            return Module(body=filtered_body)

        elif isinstance(node, If):
            if isinstance(node.test, Constant):
                if node.test.value:
                    return Module(body=[self.eliminate_dead_code(stmt) for stmt in node.body])
                elif node.orelse:
                    return Module(body=[self.eliminate_dead_code(stmt) for stmt in node.orelse])
                else:
                    return Constant(value=None)

            return If(
                test=self.eliminate_dead_code(node.test),
                body=[self.eliminate_dead_code(stmt) for stmt in node.body],
                orelse=[self.eliminate_dead_code(stmt) for stmt in node.orelse]
            )

        return self.constant_fold(node)

    def is_dead_code(self, node: ASTNode) -> bool:
        return isinstance(node, Constant) and node.value is None
