import os
import re

file_path = r'C:\Users\LENOVO\.gemini\antigravity-ide\brain\f13d8c1f-9b19-4ba8-a6dd-bb17949a35e4\task.md'
with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

content = content.replace('- [/] Fix App Startup State in Fleet App (main.dart)', '- [x] Fix App Startup State in Fleet App (main.dart)')
content = content.replace('- [ ] Fix App Startup State in Authority App (main.dart)', '- [x] Fix App Startup State in Authority App (main.dart)')

with open(file_path, 'w', encoding='utf-8') as f:
    f.write(content)
