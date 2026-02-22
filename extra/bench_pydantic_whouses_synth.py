from __future__ import annotations

import argparse
import time
from typing import List, Literal

import orjson
from pydantic import BaseModel, ConfigDict, Field, PositiveInt, TypeAdapter


# ----------------------------
# Pydantic models (who-uses-json-v1-like)
# ----------------------------
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


# ----------------------------
# Synthetic payload generator
# ----------------------------
def make_payload(
    *,
    term: str,
    n_projects: int,
    files_per_project: int,
    matches_per_file: int,
) -> dict:
    results = []
    total_matches = 0

    # keep strings short but realistic-ish
    for p in range(n_projects):
        files = []
        for f in range(files_per_project):
            # deterministic match positions
            matches = [{"line": i + 1, "column": 1} for i in range(matches_per_file)]
            total_matches += matches_per_file
            files.append({"path": f"src/mod{f}.py", "matches": matches})

        results.append({"project": f"proj{p}", "files": files})

    payload = {
        "schema": "who-uses-json-v1",
        "cmd": "scan",
        "term": term,
        "options": {"deps_only": False, "include_venv": False, "projects_only": True},
        "results": results,
        "summary": {
            "projects_with_hits": n_projects,
            "files_with_hits": n_projects * files_per_project,
            "total_matches": total_matches,
        },
    }
    return payload


def ms(dt: float) -> float:
    return dt * 1000.0


def main() -> int:
    ap = argparse.ArgumentParser(
        prog="bench_pydantic_whouses_synth.py",
        description="Generate a who-uses-json-v1-like payload and benchmark Pydantic validate_json vs orjson.loads+validate_python.",
    )
    ap.add_argument("--term", default="PHP")
    ap.add_argument("--projects", type=int, default=200)
    ap.add_argument("--files", type=int, default=30, help="files per project")
    ap.add_argument("--matches", type=int, default=10, help="matches per file")
    ap.add_argument("--n", type=int, default=200, help="repetitions for throughput loops")
    args = ap.parse_args()

    payload = make_payload(
        term=args.term,
        n_projects=args.projects,
        files_per_project=args.files,
        matches_per_file=args.matches,
    )

    raw = orjson.dumps(payload)  # bytes
    adapter = TypeAdapter(WhoUsesJSONv1)

    # warmup
    adapter.validate_json(raw)

    # validate_json (1x)
    t0 = time.perf_counter()
    m = adapter.validate_json(raw)
    t1 = time.perf_counter()

    # dump_json (1x)
    t2 = time.perf_counter()
    out = m.model_dump_json()
    t3 = time.perf_counter()

    # validate_json throughput
    N = args.n
    t4 = time.perf_counter()
    for _ in range(N):
        adapter.validate_json(raw)
    t5 = time.perf_counter()
    vjson_per_sec = N / (t5 - t4)

    # breakdown: orjson.loads + validate_python
    t6 = time.perf_counter()
    obj = orjson.loads(raw)
    t7 = time.perf_counter()

    t8 = time.perf_counter()
    adapter.validate_python(obj)
    t9 = time.perf_counter()

    t10 = time.perf_counter()
    for _ in range(N):
        adapter.validate_python(obj)
    t11 = time.perf_counter()
    vpy_per_sec = N / (t11 - t10)

    print("== synthetic who-uses-json-v1-like benchmark ==")
    print(f"shape: projects={args.projects}, files={args.files}, matches={args.matches}")
    print(f"payload_bytes:      {len(raw):,}")
    print(f"validate_json (1x): {ms(t1-t0):.3f} ms")
    print(f"dump_json     (1x): {ms(t3-t2):.3f} ms")
    print(f"validate_json:      {vjson_per_sec:,.2f} parses/sec (N={N})")
    print("-- breakdown (orjson path) --")
    print(f"orjson.loads  (1x): {ms(t7-t6):.3f} ms")
    print(f"validate_py   (1x): {ms(t9-t8):.3f} ms")
    print(f"validate_py:        {vpy_per_sec:,.2f} validates/sec (N={N})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())