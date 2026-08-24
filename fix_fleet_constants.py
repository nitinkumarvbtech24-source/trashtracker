import os

file_path = r'e:\vc code\.vscode\trash tracker\AIQ_Fleet app\lib\constants.dart'
with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

content = content.replace('String HEALTH_AI_URL = "https://7c764f8c8e1594.lhr.life";', 'String get HEALTH_AI_URL => "/health_api";')

with open(file_path, 'w', encoding='utf-8') as f:
    f.write(content)
