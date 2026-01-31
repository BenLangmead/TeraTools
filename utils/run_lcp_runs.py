#!/usr/bin/env python3
"""
Run ropebwt3 + TeraLCP to emit per-run LCP lists.

Pipeline:
  1) ropebwt3 build -> <base>.fmd
  2) TeraLCP -oindex -> <base>.lcp_index
  3) RunLCP -> tab-separated run metadata with LCP values
"""

import argparse
import os
import subprocess
import sys
import tempfile


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Compute run LCP lists using ropebwt3 + TeraLCP."
    )
    parser.add_argument(
        "input",
        nargs="?",
        default=None,
        metavar="STRING_OR_FASTA",
        help="Input string or FASTA file (use --string or --fasta to disambiguate)",
    )
    parser.add_argument("--string", metavar="S", help="Input string to index")
    parser.add_argument("--fasta", metavar="FILE", help="Input FASTA file")
    parser.add_argument(
        "--header", action="store_true", help="Print a header row before records"
    )
    parser.add_argument(
        "--keep-temp",
        action="store_true",
        help="Keep temporary files (for debugging)",
    )
    parser.add_argument(
        "--ropebwt3",
        default=os.path.join("ropebwt3", "ropebwt3"),
        help="Path to the ropebwt3 binary (default: ropebwt3/ropebwt3)",
    )
    parser.add_argument(
        "--teralcp",
        default=os.path.join("src", "TeraLCP", "TeraLCP"),
        help="Path to the TeraLCP binary (default: src/TeraLCP/TeraLCP)",
    )
    parser.add_argument(
        "--runlcp",
        default=os.path.join("src", "TeraLCP", "RunLCP"),
        help="Path to the RunLCP binary (default: src/TeraLCP/RunLCP)",
    )
    return parser.parse_args()


def resolve_input(args: argparse.Namespace) -> tuple[str, bool]:
    if args.fasta and args.string:
        raise ValueError("Provide only one of --fasta or --string.")
    if args.fasta:
        return args.fasta, False
    if args.string:
        return args.string, True
    if args.input is None:
        raise ValueError("No input provided.")
    if args.input.endswith(".fa") or args.input.endswith(".fasta"):
        return args.input, False
    return args.input, True


def run_checked(cmd: list[str]) -> None:
    result = subprocess.run(cmd, check=False, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if result.returncode != 0:
        stdout = result.stdout.strip()
        stderr = result.stderr.strip()
        if stdout:
            print(stdout, file=sys.stderr)
        if stderr:
            print(stderr, file=sys.stderr)
        raise RuntimeError(f"Command failed: {' '.join(cmd)}")


def main() -> int:
    args = parse_args()
    try:
        input_value, is_string = resolve_input(args)
    except ValueError as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 1

    for path in (args.ropebwt3, args.teralcp, args.runlcp):
        if not os.path.exists(path):
            print(f"Error: required binary not found: {path}", file=sys.stderr)
            return 1

    temp_dir = tempfile.mkdtemp(prefix="tera_run_lcp_")
    try:
        fasta_path = input_value
        if is_string:
            fasta_path = os.path.join(temp_dir, "input.fa")
            with open(fasta_path, "w", encoding="utf-8") as handle:
                handle.write(">seq\n")
                handle.write(f"{input_value}\n")

        fmd_path = os.path.join(temp_dir, "index.fmd")
        ropebwt_cmd = [args.ropebwt3, "build", "-Ldo", fmd_path, fasta_path]
        run_checked(ropebwt_cmd)

        lcp_index_base = os.path.join(temp_dir, "index")
        temp_file = os.path.join(temp_dir, "tempfile")
        tera_cmd = [
            args.teralcp,
            "-f",
            "fmd",
            "-i",
            fmd_path,
            "-oindex",
            lcp_index_base,
            "-t",
            temp_file,
        ]
        run_checked(tera_cmd)

        lcp_index_path = f"{lcp_index_base}.lcp_index"
        run_cmd = [args.runlcp, "-i", lcp_index_path]
        if args.header:
            run_cmd.append("--header")
        subprocess.run(run_cmd, check=True)
    except (RuntimeError, subprocess.CalledProcessError) as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 1
    finally:
        if args.keep_temp:
            print(f"Temporary files kept at {temp_dir}", file=sys.stderr)
        else:
            for root, dirs, files in os.walk(temp_dir, topdown=False):
                for name in files:
                    os.remove(os.path.join(root, name))
                for name in dirs:
                    os.rmdir(os.path.join(root, name))
            os.rmdir(temp_dir)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
