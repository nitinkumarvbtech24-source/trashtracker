import os
import re

file_path = r'e:\vc code\.vscode\trash tracker\AIQ_Fleet app\lib\ui\camera_screen.dart'
with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

target = '''                    Row(
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

new_ui = '''                    Row(
                      children: [
                        // Tunnel Indicator
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
                        const Icon(Icons.delete_outline, color: Colors.white70, size: 14),
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
                        const Icon(Icons.add_road, color: Colors.white70, size: 14),
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

content = content.replace(target, new_ui)

with open(file_path, 'w', encoding='utf-8') as f:
    f.write(content)

print("camera_screen.dart updated with material icons.")
