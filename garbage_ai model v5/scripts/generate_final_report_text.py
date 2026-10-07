import os
import sys
from pathlib import Path

if sys.platform == "win32":
    sys.stdout.reconfigure(encoding='utf-8')

BASE_DIR = Path(r"e:\nitin\model2")
REPORT_PATH = BASE_DIR / "results_trash_detector" / "missed_trash_analysis" / "failure_analysis_report.txt"

if REPORT_PATH.exists():
    with open(REPORT_PATH, "r", encoding="utf-8") as f:
        print(f.read())
else:
    print(f"Report not found at {REPORT_PATH}")
