import re

with open(r'C:\Users\LENOVO\AppData\Roaming\Antigravity IDE\User\History\337ec40e\8Vsj.dart', 'r', encoding='utf-8') as f:
    text = f.read()

# Extract _showNameWardDialog
ward_match = re.search(r'(void _showNameWardDialog\(\) \{.*?\n  \})', text, re.DOTALL)
zone_match = re.search(r'(void _showNameZoneDialog\(\) \{.*?\n  \})', text, re.DOTALL)

with open('extracted_methods.txt', 'w', encoding='utf-8') as f:
    if ward_match:
        f.write(ward_match.group(1) + '\n\n')
    if zone_match:
        f.write(zone_match.group(1) + '\n\n')
