import os
import re

file_path = r'e:\vc code\.vscode\trash tracker\AIQ_authority app\lib\screens\health_database_screen.dart'
with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

# Fix constructor
content = content.replace('const DatabaseScreen({super.key, this.vehicleFilter});', 'const HealthDatabaseScreen({super.key, this.vehicleFilter});')

# Fix State class type
content = content.replace('extends State<DatabaseScreen>', 'extends State<HealthDatabaseScreen>')

# Write back
with open(file_path, 'w', encoding='utf-8') as f:
    f.write(content)

print("Fixed health_database_screen.dart")
