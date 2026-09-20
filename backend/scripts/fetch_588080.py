#!/usr/bin/env python3
"""CLI utility to scrape and export complete page data for 588080.com.

Usage:
  python backend/scripts/fetch_588080.py -o out/588080.html -j out/588080.json
"""
import sys
from pathlib import Path

# Add backend directory and backend/collector to sys.path
BACKEND_DIR = Path(__file__).resolve().parent.parent
COLLECTOR_DIR = BACKEND_DIR / "collector"

if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))
if str(COLLECTOR_DIR) not in sys.path:
    sys.path.insert(0, str(COLLECTOR_DIR))

from collector.fetch_588080 import main

if __name__ == "__main__":
    main()
