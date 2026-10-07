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
            
            # replace 'com.example.street_aiq' and 'com.example.app' with 'com.nitin.trashtracker'
            new_content = re.sub(r"'com\.example\.[^']+'", "'com.nitin.trashtracker'", content)
            
            if new_content != content:
                with open(path, 'w', encoding='utf-8') as f:
                    f.write(new_content)
                print(f'Patched userAgent in {path}')
