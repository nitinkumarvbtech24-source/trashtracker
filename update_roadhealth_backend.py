import os

file_path = r'e:\vc code\.vscode\trash tracker\Roadhealthiness_ai model\modelssync-main\flask_app.py'

with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

# Replace the os.makedirs line
content = content.replace(
    'for label in ["Good_Condition", "Issues_Detected"]:',
    'for label in ["Good_Road", "Bad_Road", "Pothole_Detected"]:'
)

# Replace the road class logic in process_frame_route
old_logic = '''        road_class_str = "Good Condition"
        
        if model is not None:
            results = model(pil_image, conf=0.25, verbose=False)
            boxes = results[0].boxes
            
            if len(boxes) > 0:
                road_class_str = "Issues Detected"
                
            for box in boxes:'''

new_logic = '''        road_class_str = "Good Road"
        
        if model is not None:
            results = model(pil_image, conf=0.25, verbose=False)
            boxes = results[0].boxes
            
            has_pothole = False
            has_other_issues = False
            
            for box in boxes:
                cls_id = int(box.cls[0].cpu().numpy())
                if cls_id == 0:
                    has_pothole = True
                else:
                    has_other_issues = True
                    
            if has_pothole:
                road_class_str = "Pothole Detected"
            elif has_other_issues:
                road_class_str = "Bad Road"
            
            for box in boxes:'''

content = content.replace(old_logic, new_logic)

with open(file_path, 'w', encoding='utf-8') as f:
    f.write(content)

print("Backend updated.")
