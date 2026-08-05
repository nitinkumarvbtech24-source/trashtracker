import json

file_path = r"C:\Users\LENOVO\.gemini\antigravity-ide\brain\a4de22d5-58cb-4dda-b6d3-d8dd0750840b\.system_generated\logs\transcript_full.jsonl"
target_step = 281
chunks = None

with open(file_path, 'r', encoding='utf-8') as f:
    for line in f:
        data = json.loads(line)
        if data.get('step_index') == target_step:
            if 'tool_calls' in data:
                for tc in data['tool_calls']:
                    if tc['name'] == 'multi_replace_file_content':
                        chunks = tc['args']['ReplacementChunks']
                        print("Found chunks:", len(chunks))

if chunks:
    with open(r"e:\vc code\.vscode\trash tracker\AIQ_authority app\lib\screens\cleanliness_screen.dart", 'r', encoding='utf-8') as f:
        content = f.read()
    
    for chunk in chunks:
        old_text = chunk['TargetContent']
        new_text = chunk['ReplacementContent']
        
        if new_text in content:
            content = content.replace(new_text, old_text)
            print("Successfully reverted a chunk.")
        else:
            print("Warning: new_text not found in file.")
            
    with open(r"e:\vc code\.vscode\trash tracker\AIQ_authority app\lib\screens\cleanliness_screen.dart", 'w', encoding='utf-8') as f:
        f.write(content)
