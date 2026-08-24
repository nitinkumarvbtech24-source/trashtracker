import os
import re

file_path = r'e:\vc code\.vscode\trash tracker\AIQ_Fleet app\lib\services\camera_service.dart'
with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

content = content.replace('_isBackendConnected', '_isGarbageConnected')
content = content.replace('isBackendConnected', 'isGarbageConnected')

with open(file_path, 'w', encoding='utf-8') as f:
    f.write(content)
