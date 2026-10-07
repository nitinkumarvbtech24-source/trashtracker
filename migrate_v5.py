import os
import re

directories = [
    r'e:\vc code\.vscode\trash tracker\AIQ_Fleet app\lib',
    r'e:\vc code\.vscode\trash tracker\AIQ_authority app\lib'
]

replacements = [
    (r'garbage_ai_v4_url', r'garbage_ai_v5_url'),
    (r'saved_tunnels_v4', r'saved_tunnels_v5'),
    (r'MODEL_VERSION == 4', r'MODEL_VERSION == 5'),
    (r'MODEL_VERSION = 4', r'MODEL_VERSION = 5'),
    (r'v4LinksJson', r'v5LinksJson'),
    (r'GARBAGE_AI_V4_URL', r'GARBAGE_AI_V5_URL'),
    (r'RoadScan AI v4\.0', r'RoadScan AI v5.0'),
    (r'pointer-staff-prodigy-v4', r'pointer-staff-prodigy-v5'),
    (r'Forced to V4', r'Forced to V5')
]

for d in directories:
    for root, _, files in os.walk(d):
        for file in files:
            if not file.endswith('.dart'):
                continue
            path = os.path.join(root, file)
            with open(path, 'r', encoding='utf-8') as f:
                content = f.read()
            
            new_content = content
            for old, new in replacements:
                new_content = re.sub(old, new, new_content)
            
            if new_content != content:
                with open(path, 'w', encoding='utf-8') as f:
                    f.write(new_content)
                print(f'Updated {path}')
