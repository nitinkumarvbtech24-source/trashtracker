import os

source_file = r'e:\vc code\.vscode\trash tracker\AIQ_authority app\lib\screens\health_screen.dart'

with open(source_file, 'r', encoding='utf-8') as f:
    content = f.read()

content = content.replace("import 'database_screen.dart';", "import 'health_database_screen.dart';")
content = content.replace("const DatabaseScreen()", "const HealthDatabaseScreen()")

with open(source_file, 'w', encoding='utf-8') as f:
    f.write(content)

print("Updated health_screen.dart")
