import os

file_path = r'e:\vc code\.vscode\trash tracker\AIQ_authority app\lib\screens\health_screen.dart'

with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

# 1. Firebase Query Filter
content = content.replace(
    "f.className == 'Issues_Detected' || f.displayClass == 'Issues Detected'",
    "f.className == 'Pothole_Detected' || f.displayClass == 'Pothole Detected' || f.className == 'Bad_Road' || f.displayClass == 'Bad Road'"
)

# 2. Pie Chart Data
content = content.replace(
    "double dirtyVal = _healthFlags.where((f) => f.className == 'Issues_Detected' || f.className == 'Damaged_road' || f.className == 'Pothole').length.toDouble();",
    "double dirtyVal = _healthFlags.where((f) => f.className == 'Pothole_Detected' || f.displayClass == 'Pothole Detected').length.toDouble();"
)
content = content.replace(
    "double moderateVal = _healthFlags.where((f) => f.className == 'Debris' || f.className == 'Abandoned_Vehicle').length.toDouble();",
    "double moderateVal = _healthFlags.where((f) => f.className == 'Bad_Road' || f.displayClass == 'Bad Road').length.toDouble();"
)

# 3. Polyline Colors
content = content.replace(
    "if (status == 'Issues_Detected') segmentColor = Colors.redAccent;",
    "if (status == 'Pothole_Detected' || status == 'Pothole Detected') segmentColor = Colors.redAccent;\n        else if (status == 'Bad_Road' || status == 'Bad Road') segmentColor = Colors.orangeAccent;"
)

# 4. Marker Colors
content = content.replace(
    "markerColor = Colors.redAccent;",
    "markerColor = (flag.className == 'Pothole_Detected' || flag.displayClass == 'Pothole Detected') ? Colors.redAccent : Colors.orangeAccent;"
)
content = content.replace(
    "if (flag.className == 'Issues_Detected') color = Colors.redAccent;",
    "if (flag.className == 'Pothole_Detected' || flag.displayClass == 'Pothole Detected') color = Colors.redAccent;\n                      else if (flag.className == 'Bad_Road' || flag.displayClass == 'Bad Road') color = Colors.orangeAccent;"
)

# 5. Legend
content = content.replace(
    "'Damaged / Pothole'",
    "'Pothole Detected'"
)
content = content.replace(
    "'Debris / Abandoned Vehicle'",
    "'Bad Road'"
)

with open(file_path, 'w', encoding='utf-8') as f:
    f.write(content)

print("health_screen.dart updated.")
