from dataclasses import dataclass
from typing import List, Any, Optional, Union

@dataclass
class ASTNode:
    pass

@dataclass
class Module(ASTNode):
    body: List['ASTNode']

@dataclass
class Assignment(ASTNode):
    target: str
    value: 'ASTNode'

@dataclass
class BinaryOp(ASTNode):
    left: 'ASTNode'
    op: str
    right: 'ASTNode'

@dataclass
class UnaryOp(ASTNode):
    op: str
    operand: 'ASTNode'

@dataclass
class Compare(ASTNode):
    left: 'ASTNode'
    ops: List[str]
    comparators: List['ASTNode']

@dataclass
class BoolOp(ASTNode):
    op: str
    values: List['ASTNode']

@dataclass
class Call(ASTNode):
    func: str
    args: List['ASTNode']

@dataclass
class Name(ASTNode):
    id: str

@dataclass
class Constant(ASTNode):
    value: Any

@dataclass
class If(ASTNode):
    test: 'ASTNode'
    body: List['ASTNode']
    orelse: List['ASTNode']

@dataclass
class For(ASTNode):
    target: 'ASTNode'
    iter: 'ASTNode'
    body: List['ASTNode']

@dataclass
class While(ASTNode):
    test: 'ASTNode'
    body: List['ASTNode']

@dataclass
class ListNode(ASTNode):
    elts: List['ASTNode']

@dataclass
class Expr(ASTNode):
    value: 'ASTNode'

@dataclass
class FunctionDef(ASTNode):
    name: str
    args: List[str]
    body: List['ASTNode']
