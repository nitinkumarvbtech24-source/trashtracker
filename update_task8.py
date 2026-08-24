import os
import re

file_path = r'C:\Users\LENOVO\.gemini\antigravity-ide\brain\f13d8c1f-9b19-4ba8-a6dd-bb17949a35e4\task.md'
with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

content = content.replace('- [ ] Implement Top Filter Bar (Zone, Ward, Date, Toggle)', '- [x] Implement Top Filter Bar (Zone, Ward, Date, Toggle)')
content = content.replace('- [ ] Implement 4 KPI Stat Cards', '- [x] Implement 4 KPI Stat Cards')
content = content.replace('- [ ] Redesign Map section (light theme)', '- [x] Redesign Map section (light theme)')
content = content.replace('- [ ] Redesign Line Chart (green gradient)', '- [x] Redesign Line Chart (green gradient)')
content = content.replace('- [ ] Redesign Donut Chart (Waste Condition Distribution)', '- [x] Redesign Donut Chart (Waste Condition Distribution)')
content = content.replace('- [ ] Test and Verify with lutter analyze', '- [x] Test and Verify with lutter analyze')
content = content.replace('- [/] Set up light theme and bottom navigation bar colors', '- [x] Set up light theme and bottom navigation bar colors')

with open(file_path, 'w', encoding='utf-8') as f:
    f.write(content)
