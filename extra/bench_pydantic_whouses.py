from __future__ import annotations

import argparse
import json
import sys
import time
from typing import List, Literal

import orjson
from pydantic import BaseModel, ConfigDict, Field, PositiveInt, TypeAdapter


# --- Pydantic models matching who-uses-json-v1 ---
class Match(BaseModel):
    line: PositiveInt
    column: PositiveInt


class FileResult(BaseModel):
    path: str
    matches: List[Match]


class ProjectResult(BaseModel):
    project: str
    files: List[FileResult]


class Summary(BaseModel):
    projects_with_hits: int
    files_with_hits: int
    total_matches: int


class JSONOptions(BaseModel):
    deps_only: bool
    include_venv: bool
    projects_only: bool


class WhoUsesJSONv1(BaseModel):
    model_config = ConfigDict(extra="forbid", populate_by_name=True)
    schema_: Literal["who-uses-json-v1"] = Field(alias="schema")
    cmd: str
    term: str
    options: JSONOptions
    results: List[ProjectResult]
    summary: Summary


def _ms(dt: float) -> float:
    return dt * 1000.0


def main() -> int:
    ap = argparse.ArgumentParser(
        prog="bench_pydantic_whouses.py",
        description="Benchmark Pydantic v2 parsing/validation on who-uses-json-v1 payloads.",
    )
    ap.add_argument(
        "--n",
        type=int,
        default=0,
        help="Number of repeated parses for throughput. If 0, choose automatically based on input size.",
    )
    ap.add_argument(
        "--target-mb",
        type=int,
        default=200,
        help="When --n=0, aim to process about this many MB total (default: 200).",
    )
    ap.add_argument(
        "--no-breakdown",
        action="store_true",
        help="Skip decode/validate breakdown (faster run).",
    )
    args = ap.parse_args()

    raw = sys.stdin.buffer.read()
    if not raw.strip():
        print("ERROR: pass JSON on stdin", file=sys.stderr)
        return 2

    adapter = TypeAdapter(WhoUsesJSONv1)

    size = len(raw)
    if args.n and args.n > 0:
        N = args.n
        n_reason = "manual"
    else:
        target_bytes = max(1, args.target_mb) * 1024 * 1024
        N = max(50, min(50_000, target_bytes // max(1, size)))
        n_reason = f"auto(target≈{args.target_mb}MB)"

    # 1) validate_json (bytes -> model)
    t0 = time.perf_counter()
    model = adapter.validate_json(raw)
    t1 = time.perf_counter()

    # 2) dump_json (model -> json string)
    t2 = time.perf_counter()
    out = model.model_dump_json()
    t3 = time.perf_counter()

    # 3) Throughput loop (validate_json repeated)
    t4 = time.perf_counter()
    for _ in range(N):
        adapter.validate_json(raw)
    t5 = time.perf_counter()

    validate_1x_ms = _ms(t1 - t0)
    dump_ms = _ms(t3 - t2)
    parses_per_sec = N / (t5 - t4) if (t5 - t4) > 0 else float("inf")

    print("== Pydantic v2 benchmark on who-uses-json-v1 ==")
    print(f"input_bytes:        {size:,}")
    print(f"validate_json (1x): {validate_1x_ms:.3f} ms")
    print(f"dump_json     (1x): {dump_ms:.3f} ms")
    print(f"validate_json:      {parses_per_sec:,.0f} parses/sec (N={N}, {n_reason})")
    print(f"output_bytes:       {len(out):,}")

    if args.no_breakdown:
        return 0

    # --- breakdown: decode vs validation ---
    # A) stdlib json.loads (decode only)
    t6 = time.perf_counter()
    obj_std = json.loads(raw)
    t7 = time.perf_counter()

    # B) orjson.loads (decode only)
    t8 = time.perf_counter()
    obj_orj = orjson.loads(raw)
    t9 = time.perf_counter()

    # C) validate_python on stdlib-decoded object
    t10 = time.perf_counter()
    adapter.validate_python(obj_std)
    t11 = time.perf_counter()

    # D) validate_python on orjson-decoded object (should be same structure)
    t12 = time.perf_counter()
    adapter.validate_python(obj_orj)
    t13 = time.perf_counter()

    # E) throughput validate_python on orjson object
    M = min(10_000, max(200, N))
    t14 = time.perf_counter()
    for _ in range(M):
        adapter.validate_python(obj_orj)
    t15 = time.perf_counter()
    vpy_per_sec = M / (t15 - t14) if (t15 - t14) > 0 else float("inf")

    print("-- breakdown --")
    print(f"json.loads     (1x): {_ms(t7 - t6):.3f} ms")
    print(f"orjson.loads   (1x): {_ms(t9 - t8):.3f} ms")
    print(f"validate_py std(1x): {_ms(t11 - t10):.3f} ms")
    print(f"validate_py orj(1x): {_ms(t13 - t12):.3f} ms")
    print(f"validate_py (orj):   {vpy_per_sec:,.0f} validates/sec (M={M})")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())