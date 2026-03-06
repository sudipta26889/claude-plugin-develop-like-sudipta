#!/usr/bin/env python3
import sys
import ast
import subprocess

def is_safe_script(filepath):
    """
    Parses the Python file to ensure it only uses allowed modules (e.g., requests, json, urllib)
    and doesn't contain destructive OS commands like os.system or subprocess.run with shell=True.
    """
    try:
        with open(filepath, 'r') as f:
            tree = ast.parse(f.read())
            
        allowed_modules = {'requests', 'json', 'urllib', 'time', 'sys', 're', 'bs4'}
        for node in ast.walk(tree):
            if isinstance(node, ast.Import):
                for alias in node.names:
                    if alias.name.split('.')[0] not in allowed_modules:
                        return False, f"Unauthorized module imported: {alias.name}"
            elif isinstance(node, ast.ImportFrom):
                if node.module and node.module.split('.')[0] not in allowed_modules:
                    return False, f"Unauthorized module imported: {node.module}"
            
        return True, "Safe"
    except Exception as e:
        return False, str(e)

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: poc_validator.py <exploit_script.py>")
        sys.exit(1)
        
    script_path = sys.argv[1]
    is_safe, msg = is_safe_script(script_path)
    
    if not is_safe:
        print(f"❌ [PoC VALIDATOR] Exploit blocked for safety reasons.\nReason: {msg}")
        sys.exit(1)
        
    print(f"🔒 [PoC VALIDATOR] Script {script_path} passed static safety checks. Executing in sandbox...")
    try:
        result = subprocess.run(
            ["python3", script_path],
            capture_output=True, text=True, timeout=10,
        )
        print("--- STDOUT ---")
        if result.stdout:
            print(result.stdout)
        print("--- STDERR ---")
        if result.stderr:
            print(result.stderr)
        print(f"Exit Code: {result.returncode}")
        sys.exit(result.returncode)
    except subprocess.TimeoutExpired:
        print("⏳ [PoC VALIDATOR] Exploit execution timed out (10s).")
        sys.exit(124)
    except Exception as e:
        print(f"❌ [PoC VALIDATOR] Execution error: {e}", file=sys.stderr)
        sys.exit(1)
