import os

file_path = r'e:\vc code\.vscode\trash tracker\AIQ_authority app\lib\constants.dart'
with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

target = '''String get activeHealthAiUrl {
  return HEALTH_AI_URL;
}'''

new_val = '''String get activeHealthAiUrl {
  return "/health_api";
}'''

content = content.replace(target, new_val)

with open(file_path, 'w', encoding='utf-8') as f:
    f.write(content)
