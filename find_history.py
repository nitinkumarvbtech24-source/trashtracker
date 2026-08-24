import os
import json

history_dir = os.path.expandvars(r'%APPDATA%\Code\User\History')
if not os.path.exists(history_dir):
    print("History dir not found")
else:
    found = False
    for root, dirs, files in os.walk(history_dir):
        if 'entries.json' in files:
            with open(os.path.join(root, 'entries.json'), 'r', encoding='utf-8') as f:
                try:
                    data = json.load(f)
                    res = data.get('resource', '')
                    if 'fleet_screen.dart' in res:
                        print("Found backup for", res, "in", root)
                        found = True
                        for entry in data.get('entries', []):
                            print(entry)
                except Exception as e:
                    pass
    if not found:
        print("No fleet_screen.dart found in local history")
