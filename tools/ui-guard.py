#!/usr/bin/env python3
"""Compatibility entry point for the v9 UI guard.

The canonical implementation lives in ui-lint.py; both names are kept so the
original PRD and the current frontend quality guidelines point at one gate.
"""
from pathlib import Path
import runpy
import sys

script = Path(__file__).with_name("ui-lint.py")
sys.argv = [str(script), *sys.argv[1:]]
runpy.run_path(str(script), run_name="__main__")
