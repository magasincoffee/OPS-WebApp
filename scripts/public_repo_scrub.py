#!/usr/bin/env python3
from __future__ import annotations

import argparse
import pathlib
import re
import subprocess
from collections import defaultdict

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
    ("supabase-secret-token", re.compile(r"\bsb_secret_[A-Za-z0-9_-]{20,}\b")),
    ("openai-secret-key", re.compile(r"\bsk-(?:proj-|svcacct-)?[A-Za-z0-9_-]{20,}\b")),
    ("github-token", re.compile(r"\bgh[opsu]_[A-Za-z0-9]{20,}\b")),
    ("google-api-key", re.compile(r"\bAIza[0-9A-Za-z_-]{30,}\b")),
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


def git_output(args: list[str], *, input_text: str | None = None) -> bytes:
    return subprocess.check_output(
        ["git", *args],
        cwd=ROOT,
        input=None if input_text is None else input_text.encode("utf-8"),
    )


def tracked_files() -> list[pathlib.Path]:
    out = git_output(["ls-files", "-z"])
    return [pathlib.Path(x.decode("utf-8")) for x in out.split(b"\0") if x]


def sensitive_evidence_file(path: pathlib.Path) -> bool:
    name = path.name.upper()
    return path.as_posix() == "SOURCE_OF_TRUTH.md" or (
        path.parts[:1] == ("migration",) and any(k in name for k in ("REPORT", "MANIFEST"))
    )


def scan_current_tree() -> list[str]:
    errors: list[str] = []
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

    return errors


def history_paths() -> list[pathlib.Path]:
    raw = git_output(["log", "--all", "--format=", "--name-only", "-z"])
    paths: set[pathlib.Path] = set()
    for item in raw.split(b"\0"):
        if not item:
            continue
        try:
            paths.add(pathlib.Path(item.decode("utf-8")))
        except UnicodeDecodeError:
            continue
    return sorted(paths, key=lambda p: p.as_posix())


def rev_list_objects(paths: list[pathlib.Path] | None = None) -> list[tuple[str, pathlib.Path | None]]:
    args = ["rev-list", "--objects", "--all"]
    if paths:
        args += ["--", *[p.as_posix() for p in paths]]

    rows: list[tuple[str, pathlib.Path | None]] = []
    for raw_line in git_output(args).decode("utf-8", errors="replace").splitlines():
        if not raw_line:
            continue
        sha, *rest = raw_line.split(" ", 1)
        path = pathlib.Path(rest[0]) if rest else None
        rows.append((sha, path))
    return rows


def object_types(shas: list[str]) -> dict[str, str]:
    if not shas:
        return {}

    proc = subprocess.Popen(
        ["git", "cat-file", "--batch-check=%(objectname) %(objecttype)"],
        cwd=ROOT,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert proc.stdin is not None
    assert proc.stdout is not None

    proc.stdin.write("\n".join(shas) + "\n")
    proc.stdin.close()

    result: dict[str, str] = {}
    for line in proc.stdout:
        parts = line.strip().split()
        if len(parts) >= 2:
            result[parts[0]] = parts[1]

    stderr = proc.stderr.read() if proc.stderr is not None else ""
    rc = proc.wait()
    if rc != 0:
        raise RuntimeError(f"git cat-file --batch-check failed: {stderr.strip()}")

    return result


def read_blob_texts(shas: list[str]):
    if not shas:
        return

    proc = subprocess.Popen(
        ["git", "cat-file", "--batch"],
        cwd=ROOT,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    assert proc.stdin is not None
    assert proc.stdout is not None

    proc.stdin.write(("\n".join(shas) + "\n").encode("ascii"))
    proc.stdin.close()

    for requested_sha in shas:
        header = proc.stdout.readline()
        if not header:
            break
        parts = header.decode("ascii", errors="replace").strip().split()
        if len(parts) < 3 or parts[1] != "blob":
            continue

        size = int(parts[2])
        data = proc.stdout.read(size)
        proc.stdout.read(1)  # trailing newline
        try:
            text = data.decode("utf-8")
        except UnicodeDecodeError:
            continue
        yield requested_sha, text

    stderr = proc.stderr.read() if proc.stderr is not None else b""
    rc = proc.wait()
    if rc != 0:
        raise RuntimeError(f"git cat-file --batch failed: {stderr.decode('utf-8', errors='replace').strip()}")


def summarize_paths(paths: set[str], limit: int = 8) -> str:
    ordered = sorted(paths)
    shown = ordered[:limit]
    suffix = "" if len(ordered) <= limit else f" (+{len(ordered) - limit} more)"
    return ", ".join(shown) + suffix


def scan_history() -> list[str]:
    errors: list[str] = []
    paths = history_paths()

    forbidden = {p.as_posix() for p in paths if p.suffix.lower() in FORBIDDEN_EXTENSIONS}
    if forbidden:
        errors.append(
            "history: forbidden operational/private file extension in "
            f"{len(forbidden)} path(s): {summarize_paths(forbidden)}"
        )

    all_rows = rev_list_objects()
    unique_shas = list(dict.fromkeys(sha for sha, _ in all_rows))
    types = object_types(unique_shas)

    first_path_by_sha: dict[str, str] = {}
    blob_shas: list[str] = []
    for sha, path in all_rows:
        if types.get(sha) != "blob":
            continue
        if sha not in first_path_by_sha and path is not None:
            first_path_by_sha[sha] = path.as_posix()
        if sha not in blob_shas:
            blob_shas.append(sha)

    secret_hits: dict[str, set[str]] = defaultdict(set)
    for sha, text in read_blob_texts(blob_shas):
        path = first_path_by_sha.get(sha, "<unknown>")
        if path == SELF.as_posix():
            continue
        for label, pattern in SECRET_PATTERNS:
            if pattern.search(text):
                secret_hits[label].add(path)

    for label, matched_paths in sorted(secret_hits.items()):
        errors.append(
            f"history: matched {label} in {len(matched_paths)} path(s): "
            f"{summarize_paths(matched_paths)}"
        )

    evidence_paths = [p for p in paths if sensitive_evidence_file(p)]
    if evidence_paths:
        evidence_rows = rev_list_objects(evidence_paths)
        evidence_unique_shas = list(dict.fromkeys(sha for sha, _ in evidence_rows))
        evidence_types = object_types(evidence_unique_shas)

        evidence_path_by_sha: dict[str, set[str]] = defaultdict(set)
        evidence_blob_shas: list[str] = []
        for sha, path in evidence_rows:
            if evidence_types.get(sha) != "blob":
                continue
            if path is not None:
                evidence_path_by_sha[sha].add(path.as_posix())
            if sha not in evidence_blob_shas:
                evidence_blob_shas.append(sha)

        business_hits: dict[str, set[str]] = defaultdict(set)
        for sha, text in read_blob_texts(evidence_blob_shas):
            for label, pattern in BUSINESS_EVIDENCE_PATTERNS:
                if pattern.search(text):
                    business_hits[label].update(evidence_path_by_sha.get(sha, {"<unknown>"}))

        for label, matched_paths in sorted(business_hits.items()):
            errors.append(
                f"history: sensitive evidence matched {label} in {len(matched_paths)} path(s): "
                f"{summarize_paths(matched_paths)}"
            )

    return errors


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--history",
        action="store_true",
        help="also scan the full reachable Git history without printing matched secret values",
    )
    args = parser.parse_args()

    errors = scan_current_tree()
    if args.history:
        errors.extend(scan_history())

    if errors:
        print("PUBLIC REPOSITORY SCRUB: FAIL")
        for err in errors:
            print(f"- {err}")
        return 1

    mode = "CURRENT TREE + FULL HISTORY" if args.history else "CURRENT TREE"
    print(f"PUBLIC REPOSITORY SCRUB: PASS ({mode})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
