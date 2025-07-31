from .ast_nodes import *
from .logger import Logger
from typing import Any

class Optimizer:
    def __init__(self, logger: Logger):
        self.logger = logger

    def optimize(self, ast_node: ASTNode) -> ASTNode:
        self.logger.emit_phase("Optimizer")
        self.logger.print_progress("Constant folding", 1)

        optimized = self.constant_fold(ast_node)
        self.logger.print_result(True, "Constant folding complete", 2)

        self.logger.print_progress("Dead code elimination", 1)
        optimized = self.eliminate_dead_code(optimized)
        self.logger.print_result(True, "Dead code elimination complete", 2)

        return optimized

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
                except:
                    pass

            return BinaryOp(left=left, op=node.op, right=right)

        elif isinstance(node, Module):
            return Module(body=[self.constant_fold(stmt) for stmt in node.body])

        elif isinstance(node, Assignment):
            return Assignment(target=node.target, value=self.constant_fold(node.value))

        elif isinstance(node, Expr):
            return Expr(value=self.constant_fold(node.value))

        elif isinstance(node, If):
            return If(
                test=self.constant_fold(node.test),
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
            return While(
                test=self.constant_fold(node.test),
                body=[self.constant_fold(stmt) for stmt in node.body]
            )

        elif isinstance(node, Call):
            return Call(
                func=node.func,
                args=[self.constant_fold(arg) for arg in node.args]
            )

        return node

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
