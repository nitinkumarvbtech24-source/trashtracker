import os
import re

file_path = r'C:\Users\LENOVO\.gemini\antigravity-ide\brain\f13d8c1f-9b19-4ba8-a6dd-bb17949a35e4\task.md'
with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

content = content.replace('- [ ] Relink constants.dart in Fleet App', '- [x] Relink constants.dart in Fleet App')
content = content.replace('- [ ] Relink constants.dart in Authority App', '- [x] Relink constants.dart in Authority App')
content = content.replace('- [ ] Clean up Settings UI in Fleet App (settings_screen.dart)', '- [x] Clean up Settings UI in Fleet App (settings_screen.dart)')
content = content.replace('- [ ] Clean up Settings UI in Authority App (settings_screen.dart)', '- [x] Clean up Settings UI in Authority App (settings_screen.dart)')
content = content.replace('- [ ] Verify changes and test functionality', '- [/] Verify changes and test functionality')

with open(file_path, 'w', encoding='utf-8') as f:
    f.write(content)
