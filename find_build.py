import os

file_path = r'e:\vc code\.vscode\trash tracker\AIQ_authority app\lib\screens\fleet_screen.dart'
with open(file_path, 'r', encoding='utf-8') as f:
    lines = f.readlines()

build_idx = -1
for i, line in enumerate(lines):
    if 'Widget build(BuildContext context) {' in line:
        build_idx = i
        break

if build_idx != -1:
    print(f"build() starts at line {build_idx + 1}")
    methods = []
    for i in range(build_idx, len(lines)):
        line = lines[i].strip()
        if line.startswith('Widget _build') or line.startswith('void _show') or line.startswith('Widget _get'):
            methods.append((i+1, line.split('(')[0]))
    for m in methods:
        print(f"Line {m[0]}: {m[1]}")
