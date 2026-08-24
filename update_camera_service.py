import os

file_path = r'e:\vc code\.vscode\trash tracker\AIQ_Fleet app\lib\services\camera_service.dart'

with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

content = content.replace(
    "if (roadStatus == 'Issues Detected' || roadStatus == 'Issues_Detected') {",
    "if (roadStatus == 'Pothole Detected' || roadStatus == 'Bad Road') {"
)

with open(file_path, 'w', encoding='utf-8') as f:
    f.write(content)

print("camera_service.dart updated.")
