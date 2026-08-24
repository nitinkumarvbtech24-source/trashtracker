import os
import re

file_path = r'e:\vc code\.vscode\trash tracker\AIQ_Fleet app\lib\ui\camera_screen.dart'
with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

# Replace connection UI in camera_screen.dart
old_ui = '''                  Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: cameraService.isBackendConnected ? Colors.greenAccent : Colors.redAccent,
                          boxShadow: [
                            BoxShadow(
                              color: cameraService.isBackendConnected ? Colors.greenAccent.withOpacity(0.5) : Colors.redAccent.withOpacity(0.5),
                              blurRadius: 8,
                            )
                          ]
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        cameraService.isBackendConnected ? "Connected" : "Offline",
                        style: TextStyle(
                          color: cameraService.isBackendConnected ? Colors.greenAccent : Colors.redAccent,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      )
                    ],
                  ),'''
new_ui = '''                  Row(
                    children: [
                      // Garbage AI Indicator
                      const Text("???", style: TextStyle(fontSize: 12)),
                      const SizedBox(width: 4),
                      Container(
                        width: 8, height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: cameraService.isGarbageConnected ? Colors.greenAccent : Colors.redAccent,
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Health AI Indicator
                      const Text("???", style: TextStyle(fontSize: 12)),
                      const SizedBox(width: 4),
                      Container(
                        width: 8, height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: cameraService.isHealthConnected ? Colors.greenAccent : Colors.redAccent,
                        ),
                      ),
                    ],
                  ),'''

content = content.replace(old_ui, new_ui)

with open(file_path, 'w', encoding='utf-8') as f:
    f.write(content)

print("camera_screen.dart updated.")
