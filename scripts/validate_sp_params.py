#!/usr/bin/env python3
"""
NGOConnect -- SP Parameter Validator
=====================================
Compares stored procedure IN-parameter declarations in the setup SQL
against what each DAL actually passes via _db.AddParameter / AddWithValue.

Usage:
    python scripts/validate_sp_params.py

Exit code:
    0  = all clear
    1  = mismatches found (blocks deployment)

Run this before every Railway deploy to catch SP <-> DAL drift early.
"""

import re
import sys
from pathlib import Path

# -- Paths --------------------------------------------------------------------
ROOT      = Path(__file__).parent.parent
SETUP_SQL = ROOT / "Documents" / "NGOConnect_Complete_Setup_v4.8.sql"
DAL_DIR   = ROOT / "NGOConnect.Infrastructure" / "DAL"


# -- Step 1: Parse SP declarations from setup SQL -----------------------------
def parse_sp_params(sql_path):
    """
    Returns { "Sp_Name": ["p_param1", "p_param2", ...] }
    Covers single-line and multi-line CREATE PROCEDURE signatures.
    """
    text = sql_path.read_text(encoding="utf-8", errors="ignore")

    # \w+\s*:\s* handles MySQL labeled blocks like "main_block: BEGIN"
    pattern = re.compile(
        r"CREATE\s+PROCEDURE\s+(\w+)\s*\((.*?)\)\s*(?:\w+\s*:\s*)?(?:BEGIN|//)",
        re.IGNORECASE | re.DOTALL
    )

    sp_params = {}
    for m in pattern.finditer(text):
        sp_name  = m.group(1).strip()
        sig_body = m.group(2)
        params   = re.findall(r"\bIN\s+(p_\w+)", sig_body, re.IGNORECASE)
        sp_params[sp_name] = [p.lower() for p in params]

    return sp_params


# -- Step 2: Parse DAL files for SP calls + params passed ---------------------
def parse_dal_calls(dal_dir):
    """
    Returns { "SomeDal.cs": { "Sp_Name": ["p_param1", ...] } }
    """
    results = {}

    dal_files = list(dal_dir.glob("**/*.cs"))
    if not dal_files:
        print("[WARN] No .cs files found under " + str(dal_dir))
        return results

    # SP name: a quoted string matching Module_Action pattern passed to Execute methods
    sp_call_re = re.compile(r'"([A-Z][A-Za-z]+(?:_[A-Za-z0-9]+)+)"')

    # Parameter additions:
    #   _db.AddParameter(cmd, "p_X", ...)  <- primary pattern in this codebase
    #   cmd.Parameters.AddWithValue("p_X", ...)
    #   cmd.Parameters.Add("p_X", ...)
    param_re = re.compile(
        r'AddParameter\s*\(\s*\w+\s*,\s*"(p_\w+)"|'
        r'\.(?:AddWithValue|Add)\s*\(\s*"(p_\w+)"',
        re.IGNORECASE
    )

    for cs_file in dal_files:
        text  = cs_file.read_text(encoding="utf-8", errors="ignore")
        lines = text.splitlines()

        file_key          = cs_file.name
        results[file_key] = {}
        current_sp        = None
        collected         = []

        for line in lines:
            stripped = line.lstrip()
            # Skip C# comment lines — they often contain example SP names
            if stripped.startswith("//") or stripped.startswith("*") or stripped.startswith("/*"):
                continue

            sp_match = sp_call_re.search(line)
            if sp_match:
                candidate = sp_match.group(1)
                if "_" in candidate and not candidate.startswith("p_"):
                    if current_sp:
                        results[file_key][current_sp] = collected
                    current_sp = candidate
                    collected  = []

            for pm in param_re.finditer(line):
                pname = (pm.group(1) or pm.group(2) or "").lower()
                if pname and pname not in collected:
                    collected.append(pname)

        if current_sp and collected:
            results[file_key][current_sp] = collected

    return results


# -- Step 3: Cross-reference and report --------------------------------------
def validate(sp_params, dal_calls):
    """Returns list of human-readable mismatch strings."""
    issues = []

    for dal_file, sp_map in dal_calls.items():
        for sp_name, dal_passed in sp_map.items():
            if sp_name not in sp_params:
                continue  # not an SP name -- helper string, skip

            declared = set(sp_params[sp_name])
            passed   = set(dal_passed)

            missing_from_dal = declared - passed
            extra_in_dal     = passed   - declared

            if missing_from_dal or extra_in_dal:
                issues.append("")
                issues.append("  [" + dal_file + "] -> " + sp_name)
                if missing_from_dal:
                    issues.append("    MISSING in DAL  : " + str(sorted(missing_from_dal)))
                if extra_in_dal:
                    issues.append("    EXTRA in DAL    : " + str(sorted(extra_in_dal)))

    return issues


# -- Main --------------------------------------------------------------------
def main():
    sep = "=" * 60
    print(sep)
    print("  NGOConnect SP Parameter Validator")
    print(sep)

    if not SETUP_SQL.exists():
        print("[ERROR] Setup SQL not found: " + str(SETUP_SQL))
        return 1

    if not DAL_DIR.exists():
        print("[ERROR] DAL directory not found: " + str(DAL_DIR))
        return 1

    print("\n[1/3] Parsing SP declarations from " + SETUP_SQL.name + " ...")
    sp_params = parse_sp_params(SETUP_SQL)
    print("      Found " + str(len(sp_params)) + " stored procedures.")

    print("\n[2/3] Scanning DAL files in " + str(DAL_DIR) + " ...")
    dal_calls = parse_dal_calls(DAL_DIR)
    total_sp_calls = sum(len(v) for v in dal_calls.values())
    print("      Found " + str(len(dal_calls)) + " DAL files, " + str(total_sp_calls) + " SP call sites.")

    print("\n[3/3] Cross-referencing parameters ...")
    issues = validate(sp_params, dal_calls)

    print()
    if not issues:
        print("  [OK] All SP parameters match their DAL callers. Safe to deploy.")
        return 0
    else:
        mismatch_count = sum(1 for i in issues if i.startswith("  ["))
        print("  [FAIL] " + str(mismatch_count) + " SP(s) with mismatches -- fix before deploying:\n")
        for line in issues:
            print(line)
        print()
        return 1


if __name__ == "__main__":
    sys.exit(main())
