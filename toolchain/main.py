import argparse
import os
import sys
import time
from compiler import Logger, PythonParser, CodeGenerator, Optimizer, CompilerError

def main():
    parser = argparse.ArgumentParser(description='Python to Carbon bytecode compiler')
    parser.add_argument('input', help='Input Python source file')
    parser.add_argument('-o', '--output', help='Output file')
    parser.add_argument('--debug', action='store_true', help='Enable debug output')
    parser.add_argument('--optimize', action='store_true', help='Enable optimizations')

    args = parser.parse_args()

    if args.output:
        output_file = args.output
    else:
        base = os.path.splitext(args.input)[0]
        output_file = f"{base}.crbn"

    logger = Logger()

    try:
        logger.print_progress("Carbon Compiler v1.0.0")
        time.sleep(0.5)

        logger.print_progress("Reading Python source file")
        with open(args.input, 'r') as f:
            source = f.read()

        source_lines = source.splitlines()
        logger.print_result(True, f"Source file loaded ({len(source_lines)} lines)")
        parser_instance = PythonParser(logger)
        ast_tree = parser_instance.parse_file(source)

        if args.optimize:
            optimizer = Optimizer(logger)
            ast_tree = optimizer.optimize(ast_tree)

        codegen = CodeGenerator(logger)
        bytecode = codegen.generate(ast_tree)

        with open(output_file, 'wb') as f:
            f.write(bytecode)

        if logger.error_count == 0:
            logger.print_result(True, "Compilation pipeline completed successfully")
        else:
            logger.print_result(False, f"Compilation pipeline failed with {logger.error_count} errors")

    except FileNotFoundError:
        logger.print_result(False, f"Input file not found: {args.input}")
        sys.exit(1)
    except CompilerError as e:
        logger.print_result(False, f"Compilation failed: {e}")
        sys.exit(1)
    except Exception as e:
        logger.print_result(False, f"Unexpected error: {e}")
        sys.exit(1)

if __name__ == '__main__':
    main()
