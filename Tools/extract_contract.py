#!/usr/bin/env python3
"""Extracts the exact files ("// FILE:" blocks and the listed verbatim sections) from the
design documents into the repository. Idempotent; reports every file written.
Usage: python Tools/extract_contract.py [--dry-run]"""
import os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DESIGN = os.path.join(ROOT, "docs", "design")
APPENDIX_B_LINE = None  # computed

def read_lines(name):
    with open(os.path.join(DESIGN, name), encoding="utf-8") as f:
        return f.read().split("\n")

def fence_at(lines, start_1based):
    """Return the body lines of the fence opened at line start_1based (1-based)."""
    i = start_1based - 1
    opener = lines[i]
    m = re.match(r"^(`{3,})", opener)
    assert m, f"no fence at line {start_1based}: {opener!r}"
    ticks = m.group(1)
    body = []
    j = i + 1
    while j < len(lines):
        if lines[j].strip() == ticks:
            return body
        body.append(lines[j])
        j += 1
    raise SystemExit(f"unterminated fence at {start_1based}")

def all_file_blocks(lines, limit_line):
    out = []
    i = 0
    while i < len(lines) and i < limit_line:
        m = re.match(r"^(`{3,})(\w*)\s*$", lines[i])
        if m:
            ticks = m.group(1)
            j = i + 1
            body = []
            while j < len(lines) and lines[j].strip() != ticks:
                body.append(lines[j]); j += 1
            if body and body[0].startswith("// FILE: "):
                path = body[0][len("// FILE: "):].strip().split()[0]
                out.append((i + 1, path, body))
            i = j + 1
            continue
        i += 1
    return out

def main():
    dry = "--dry-run" in sys.argv
    c04 = read_lines("04_architecture_contract.md")
    c01c = read_lines("01c_platform_build_deploy.md")
    appendix = next(n for n, l in enumerate(c04) if l.startswith("## Appendix B"))
    written = {}

    def put(path, body_lines, source):
        text = "\n".join(body_lines).rstrip("\n") + "\n"
        if path in written:
            raise SystemExit(f"duplicate target {path} ({written[path]} and {source})")
        written[path] = source
        full = os.path.join(ROOT, path.replace("/", os.sep))
        if not dry:
            os.makedirs(os.path.dirname(full), exist_ok=True)
            with open(full, "w", encoding="utf-8", newline="\n") as f:
                f.write(text)
        print(f"{'(dry) ' if dry else ''}{path}  <- {source}  ({len(body_lines)} lines)")

    for line, path, body in all_file_blocks(c04, appendix):
        put(path, body, f"04:{line}")

    extra04 = {4086: "App/Resources/tr.lproj/AppShortcuts.strings",
               4626: "project.yml",
               4721: "Scripts/ci/package-ipa.sh",
               4818: "Tools/make_sounds.py"}
    for ln, path in extra04.items():
        put(path, fence_at(c04, ln), f"04:{ln}")

    extra01c = {281: "App/Resources/Assets.xcassets/Contents.json",
                288: "App/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json",
                307: "Tools/make_app_icon.py",
                369: "Packages/AsistCore/Package.swift",
                445: "Scripts/ci/select-xcode.sh",
                513: "Scripts/ci/install-xcodegen.sh",
                690: ".github/workflows/ci.yml",
                863: "Scripts/ci/error-summary.sh",
                1065: "Packages/AsistCore/Sources/AsistCore/Platform/ProvisioningProfile.swift",
                1223: "Packages/AsistCore/Sources/AsistCore/Platform/AppGroupResolver.swift",
                1294: "Packages/AsistCore/Sources/AsistCore/Platform/SigningExpiryPlanner.swift",
                1450: "Packages/AsistCore/Tests/AsistCoreTests/PlatformTests.swift",
                1587: ".gitignore",
                1607: ".gitattributes"}
    for ln, path in extra01c.items():
        put(path, fence_at(c01c, ln), f"01c:{ln}")
    print(f"\n{len(written)} files")

if __name__ == "__main__":
    main()
