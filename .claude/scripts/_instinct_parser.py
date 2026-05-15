"""Minimal stdlib-only YAML reader for .claude/instincts.yaml.

The file follows a tightly-bounded subset of YAML:
  - top-level is a flat list (one ``- name: ...`` block per entry)
  - per entry:
      name:        scalar string
      trigger:     nested 2-key dict (kind, optional glob, optional not_glob)
      guidance:    list of one-line strings (``    - ...``)
      refs:        optional scalar string
  - values are unquoted plain strings, no inline flow style, no anchors,
    no multi-line scalars.

Why a hand-rolled parser:
  the runtime test container is Alpine bats:1.11.0 + `apk add python3`,
  and PyYAML is not in the package set (and the registry is unreachable
  in sandboxed builds). A 60-line subset parser keeps the dependency
  surface to the stdlib so `instinct-query.sh` ships with no install
  step.

This module exposes one function, ``parse_instincts(path)``, returning
a ``list[dict]`` with keys ``name``, ``trigger`` (dict), ``guidance``
(list of str), and ``refs`` (str or "").
"""
from __future__ import annotations

import re
from typing import Any


_ENTRY_START = re.compile(r"^- name: (.+)$")
_KEY_LINE = re.compile(r"^  (name|trigger|guidance|refs): ?(.*)$")
_TRIGGER_INLINE = re.compile(r"^  trigger: \{(.+)\}$")
_TRIGGER_NESTED_KEY = re.compile(r"^    (kind|glob|not_glob): (.+)$")
_GUIDANCE_ITEM = re.compile(r"^    - (.+)$")


def _strip_quotes(value: str) -> str:
    value = value.strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in ("'", '"'):
        return value[1:-1]
    return value


def _parse_inline_trigger(body: str) -> dict[str, str]:
    """Parse ``kind: foo, glob: '**/*.sh'`` -> {kind: foo, glob: **/*.sh}.

    Splits on top-level commas only (the values are short scalars without
    nesting in the schema we support).
    """
    out: dict[str, str] = {}
    for piece in body.split(","):
        piece = piece.strip()
        if not piece or ":" not in piece:
            continue
        k, v = piece.split(":", 1)
        out[k.strip()] = _strip_quotes(v)
    return out


def parse_instincts(path: str) -> list[dict[str, Any]]:
    entries: list[dict[str, Any]] = []
    current: dict[str, Any] | None = None
    section: str | None = None  # "trigger" | "guidance" | None

    with open(path, encoding="utf-8") as fh:
        for raw in fh:
            line = raw.rstrip("\n")

            # skip comments / blanks
            stripped = line.strip()
            if not stripped or stripped.startswith("#"):
                continue

            m = _ENTRY_START.match(line)
            if m:
                if current is not None:
                    entries.append(current)
                current = {
                    "name": _strip_quotes(m.group(1)),
                    "trigger": {},
                    "guidance": [],
                    "refs": "",
                }
                section = None
                continue

            if current is None:
                # ignore stray lines before the first entry
                continue

            m = _TRIGGER_INLINE.match(line)
            if m:
                current["trigger"] = _parse_inline_trigger(m.group(1))
                section = None
                continue

            m = _KEY_LINE.match(line)
            if m:
                key, val = m.group(1), m.group(2)
                if key == "trigger":
                    # value should be empty (nested block follows); guard
                    current["trigger"] = {}
                    section = "trigger"
                elif key == "guidance":
                    current["guidance"] = []
                    section = "guidance"
                elif key == "refs":
                    current["refs"] = _strip_quotes(val)
                    section = None
                elif key == "name":
                    # entries with the long-form `  name: ...` continuation
                    # are not expected, but tolerate.
                    current["name"] = _strip_quotes(val)
                    section = None
                continue

            if section == "trigger":
                m = _TRIGGER_NESTED_KEY.match(line)
                if m:
                    current["trigger"][m.group(1)] = _strip_quotes(m.group(2))
                continue

            if section == "guidance":
                m = _GUIDANCE_ITEM.match(line)
                if m:
                    current["guidance"].append(_strip_quotes(m.group(1)))
                continue

        if current is not None:
            entries.append(current)

    return entries
