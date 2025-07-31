import ast
from .ast_nodes import *
from .errors import CompilerError
from .logger import Logger

class PythonParser:
    def __init__(self, logger: Logger):
        self.logger = logger

    def parse_file(self, source: str) -> Module:
        self.logger.phase("Parsing")
        self.logger.print_progress("Parsing Python source", 1)

        try:
            tree = ast.parse(source)
            self.logger.print_result(True, "AST generation complete", 2)

            self.logger.print_progress("Converting to internal AST", 1)
            internal_ast = self.convert_ast(tree)
            self.logger.print_result(True, "Internal AST conversion complete", 2)

            return internal_ast

        except SyntaxError as e:
            self.logger.print_result(False, f"Syntax error: {e}", 1, str(e))
            raise CompilerError(f"Python syntax error: {e}")
        except Exception as e:
            self.logger.print_result(False, f"Parse error: {e}", 1, str(e))
            raise CompilerError(f"Parse error: {e}")

    def convert_ast(self, node: ast.AST) -> ASTNode:
        if isinstance(node, ast.Module):
            body = [self.convert_ast(stmt) for stmt in node.body]
            return Module(body=body)

        elif isinstance(node, ast.Assign):
            if len(node.targets) == 1 and isinstance(node.targets[0], ast.Name):
                return Assignment(
                    target=node.targets[0].id,
                    value=self.convert_ast(node.value)
                )

        elif isinstance(node, ast.Expr):
            return Expr(value=self.convert_ast(node.value))

        elif isinstance(node, ast.Call):
            if isinstance(node.func, ast.Name):
                args = [self.convert_ast(arg) for arg in node.args]
                return Call(func=node.func.id, args=args)

        elif isinstance(node, ast.Name):
            return Name(id=node.id)

        elif isinstance(node, ast.Constant):
            return Constant(value=node.value)

        elif isinstance(node, ast.BinOp):
            op_map = {
                ast.Add: 'ADD',
                ast.Sub: 'SUB',
                ast.Mult: 'MUL',
                ast.Div: 'DIV',
                ast.Mod: 'MOD'
            }
            return BinaryOp(
                left=self.convert_ast(node.left),
                op=op_map.get(type(node.op), 'UNKNOWN'),
                right=self.convert_ast(node.right)
            )

        elif isinstance(node, ast.Compare):
            op_map = {
                ast.Eq: 'EQ',
                ast.NotEq: 'NE',
                ast.Lt: 'LT',
                ast.LtE: 'LE',
                ast.Gt: 'GT',
                ast.GtE: 'GE'
            }
            ops = [op_map.get(type(op), 'UNKNOWN') for op in node.ops]
            comparators = [self.convert_ast(comp) for comp in node.comparators]
            return Compare(
                left=self.convert_ast(node.left),
                ops=ops,
                comparators=comparators
            )

        elif isinstance(node, ast.BoolOp):
            op_name = 'AND' if isinstance(node.op, ast.And) else 'OR'
            values = [self.convert_ast(val) for val in node.values]
            return BoolOp(op=op_name, values=values)

        elif isinstance(node, ast.UnaryOp):
            op_map = {
                ast.Not: 'NOT',
                ast.USub: 'NEG'
            }
            return UnaryOp(
                op=op_map.get(type(node.op), 'UNKNOWN'),
                operand=self.convert_ast(node.operand)
            )

        elif isinstance(node, ast.If):
            return If(
                test=self.convert_ast(node.test),
                body=[self.convert_ast(stmt) for stmt in node.body],
                orelse=[self.convert_ast(stmt) for stmt in node.orelse] if node.orelse else []
            )

        elif isinstance(node, ast.For):
            return For(
                target=self.convert_ast(node.target),
                iter=self.convert_ast(node.iter),
                body=[self.convert_ast(stmt) for stmt in node.body]
            )

        elif isinstance(node, ast.While):
            return While(
                test=self.convert_ast(node.test),
                body=[self.convert_ast(stmt) for stmt in node.body]
            )

        elif isinstance(node, ast.List):
            return ListNode(elts=[self.convert_ast(elt) for elt in node.elts])

        elif isinstance(node, ast.FunctionDef):
            args = [arg.arg for arg in node.args.args]
            return FunctionDef(
                name=node.name,
                args=args,
                body=[self.convert_ast(stmt) for stmt in node.body]
            )

        return Constant(value=None)
