#!/usr/bin/env python3
"""OPS-071 deterministic spreadsheet staging entrypoint.

The implementation payload is stored losslessly as gzip in
`ops_071_stage_source.py.gz`. Keeping the entrypoint small lets GitHub retain
both a stable CLI and the exact tested parser payload. The payload uses only the
Python standard library and is executed in this module namespace so helper
functions remain importable by the unit tests.
"""
from __future__ import annotations

import gzip
from pathlib import Path

_PAYLOAD = Path(__file__).with_name("ops_071_stage_source.py.gz")
_SOURCE = gzip.decompress(_PAYLOAD.read_bytes())
exec(compile(_SOURCE, str(_PAYLOAD.with_suffix("")), "exec"), globals(), globals())
