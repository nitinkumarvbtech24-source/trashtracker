import os

file_path = r'e:\vc code\.vscode\trash tracker\AIQ_Fleet app\lib\main.dart'
with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

target = '''    final savedHealthUrl = prefs.getString('health_ai_url');
    if (savedHealthUrl != null && savedHealthUrl.isNotEmpty) {
      HEALTH_AI_URL = savedHealthUrl;
    }'''

content = content.replace(target, '')

with open(file_path, 'w', encoding='utf-8') as f:
    f.write(content)

print("Fleet main.dart fixed")
