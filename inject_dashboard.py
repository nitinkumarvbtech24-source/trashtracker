import os
import re

# 1. Extract the dashboard template from garbage ai model v3
source_path = r'e:\vc code\.vscode\trash tracker\garbage ai model v3\flask_demo_app.py'
with open(source_path, 'r', encoding='utf-8') as f:
    source_content = f.read()

dashboard_match = re.search(r'DASHBOARD_TEMPLATE = """(.*?)"""', source_content, re.DOTALL)
if dashboard_match:
    dashboard_html = dashboard_match.group(1)
else:
    print("Could not find DASHBOARD_TEMPLATE")
    exit(1)

# Transform the HTML for Road Health
dashboard_html = dashboard_html.replace('Road Cleanliness Analyzer', 'Road Health Monitor')
dashboard_html = dashboard_html.replace('Road Cleanliness Monitoring Dashboard', 'Road Health Monitoring Dashboard')

# Update stats cards
dashboard_html = dashboard_html.replace('Clean Roads', 'Good Roads')
dashboard_html = dashboard_html.replace('val-clean', 'val-good')

dashboard_html = dashboard_html.replace('Slightly Dirty', 'Bad Roads')
dashboard_html = dashboard_html.replace('val-slightly', 'val-bad')

dashboard_html = dashboard_html.replace('Very Dirty', 'Potholes Detected')
dashboard_html = dashboard_html.replace('val-very', 'val-pothole')

# Update color classes
dashboard_html = dashboard_html.replace('--clean-color: #00e676;', '--good-color: #00e676;')
dashboard_html = dashboard_html.replace('--slightly-color: #ff9100;', '--bad-color: #ff9100;')
dashboard_html = dashboard_html.replace('--very-color: #ff1744;', '--pothole-color: #ff1744;')

dashboard_html = dashboard_html.replace('var(--clean-color)', 'var(--good-color)')
dashboard_html = dashboard_html.replace('var(--slightly-color)', 'var(--bad-color)')
dashboard_html = dashboard_html.replace('var(--very-color)', 'var(--pothole-color)')

dashboard_html = dashboard_html.replace('.flag.clean', '.flag.good')
dashboard_html = dashboard_html.replace('.flag.slightly', '.flag.bad')
dashboard_html = dashboard_html.replace('.flag.very', '.flag.pothole')

dashboard_html = dashboard_html.replace('.stat-card.clean', '.stat-card.good')
dashboard_html = dashboard_html.replace('.stat-card.slightly', '.stat-card.bad')
dashboard_html = dashboard_html.replace('.stat-card.very', '.stat-card.pothole')

# Update JS logic
dashboard_html = dashboard_html.replace(
    'document.getElementById("val-clean").textContent = stats["Clean Road"] || 0;',
    'document.getElementById("val-good").textContent = stats["Good Road"] || 0;'
)
dashboard_html = dashboard_html.replace(
    'document.getElementById("val-slightly").textContent = stats["Slightly Dirty Road"] || 0;',
    'document.getElementById("val-bad").textContent = stats["Bad Road"] || 0;'
)
dashboard_html = dashboard_html.replace(
    'document.getElementById("val-very").textContent = stats["Very Dirty Road"] || 0;',
    'document.getElementById("val-pothole").textContent = stats["Pothole Detected"] || 0;'
)

# Replace class determination logic in JS
js_old = '''        function getFlagClass(label) {
            if (label === 'Clean Road') return 'clean';
            if (label === 'Slightly Dirty Road') return 'slightly';
            if (label === 'Very Dirty Road') return 'very';
            if (label === 'Not a Road') return 'notaroad';
            return 'clean';
        }'''
js_new = '''        function getFlagClass(label) {
            if (label === 'Good Road') return 'good';
            if (label === 'Bad Road') return 'bad';
            if (label === 'Pothole Detected') return 'pothole';
            if (label === 'Not a Road') return 'notaroad';
            return 'good';
        }'''
dashboard_html = dashboard_html.replace(js_old, js_new)


# 2. Modify flask_app.py
target_path = r'e:\vc code\.vscode\trash tracker\Roadhealthiness_ai model\modelssync-main\flask_app.py'
with open(target_path, 'r', encoding='utf-8') as f:
    target_content = f.read()

# Fix folder_name bug
old_folder_logic = 'folder_name = "Issues_Detected" if road_class_str == "Issues Detected" else "Good_Condition"'
new_folder_logic = 'folder_name = road_class_str.replace(" ", "_")'
target_content = target_content.replace(old_folder_logic, new_folder_logic)

# Insert DASHBOARD_TEMPLATE
target_content = target_content.replace('HTML_TEMPLATE = """', f'DASHBOARD_TEMPLATE = """{dashboard_html}"""\n\nHTML_TEMPLATE = """')

# Insert Routes
routes_code = '''
@app.route('/dashboard')
def dashboard():
    return render_template_string(DASHBOARD_TEMPLATE)

@app.route('/api/snapshots', methods=['GET'])
def get_snapshots():
    return jsonify(recent_snapshots)
'''

target_content = target_content.replace("@app.route('/')", f"{routes_code}\n@app.route('/')")

with open(target_path, 'w', encoding='utf-8') as f:
    f.write(target_content)

print("Dashboard injected into Road Health backend.")
