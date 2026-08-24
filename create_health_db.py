import os

source_file = r'e:\vc code\.vscode\trash tracker\AIQ_authority app\lib\screens\database_screen.dart'
dest_file = r'e:\vc code\.vscode\trash tracker\AIQ_authority app\lib\screens\health_database_screen.dart'

with open(source_file, 'r', encoding='utf-8') as f:
    content = f.read()

content = content.replace('class DatabaseScreen', 'class HealthDatabaseScreen')
content = content.replace('_DatabaseScreenState', '_HealthDatabaseScreenState')
content = content.replace('activeGarbageAiUrl', 'activeHealthAiUrl')
content = content.replace('Road Cleanliness Analyzer', 'Road Health Analyzer')

# Update stats
content = content.replace('"Clean Road": 0, "Slightly Dirty Road": 0, "Very Dirty Road": 0, "Not a Road": 0', '"Good Road": 0, "Bad Road": 0, "Pothole Detected": 0, "Not a Road": 0')
content = content.replace("'Clean Road').length", "'Good Road').length")
content = content.replace("'Slightly Dirty Road').length", "'Bad Road').length")
content = content.replace("'Very Dirty Road').length", "'Pothole Detected').length")
content = content.replace('"Clean Road": _snapshots', '"Good Road": _snapshots')
content = content.replace('"Slightly Dirty Road": _snapshots', '"Bad Road": _snapshots')
content = content.replace('"Very Dirty Road": _snapshots', '"Pothole Detected": _snapshots')

# Update getClassColor
content = content.replace("className == 'Clean Road'", "className == 'Good Road'")
content = content.replace("className == 'Slightly Dirty Road'", "className == 'Bad Road'")
content = content.replace("className == 'Very Dirty Road'", "className == 'Pothole Detected'")

# Update tabs
content = content.replace("'Clean Road', Icons.folder_rounded, const Color(0xFF00E676)", "'Good Road', Icons.folder_rounded, const Color(0xFF00E676)")
content = content.replace("'Slightly Dirty Road', Icons.folder_rounded, const Color(0xFFFF9100)", "'Bad Road', Icons.folder_rounded, const Color(0xFFFF9100)")
content = content.replace("'Very Dirty Road', Icons.folder_special_rounded, const Color(0xFFFF1744)", "'Pothole Detected', Icons.warning_rounded, const Color(0xFFFF1744)")

# Update stat cards using regex to avoid quote escaping issues
import re
content = re.sub(r'_buildStatCard\("Clean Roads", _stats\[.*?\] \?\? 0', '_buildStatCard("Good Roads", _stats["Good Road"] ?? 0', content)
content = re.sub(r'_buildStatCard\("Slightly Dirty", _stats\[.*?\] \?\? 0', '_buildStatCard("Bad Roads", _stats["Bad Road"] ?? 0', content)
content = re.sub(r'_buildStatCard\("Very Dirty", _stats\[.*?\] \?\? 0', '_buildStatCard("Potholes Detected", _stats["Pothole Detected"] ?? 0', content)

with open(dest_file, 'w', encoding='utf-8') as f:
    f.write(content)

print("Created health_database_screen.dart")
