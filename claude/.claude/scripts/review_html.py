#!/usr/bin/env python3
"""review_html.py — generate a self-contained HTML review page.

(unified diff text, explanations.json, lang) -> one standalone .html file.
Pure rendering, Python stdlib only. Driven by the /review-html Claude command.
"""
from __future__ import annotations

import argparse
import html
import json
import os
import sys
import tempfile


def hunk_id(file_idx: int, hunk_idx: int) -> str:
    """Stable anchor id for a hunk: file index + hunk index, e.g. 'F0H1'."""
    return f"F{file_idx}H{hunk_idx}"
