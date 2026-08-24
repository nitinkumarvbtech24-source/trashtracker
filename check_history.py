import os
import json

history_dir = r'C:\Users\LENOVO\AppData\Roaming\Antigravity IDE\User\History\337ec40e'
entries_path = os.path.join(history_dir, 'entries.json')

with open(entries_path, 'r', encoding='utf-8') as f:
    data = json.load(f)
    entries = data.get('entries', [])
    for entry in sorted(entries, key=lambda x: x.get('timestamp', 0), reverse=True):
        file_id = entry.get('id')
        file_path = os.path.join(history_dir, file_id)
        if os.path.exists(file_path):
            with open(file_path, 'r', encoding='utf-8') as f2:
                lines = f2.readlines()
                print(f"Timestamp: {entry.get('timestamp')}, File: {file_id}, Lines: {len(lines)}")
