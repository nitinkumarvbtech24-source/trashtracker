import os, re
import glob

pattern1 = 'e:/vc code/.vscode/trash tracker/AIQ_authority app/lib/**/*.dart'
pattern2 = 'e:/vc code/.vscode/trash tracker/AIQ_Fleet app/lib/**/*.dart'
files = glob.glob(pattern1, recursive=True) + glob.glob(pattern2, recursive=True)

regex = re.compile(r'Image\.network\(\s*([^,]+),')
replacement = r'Image.network(\1, headers: const {"ngrok-skip-browser-warning": "true"},'

count = 0
for f in files:
    with open(f, 'r', encoding='utf-8') as file:
        content = file.read()
    
    new_content, num_subs = regex.subn(replacement, content)
    if num_subs > 0:
        with open(f, 'w', encoding='utf-8') as file:
            file.write(new_content)
        print(f'Updated {f} with {num_subs} replacements')
        count += 1

print(f'Total files updated: {count}')
