import os
import re

directories = [
    r'e:\vc code\.vscode\trash tracker\AIQ_Fleet app\lib',
    r'e:\vc code\.vscode\trash tracker\AIQ_authority app\lib'
]

for d in directories:
    for root, _, files in os.walk(d):
        for file in files:
            if not file.endswith('.dart'):
                continue
            path = os.path.join(root, file)
            with open(path, 'r', encoding='utf-8') as f:
                content = f.read()
            
            # Find TileLayer(..., urlTemplate: 'https://tile.openstreetmap.org...')
            # We will insert userAgentPackageName: 'com.example.app', inside TileLayer if not present
            
            def add_user_agent(match):
                inner = match.group(0)
                if 'userAgentPackageName' not in inner:
                    return inner.replace("urlTemplate:", "userAgentPackageName: 'com.nitin.trashtracker',\n                urlTemplate:")
                return inner
            
            new_content = re.sub(r'TileLayer\([^)]*urlTemplate:[^)]*\)', add_user_agent, content, flags=re.DOTALL)
            
            if new_content != content:
                with open(path, 'w', encoding='utf-8') as f:
                    f.write(new_content)
                print(f'Patched map tiles in {path}')
