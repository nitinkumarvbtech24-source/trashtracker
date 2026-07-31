import glob, re

pattern1 = 'e:/vc code/.vscode/trash tracker/AIQ_authority app/lib/**/*.dart'
pattern2 = 'e:/vc code/.vscode/trash tracker/AIQ_Fleet app/lib/**/*.dart'
files = glob.glob(pattern1, recursive=True) + glob.glob(pattern2, recursive=True)

for f in files:
    with open(f, 'r', encoding='utf-8') as file:
        content = file.read()
    
    # Replace duplicate headers
    new_content = re.sub(
        r'headers:\s*const\s*\{"ngrok-skip-browser-warning":\s*"true"\},\s*headers:\s*const\s*\{\'ngrok-skip-browser-warning\':\s*\'true\'\},',
        r"headers: const {'ngrok-skip-browser-warning': 'true'},", 
        content
    )
    
    if new_content != content:
        with open(f, 'w', encoding='utf-8') as file:
            file.write(new_content)
        print(f'Fixed duplicates in {f}')
