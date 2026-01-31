#!/usr/bin/env python3
"""
Author: Ben Langmead with assistance from Codex
Copyright 2026

Run RunLCP vs naive LCP comparisons without pytest.
"""

from __future__ import annotations

import argparse
import os
import sys

from compare_run_lcp import compare_file


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run RunLCP comparison checks.")
    parser.add_argument(
        "--run-lcp",
        default=os.path.join("utils", "run_lcp_runs.py"),
        help="Path to utils/run_lcp_runs.py",
    )
    parser.add_argument(
        "--lcp-py",
        default=os.path.join("utils", "lcp.py"),
        help="Path to utils/lcp.py",
    )
    parser.add_argument(
        "inputs",
        nargs="*",
        metavar="FASTA",
        help="FASTA files to compare (default: data/fasta/minishred1_20_002.fa data/fasta/yeast.fasta)",
    )
    return parser.parse_args()


def default_inputs() -> list[str]:
    return [
        os.path.join("data", "fasta", "minishred1_20_002.fa"),
        os.path.join("data", "fasta", "yeast.fasta"),
    ]


def main() -> int:
    args = parse_args()
    inputs = args.inputs or default_inputs()
    failures = 0
    for path in inputs:
        failures += compare_file(path, args.run_lcp, args.lcp_py, keep_temp=False)
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
