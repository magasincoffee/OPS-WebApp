#!/usr/bin/env python3
from __future__ import annotations

import pathlib
import re
import subprocess

ROOT = pathlib.Path(__file__).resolve().parents[1]
SELF = pathlib.Path("scripts/public_repo_scrub.py")
FORBIDDEN_EXTENSIONS = {".xlsx", ".xls", ".csv", ".jsonl", ".parquet", ".sqlite", ".db", ".pem", ".key"}

SECRET_PATTERNS = [
    ("private-key", re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----")),
    ("service-role-assignment", re.compile(
        r"(?:SUPABASE_SERVICE_ROLE_KEY|SUPABASE_SECRET_KEY|POSTGRES_PASSWORD|DATABASE_URL|OPENAI_API_KEY)"
        r"\s*[:=]\s*[\"']?(?!YOUR_|<|REDACTED)[^\s\"']{8,}",
        re.IGNORECASE,
    )),
    ("google-drive-url", re.compile(r"https://(?:docs|drive)\.google\.com/[^\s)\"']*[A-Za-z0-9_-]{20,}")),
    ("drive-id-json", re.compile(
        r"\"(?:drive_id|source_file_id|snapshot_drive_id|file_id)\"\s*:\s*\"[A-Za-z0-9_-]{20,}\""
    )),
]

BUSINESS_EVIDENCE_PATTERNS = [
    ("legacy-order-id", re.compile(r"\bDH-\d{6,}(?:-\d+)?\b")),
    ("large-vnd-control", re.compile(r"\b\d{1,3}(?:[.,]\d{3})+\s*VND\b", re.IGNORECASE)),
    ("snapshot-sha256", re.compile(r"\b[a-f0-9]{64}\b", re.IGNORECASE)),
]

def tracked_files():
    out = subprocess.check_output(["git", "ls-files", "-z"], cwd=ROOT)
    return [pathlib.Path(x.decode("utf-8")) for x in out.split(b"\0") if x]

def sensitive_evidence_file(path):
    name = path.name.upper()
    return path.as_posix() == "SOURCE_OF_TRUTH.md" or (
        path.parts[:1] == ("migration",) and any(k in name for k in ("REPORT", "MANIFEST"))
    )

def main():
    errors = []
    for rel in tracked_files():
        if rel == SELF:
            continue
        if rel.suffix.lower() in FORBIDDEN_EXTENSIONS:
            errors.append(f"{rel}: forbidden tracked operational/private file type")
            continue
        full = ROOT / rel
        try:
            text = full.read_text(encoding="utf-8")
        except (UnicodeDecodeError, IsADirectoryError):
            continue
        for label, pattern in SECRET_PATTERNS:
            if pattern.search(text):
                errors.append(f"{rel}: matched {label}")
        if sensitive_evidence_file(rel):
            for label, pattern in BUSINESS_EVIDENCE_PATTERNS:
                if pattern.search(text):
                    errors.append(f"{rel}: matched {label}")
    if errors:
        print("PUBLIC REPOSITORY SCRUB: FAIL")
        for err in errors:
            print(f"- {err}")
        return 1
    print("PUBLIC REPOSITORY SCRUB: PASS")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
