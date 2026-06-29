from pathlib import Path
from datetime import datetime
import subprocess
import sys

SCRIPT_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = SCRIPT_DIR.parent

if len(sys.argv) != 2:
    print(f"Usage: {Path(sys.argv[0]).name} <YYYY-MM-DD>")
    sys.exit(1)

DATE = sys.argv[1]

try:
    datetime.strptime(DATE, "%Y-%m-%d")
except ValueError:
    print("Error: date must be in YYYY-MM-DD format.")
    sys.exit(1)

hour_script = PROJECT_ROOT / "jobs" / "download_hour_job.py"

for hour in range(24):

    print()
    print("=" * 70)
    print(f"Downloading hour {hour:02d}")
    print("=" * 70)
    print()

    result = subprocess.run(
        [
            sys.executable,
            str(hour_script),
            DATE,
            f"{hour:02d}",
        ]
    )

    if result.returncode != 0:
        print(f"\nHour {hour:02d} failed.")
        sys.exit(result.returncode)

print()
print("Day download complete.")