"""Combine observed extended-state verdicts without promoting captures to passes."""
import collections
import json
import pathlib

root = pathlib.Path(__file__).resolve().parent
plan = json.loads((root / "plan.json").read_text())
frames = {r["id"]: r for r in json.loads((root.parent / "figma-frames.json").read_text())}
states = [("max_text:" + fid, "Maximum text: " + frames[fid]["name"]) for fid in plan["fidelity_ids_at_max_text"]]
states += [("real:" + route, "Real data: " + route) for route in plan["real_routes"]]
states += [("denied:" + route, "Access denied: " + route) for route in plan["denied_routes"]]
reports = {}
for device in plan["devices"]:
    path = root / device / "results.json"
    rows = json.loads(path.read_text()) if path.exists() else []
    assert isinstance(rows, list), str(path)
    assert len({r["key"] for r in rows}) == len(rows), "Duplicate result keys: " + device
    assert all(r["status"] in {"pass", "issue", "blocked"} for r in rows), "Unknown status: " + device
    reports[device] = {r["key"]: r for r in rows}
totals = collections.Counter(reports[d].get(key, {}).get("status", "pending") for key, _ in states for d in reports)
symbols = {"pass": "✅ adaptation/chrome", "issue": "❌ issue", "blocked": "⛔ blocked", "pending": "⏳ pending"}
lines = ["# Extended-state verification — updated 2026-11-11", "",
         f"{len(states)} configurations × 3 sizes = {len(states) * 3} planned cells. " + ", ".join(f"{v} {k}" for k, v in totals.items()) + ".", "",
         "Confirmed accessibility defects were corrected on 2026-11-11 and affected states rechecked. The previous582 fixture matches remain a separate, narrower baseline; per-device history retains initial defects.", "",
         "Reference: cached Figma snapshot2026-11-10. A pass here means inspected adaptation or corresponding design chrome, not pixel identity. Maximum text and most system-denial states have no dedicated source frame. See [reference gaps](source-gaps.md) and [build/source hashes](build-evidence.json).", "",
         "| Mode / state | SE | Pro | Max |", "|---|---|---|---|"]
for key, name in states:
    cells = [symbols[reports[d].get(key, {}).get("status", "pending")] for d in reports]
    lines.append("| " + name.replace("|", "/") + " | " + " | ".join(cells) + " |")
lines += ["", "## Observed issues and blocked cells", ""]
for device, rows in reports.items():
    for key, r in rows.items():
        if r["status"] == "pass":
            continue
        findings = r.get("findings", [])
        detail = "; ".join(str(f) for f in findings) or "See device evidence."
        lines.append(f"- **{device.upper()} · {key} · {r['status']}**: {detail}")
lines += ["", "## Supplemental checks", ""]
planned = {key for key, _ in states}
for device, rows in reports.items():
    for key, r in rows.items():
        if key not in planned:
            lines.append(f"- {device.upper()} · {key}: {r['status']} — " + "; ".join(str(f) for f in r.get("findings", [])))
lines += ["", "Per-cell screenshots, comparison notes and scroll evidence: [SE](se/results.json), [Pro](pro/results.json), [Max](max/results.json).", "",
          "Not established by this matrix: physical-device Vision/export success, configured StoreKit transaction failures, cloud-only media failures, controlled password-service errors, and corrupt/partial-restore failures. These require external setup or safe failure injection; see source-gaps.md.", ""]
(root / "REPORT.md").write_text("\n".join(lines))
print(dict(totals))
