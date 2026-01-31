#!/usr/bin/env python3
"""
Author: Ben Langmead with assistance from Codex
Copyright 2026

Compare run-LCP TSV outputs from TeraTools and the naive lcp.py implementation.

The script runs:
  1) utils/run_lcp_runs.py (ropebwt3 + TeraLCP + RunLCP)
  2) utils/lcp.py (naive suffix array + Kasai)

It then compares the normalized TSV outputs and reports whether they are identical.
If not identical, it prints coarse-grained statistics for each output.
"""

from __future__ import annotations

import argparse
import csv
import os
import statistics
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from typing import Iterable, List


@dataclass
class RunRecord:
    run_id: int
    run_offset: int
    run_length: int
    char: str
    lcp_values: List[int]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Compare TeraTools and naive run-LCP outputs.")
    parser.add_argument(
        "inputs",
        nargs="+",
        metavar="FASTA",
        help="FASTA files to compare (e.g. data/fasta/minishred1_20_002.fa)",
    )
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
        "--keep-temp",
        action="store_true",
        help="Keep temporary output files for inspection",
    )
    return parser.parse_args()


def load_tsv(path: str, is_naive: bool) -> List[RunRecord]:
    records: List[RunRecord] = []
    with open(path, newline="") as handle:
        reader = csv.reader(handle, delimiter="\t")
        header = next(reader, None)
        if header is None:
            return records
        for row in reader:
            if not row:
                continue
            if is_naive:
                run_id, run_len, run_offset, char, lcp_values = row
            else:
                run_id, run_offset, run_len, char, lcp_values = row
            lcp_list = [int(val) for val in lcp_values.split(",") if val != ""]
            records.append(
                RunRecord(
                    run_id=int(run_id),
                    run_offset=int(run_offset),
                    run_length=int(run_len),
                    char=char,
                    lcp_values=lcp_list,
                )
            )
    return records


def records_identical(a: List[RunRecord], b: List[RunRecord]) -> bool:
    if len(a) != len(b):
        return False
    for left, right in zip(a, b):
        if left != right:
            return False
    return True


def stats_for(records: Iterable[RunRecord]) -> dict[str, float]:
    runs = list(records)
    total_chars = sum(run.run_length for run in runs)
    total_runs = len(runs)
    lcp_values: List[int] = []
    for run in runs:
        lcp_values.extend(run.lcp_values)
    avg_lcp = statistics.mean(lcp_values) if lcp_values else 0.0
    return {
        "total_chars": float(total_chars),
        "total_runs": float(total_runs),
        "avg_lcp": float(avg_lcp),
    }


def compare_file(path: str, run_lcp: str, lcp_py: str, keep_temp: bool) -> int:
    if not os.path.exists(path):
        print(f"Error: FASTA file not found: {path}", file=sys.stderr)
        return 1

    temp_dir = tempfile.mkdtemp(prefix="tera_compare_lcp_")
    try:
        tera_out = os.path.join(temp_dir, "tera.tsv")
        naive_out = os.path.join(temp_dir, "naive.tsv")

        with open(tera_out, "w", encoding="utf-8") as handle:
            subprocess.run([run_lcp, "--fasta", path, "--header"], check=True, stdout=handle)

        with open(naive_out, "w", encoding="utf-8") as handle:
            subprocess.run(
                [lcp_py, "--fasta", path, "--separators"],
                check=True,
                stdout=handle,
            )

        tera_records = load_tsv(tera_out, is_naive=False)
        naive_records = load_tsv(naive_out, is_naive=True)

        if records_identical(tera_records, naive_records):
            print(f"{path}: outputs are identical")
        else:
            print(f"{path}: outputs differ")
            tera_stats = stats_for(tera_records)
            naive_stats = stats_for(naive_records)
            print(f"  TeraTools runs: {tera_stats['total_runs']}, chars: {tera_stats['total_chars']}, avg LCP: {tera_stats['avg_lcp']:.3f}")
            print(f"  Naive runs:     {naive_stats['total_runs']}, chars: {naive_stats['total_chars']}, avg LCP: {naive_stats['avg_lcp']:.3f}")
    except (RuntimeError, subprocess.CalledProcessError) as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 1
    finally:
        if keep_temp:
            print(f"Temporary files kept at {temp_dir}", file=sys.stderr)
        else:
            for root, dirs, files in os.walk(temp_dir, topdown=False):
                for name in files:
                    os.remove(os.path.join(root, name))
                for name in dirs:
                    os.rmdir(os.path.join(root, name))
            os.rmdir(temp_dir)
    return 0


def main() -> int:
    args = parse_args()
    failures = 0
    for path in args.inputs:
        failures += compare_file(path, args.run_lcp, args.lcp_py, args.keep_temp)
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
