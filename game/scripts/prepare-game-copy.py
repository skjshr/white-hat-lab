#!/usr/bin/env python3
"""Extract Japanese display strings into reviewable Gemini batches.

This tool only reads game/scripts/*.gd and game/content/*.json.  It writes a
manifest containing the exact source text plus occurrence metadata; it never
rewrites source files.
"""

from __future__ import annotations

import ast
import hashlib
import json
import re
from pathlib import Path


JAPANESE = re.compile(r"[\u3040-\u30ff\u3400-\u4dbf\u4e00-\u9fff々ー]")
TOKEN = re.compile(r"(?P<quote>['\"])(?P<body>(?:\\.|(?!\1).)*)\1")
PLACEHOLDER = re.compile(r"%(?:\d+\$)?[sdif%]|\{[^{}]+\}")


def decode_literal(raw: str) -> str:
    try:
        value = ast.literal_eval(raw)
        return value if isinstance(value, str) else str(value)
    except Exception:
        return raw[1:-1]


def stable_id(text: str) -> str:
    return "copy-" + hashlib.sha1(text.encode("utf-8")).hexdigest()[:12]


def callsite(lines: list[str], line_no: int) -> str:
    for index in range(line_no - 1, max(-1, line_no - 12), -1):
        match = re.search(r"func\s+([A-Za-z0-9_]+)", lines[index])
        if match:
            return match.group(1)
    return "module"


def extract(path: Path, root: Path) -> list[dict]:
    text = path.read_text(encoding="utf-8")
    lines = text.splitlines()
    found: list[dict] = []
    for match in TOKEN.finditer(text):
        value = decode_literal(match.group(0))
        if not JAPANESE.search(value):
            continue
        line_no = text.count("\n", 0, match.start()) + 1
        rel = path.relative_to(root).as_posix()
        found.append({
            "id": stable_id(value),
            "text": value,
            "sourcefile": rel,
            "line": line_no,
            "callsite": callsite(lines, line_no),
            "context": lines[line_no - 1].strip()[:240],
            "placeholders": PLACEHOLDER.findall(value),
            "source_kind": "gdscript" if path.suffix == ".gd" else "content",
        })
    return found


def main() -> None:
    project = Path(__file__).resolve().parents[1]
    output = project.parent / "artifacts" / "simulator" / "v15-copy"
    output.mkdir(parents=True, exist_ok=True)
    # The old lesson corpus under content/ is intentionally excluded from the
    # Gemini review package; this package covers the current game's UI/runtime.
    # Exclude the legacy lesson corpus; this review covers the current game runtime.
    files = sorted(project.glob("scripts/*.gd")) + sorted(project.glob("content/*.json"))
    occurrences: list[dict] = []
    for path in files:
        occurrences.extend(extract(path, project))

    grouped: dict[str, dict] = {}
    for occurrence in occurrences:
        entry = grouped.setdefault(occurrence["id"], {
            "id": occurrence["id"],
            "text": occurrence["text"],
            "placeholders": occurrence["placeholders"],
            "occurrences": [],
        })
        entry["occurrences"].append({key: occurrence[key] for key in ("sourcefile", "line", "callsite", "context", "source_kind")})

    manifest = {
        "schema": "white-hat-lab-copy-review-v1",
        "source_scope": ["game/scripts/*.gd", "game/content/*.json"],
        "source_files": [path.relative_to(project).as_posix() for path in files],
        "entry_count": len(grouped),
        "occurrence_count": len(occurrences),
        "entries": sorted(grouped.values(), key=lambda item: item["id"]),
    }
    (output / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    for old_batch in output.glob("batch-*.json"):
        old_batch.unlink()
    compact = []
    for entry in manifest["entries"]:
        first = entry["occurrences"][0]
        source = first["sourcefile"]
        category = "case" if "case_catalog" in source else ("ui" if "interface" in source or "business_apps" in source else ("terminal" if "shell" in source or "editor" in source or "diagnostics" in source else ("office" if "office" in source else "game")))
        compact.append({"id": entry["id"], "text": entry["text"], "category": category})
    compact_path = output / "compact-catalog.json"
    compact_path.write_text(json.dumps({"schema": manifest["schema"], "entries": compact}, ensure_ascii=False, separators=(",", ":")) + "\n", encoding="utf-8")

    prompt = """あなたは日本語UI校正担当です。添付compact-catalog.jsonの各textを確認し、全項目を確認し、変更が必要な項目だけ返してください。初心者が操作対象と次の行動をすぐ理解できる自然で簡潔な日本語にします。原文の意味、案件条件、技術的な正誤、固有名、コマンド、パス、数値、%d/%s等のプレースホルダー、{}プレースホルダー、改行、記号を必ず保持してください。再測定、納品、保存、反映などの用語は統一し、UI文言は短くしてください。説明文を新規追加しません。形式は[{\"id\":\"...\",\"original\":\"...\",\"revised\":\"...\",\"changes\":[\"...\"]}]です。コード、秘密、個人情報は扱わず、技術識別子を翻訳しないでください。"""
    (output / "prompt.txt").write_text(prompt + "\n", encoding="utf-8")
    print(json.dumps({"entries": len(grouped), "occurrences": len(occurrences), "compact_bytes": compact_path.stat().st_size, "output": str(output)}, ensure_ascii=False))


if __name__ == "__main__":
    main()
