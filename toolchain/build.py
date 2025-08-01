import subprocess
import sys
import os
from pathlib import Path

def build_executable():
    print("[/] Building Carbon Compiler executable...")

    try:
        print("    ├── [*] Installing dependencies...")
        subprocess.run(["uv", "pip", "install", "-r", "requirements.txt"],
                       check=True, capture_output=True)
        print("    ├── [+] Dependencies installed")

        print("    ├── [*] Running PyInstaller...")

        main_script = Path("main.py")
        if not main_script.exists():
            raise FileNotFoundError("main.py not found")

        pyinstaller_cmd = [
            "pyinstaller",
            "--onefile",
            "--name=carbn",
            "--clean",
            "--distpath=../dist",
            "--workpath=../build",
            "--specpath=../build",
            str(main_script)
        ]

        result = subprocess.run(pyinstaller_cmd, check=True, capture_output=True, text=True)
        print("    ├── [+] PyInstaller completed successfully")

        dist_path = Path("../dist")
        executable_name = "carbn.exe" if os.name == 'nt' else "carbn"
        executable_path = dist_path / executable_name

        if executable_path.exists():
            print(f"    ├── [+] Executable created: {executable_path}")
            print(f"    └── [+] Size: {executable_path.stat().st_size} bytes")
        else:
            print("    └── [-] Executable not found after build")
            return False

        return True

    except subprocess.CalledProcessError as e:
        print(f"    └── [-] Build failed: {e}")
        if e.stdout:
            print(f"STDOUT: {e.stdout}")
        if e.stderr:
            print(f"STDERR: {e.stderr}")
        return False
    except Exception as e:
        print(f"    └── [-] Unexpected error: {e}")
        return False

def main():
    print("[/] Carbon Compiler Build Script")

    if build_executable():
        print("[+] Build completed successfully!")
        print("[+] Run the compiler with: ./dist/carbn <input.py>")
    else:
        print("[-] Build failed!")
        sys.exit(1)

if __name__ == "__main__":
    main()
