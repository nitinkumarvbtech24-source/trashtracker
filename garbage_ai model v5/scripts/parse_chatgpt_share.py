import json
import re
from pathlib import Path

path = Path(r"C:\Users\yashw\.gemini\antigravity-ide/brain/19816049-68c5-4316-a7c5-2418030472fe/.system_generated/steps/652/content.md")
text = path.read_text(encoding="utf-8", errors="ignore")

matches = re.findall(r'streamController\.enqueue\(("(?:[^"\\]|\\.)*")\);', text)

out_file = Path(r"e:\nitin\model2\results\parsed_chatgpt_convo.txt")
out_file.parent.mkdir(parents=True, exist_ok=True)

with open(out_file, "w", encoding="utf-8") as f:
    f.write("==================================================\n")
    f.write("FULL CHATGPT SHARED CONVERSATION EXPORT\n")
    f.write("==================================================\n\n")

    for m in matches:
        raw_str = json.loads(m)
        tokens = re.findall(r'\\"((?:[^\\"]|\\.)*)\\"', raw_str)
        for idx, t in enumerate(tokens, 1):
            clean = t.replace('\\n', '\n').replace('\\"', '"')
            if len(clean) > 20 and not any(k in clean for k in ['statsig', 'feature_gates', 'modulepreload', 'http://', 'https://', 'csrf', 'assets/']):
                f.write(f"\n--- [PARSED BLOCK {idx}] ---\n")
                f.write(clean + "\n")

print(f"Parsed ChatGPT conversation written to {out_file}")
