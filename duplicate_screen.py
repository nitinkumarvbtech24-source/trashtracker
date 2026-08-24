import os

source_path = r'e:\vc code\.vscode\trash tracker\AIQ_authority app\lib\screens\cleanliness_screen.dart'
dest_path = r'e:\vc code\.vscode\trash tracker\AIQ_authority app\lib\screens\health_screen.dart'

with open(source_path, 'r', encoding='utf-8') as f:
    content = f.read()

# Perform replacements
content = content.replace('CleanlinessScreen', 'HealthScreen')
content = content.replace('_CleanlinessScreenState', '_HealthScreenState')
content = content.replace('GarbageFlag', 'HealthFlag')
content = content.replace('trash_spots', 'health_spots')
content = content.replace('Street Cleanliness AI', 'Road Health Monitor')
content = content.replace('Overall Cleanliness', 'Overall Health')
content = content.replace('_garbageFlags', '_healthFlags')
content = content.replace('_garbageTimer', '_healthTimer')

# The cleanliness screen checks for 'Very_Dirty' and 'Slightly_Dirty'.
# We want to replace these checks with 'Issues_Detected' or 'Issues Detected'.
content = content.replace("f.className == 'Very_Dirty' || f.className == 'Slightly_Dirty' || f.displayClass == 'Very Dirty' || f.displayClass == 'Slightly Dirty'", "f.className == 'Issues_Detected' || f.displayClass == 'Issues Detected'")

content = content.replace("f.className == 'Clean'", "f.className == 'Good_Condition' || f.displayClass == 'Good Condition'")

# Map colors
content = content.replace("if (status == 'Very_Dirty') segmentColor = Colors.redAccent;", "if (status == 'Issues_Detected') segmentColor = Colors.redAccent;")
content = content.replace("else if (status == 'Slightly_Dirty') segmentColor = Colors.orangeAccent;", "")

# Pie chart data
content = content.replace("double dirtyVal = _healthFlags.where((f) => f.className == 'Very_Dirty').length.toDouble();", "double dirtyVal = _healthFlags.where((f) => f.className == 'Issues_Detected' || f.className == 'Damaged_road' || f.className == 'Pothole').length.toDouble();")
content = content.replace("double moderateVal = _healthFlags.where((f) => f.className == 'Slightly_Dirty').length.toDouble();", "double moderateVal = _healthFlags.where((f) => f.className == 'Debris' || f.className == 'Abandoned_Vehicle').length.toDouble();")

content = content.replace("markerColor = (flag.className == 'Very_Dirty') ? Colors.redAccent : Colors.orangeAccent;", "markerColor = Colors.redAccent;")
content = content.replace("if (flag.className == 'Very_Dirty') color = Colors.redAccent;", "if (flag.className == 'Issues_Detected') color = Colors.redAccent;")
content = content.replace("else if (flag.className == 'Slightly_Dirty') color = Colors.orangeAccent;", "")

# Remove old Very_Dirty text in legend
content = content.replace("'Very Dirty'", "'Damaged / Pothole'")
content = content.replace("'Slightly Dirty'", "'Debris / Abandoned Vehicle'")

with open(dest_path, 'w', encoding='utf-8') as f:
    f.write(content)

print('health_screen.dart created successfully.')
