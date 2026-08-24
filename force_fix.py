import os
import re

file_path = r'e:\vc code\.vscode\trash tracker\AIQ_Fleet app\lib\ui\camera_screen.dart'
with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

# Replace the first ??? with Tunnel + Garbage
first_replace = '''// Tunnel Indicator
                        const Icon(Icons.cloud_sync, color: Colors.white70, size: 14),
                        const SizedBox(width: 4),
                        Container(
                          width: 8, height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: (cameraService.isGarbageConnected || cameraService.isHealthConnected) ? Colors.greenAccent : Colors.redAccent,
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Garbage AI Indicator
                        const Icon(Icons.delete_outline, color: Colors.white70, size: 14)'''

content = content.replace('const Text("???", style: TextStyle(fontSize: 12))', first_replace, 1)

# Replace the second ??? with Health AI
second_replace = '''const Icon(Icons.add_road, color: Colors.white70, size: 14)'''
content = content.replace('const Text("???", style: TextStyle(fontSize: 12))', second_replace, 1)

with open(file_path, 'w', encoding='utf-8') as f:
    f.write(content)

print("done")
