import os

file_path = r'e:\vc code\.vscode\trash tracker\AIQ_Fleet app\lib\ui\camera_screen.dart'
with open(file_path, 'r', encoding='utf-8') as f:
    lines = f.readlines()

out_lines = []
skip = False
for line in lines:
    if "const Text(\"???\", style: TextStyle(fontSize: 12))," in line:
        continue # Skip this line
    if "// Tunnel Indicator" in line:
        skip = True
    if skip and "Row(" in line:
        pass # Wait, if it inserted Row, it might be nested
    
    out_lines.append(line)

content = "".join(out_lines)

# Re-do it cleanly using string replace
with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

# Let's revert git for camera_screen.dart first just to be completely clean!
