import time
import sys

class Logger:
    def __init__(self):
        self.error_count = 0
        self.error_log = {}

    def print_progress(self, message, depth=0):
        for i in range(depth - 1):
            print("    │", end="")

        if depth == 0:
            print("[/] ", end="")
        else:
            print("    ├── [*] ", end="")

        print(message)
        sys.stdout.flush()
        time.sleep(0.2)

    def print_result(self, success, message, depth=0, error_output=""):
        for i in range(depth - 1):
            print("    │", end="")

        if depth == 0:
            if success:
                print("[+] ", end="")
            else:
                print("[-] ", end="")
                self.error_count += 1
                self.error_log[message] = error_output
        else:
            if depth > 2:
                print("    └── ", end="")
            else:
                print("    ├── ", end="")

            if success:
                print("[+] ", end="")
            else:
                print("[-] ", end="")
                self.error_count += 1
                self.error_log[message] = error_output

        print(message)
        sys.stdout.flush()

    def emit_phase(self, phase_name):
        self.print_progress(f"Emit {phase_name}")
        time.sleep(0.5)

    def phase(self, phase_name):
        self.print_progress(phase_name)
        time.sleep(0.5)
