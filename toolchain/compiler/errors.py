class CompilerError(Exception):
    def __init__(self, message: str, line: int = None, column: int = None):
        self.message = message
        self.line = line
        self.column = column
        super().__init__(self.format_message())

    def format_message(self) -> str:
        if self.line is not None and self.column is not None:
            return f"Error at line {self.line}, column {self.column}: {self.message}"
        elif self.line is not None:
            return f"Error at line {self.line}: {self.message}"
        else:
            return f"Compiler error: {self.message}"

class ParseError(CompilerError):
    pass

class CodeGenError(CompilerError):
    pass

class OptimizationError(CompilerError):
    pass
