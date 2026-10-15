import os
import sys
from pathlib import Path

# function_app.py imports its siblings as top-level modules, like the Functions
# host does, so the functions/ folder must be on sys.path.
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

# Read at import time by config.py; the value is irrelevant in tests.
os.environ.setdefault("SBUS_QUEUE", "test-queue")
