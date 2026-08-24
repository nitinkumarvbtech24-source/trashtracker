import os
import re

file_path = r'e:\vc code\.vscode\trash tracker\AIQ_authority app\lib\screens\settings_screen.dart'
with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

# Remove state vars
state_vars_old = '''  Map<String, String> _savedHealthLinks = {};
  String? _selectedHealthLinkKey;'''
content = content.replace(state_vars_old, '')

# Remove from initState
init_old = '''    _loadSavedHealthLinks();'''
content = content.replace(init_old, '')

# Remove methods using regex
pattern = r'  Future<void> _loadSavedHealthLinks\(\).*?void _showAddHealthLinkDialog\(\).*?    \);[\r\n]+  \}'
content = re.sub(pattern, '', content, flags=re.DOTALL)

with open(file_path, 'w', encoding='utf-8') as f:
    f.write(content)

print("Authority settings_screen.dart fixed")
