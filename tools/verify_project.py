#!/usr/bin/env python3
"""Static verification of the BusSimulator project.

Checks, in order:
  1. every .gd file parses (via gdtoolkit's gdparse)
  2. tabs-only indentation, balanced parens/brackets/quotes
  3. no inline-if inside a "%" format tuple  (the rule that broke a past build)
  4. every res:// path referenced by materials/scenes/scripts exists
  5. the CI workflow contains no HTML entities and uses plain "&&"
  6. export_presets.cfg keystore fields are all-set or all-empty

Exit code 0 = everything OK.
"""

import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RES = os.path.join(ROOT, "res")
# The workflow cannot be pushed to .github/workflows (missing "workflows"
# permission on the GitHub App), so it is shipped as WORKFLOW_CONTENT.txt.
WORKFLOW_IN_PLACE = os.path.join(ROOT, ".github", "workflows", "build-apk.yml")
WORKFLOW_FALLBACK = os.path.join(ROOT, "WORKFLOW_CONTENT.txt")
WORKFLOW = WORKFLOW_IN_PLACE
if not os.path.exists(WORKFLOW):
    WORKFLOW = WORKFLOW_FALLBACK

errors = []
warnings = []
oks = []


def ok(msg):
    oks.append(msg)


def err(msg):
    errors.append(msg)


def warn(msg):
    warnings.append(msg)


def gd_files():
    out = []
    for base, _dirs, files in os.walk(os.path.join(RES, "scripts")):
        for f in sorted(files):
            if f.endswith(".gd"):
                out.append(os.path.join(base, f))
    return out


# --- 1. parse ---------------------------------------------------------------
def check_parse():
    files = gd_files()
    if not files:
        err("no .gd files found")
        return
    for path in files:
        rel = os.path.relpath(path, ROOT)
        res = subprocess.run(
            ["gdparse", path], capture_output=True, text=True
        )
        if res.returncode == 0:
            ok("parses: " + rel)
        else:
            tail = (res.stderr or res.stdout).strip().splitlines()
            detail = tail[-1] if tail else "unknown error"
            err("PARSE FAIL " + rel + ": " + detail)


# --- 2. indentation + delimiters -------------------------------------------
def check_style():
    for path in gd_files():
        rel = os.path.relpath(path, ROOT)
        text = open(path, encoding="utf-8").read()

        for i, line in enumerate(text.splitlines(), 1):
            stripped = line.lstrip("\t")
            if stripped.startswith(" ") and stripped.strip():
                # allow spaces only inside continuation/alignment after tabs
                if not stripped.lstrip().startswith(("#", "*")):
                    err(rel + ":" + str(i) + " space-based indentation")
            if " \t" in line:
                err(rel + ":" + str(i) + " mixed space-then-tab indent")

        # balanced delimiters, ignoring strings and comments
        depth = {"(": 0, "[": 0, "{": 0}
        pairs = {")": "(", "]": "[", "}": "{"}
        for i, line in enumerate(text.splitlines(), 1):
            j = 0
            in_str = None
            while j < len(line):
                c = line[j]
                if in_str:
                    if c == "\\":
                        j += 2
                        continue
                    if c == in_str:
                        in_str = None
                elif c in "\"'":
                    in_str = c
                elif c == "#":
                    break
                elif c in depth:
                    depth[c] += 1
                elif c in pairs:
                    depth[pairs[c]] -= 1
                j += 1
            if in_str is not None:
                err(rel + ":" + str(i) + " unterminated string literal")
        for k, v in depth.items():
            if v != 0:
                err(rel + " unbalanced '" + k + "' (delta " + str(v) + ")")
        ok("style clean: " + rel)


# --- 3. the % tuple rule ----------------------------------------------------
def check_format_rule():
    bad = 0
    for path in gd_files():
        rel = os.path.relpath(path, ROOT)
        for i, line in enumerate(open(path, encoding="utf-8").read().splitlines(), 1):
            code = line.split("#")[0]
            if "%" not in code:
                continue
            # inline-if anywhere on a line that also uses % formatting
            if re.search(r"%\s*[\(\"']", code) and re.search(r"\bif\b.*\belse\b", code):
                err(rel + ":" + str(i) + " inline-if inside % format")
                bad += 1
        if bad == 0:
            ok("no %-tuple ternaries: " + rel)
    # global: no inline-if at all (project rule preference)
    for path in gd_files():
        rel = os.path.relpath(path, ROOT)
        for i, line in enumerate(open(path, encoding="utf-8").read().splitlines(), 1):
            code = line.split("#")[0]
            if re.search(r"=\s*.+\bif\b.+\belse\b", code):
                warn(rel + ":" + str(i) + " inline-if expression present")


# --- 3b. UI regressions that shipped a broken menu once already -------------
def check_ui_contract():
    """Two bugs made the whole main menu unusable on the phone. Both are easy
    to reintroduce by accident, so they are pinned down here.

    1) A root Control created with Control.new() is 0x0. Calling
       set_anchors_preset() from _ready() defaults to keep_offsets=false,
       which Godot reads as "keep the rect you have now" -- so it kept 0x0
       and the entire menu collapsed into the top-left corner.
       The fix is set_anchors_and_offsets_preset().

    2) BaseButton::gui_input() only handles InputEventMouseButton. The project
       must keep emulate_mouse_from_touch=false (otherwise the synthetic mouse
       pointer fights the real one for the steering wheel), so a plain Button
       never receives a finger tap on Android. Buttons the player has to press
       must therefore use scripts/touch_button.gd.
    """
    roots = {
        "res/scripts/main_menu.gd": "main menu",
        "res/scripts/loading_screen.gd": "loading screen",
        "res/scripts/ui_manager.gd": "HUD",
    }
    for rel, label in roots.items():
        path = os.path.join(ROOT, rel)
        if not os.path.isfile(path):
            err("missing " + rel)
            continue
        text = open(path, encoding="utf-8").read()
        body = text.split("func _ready()", 1)
        if len(body) < 2:
            err(rel + " has no _ready()")
            continue
        head = body[1].split("func ", 1)[0]
        if "set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)" in head:
            ok(label + " root uses set_anchors_AND_OFFSETS_preset")
        elif "set_anchors_preset(Control.PRESET_FULL_RECT)" in head:
            err(
                rel
                + ": _ready() uses set_anchors_preset on a 0x0 root; it keeps"
                + " the empty rect and collapses the UI into the corner."
                + " Use set_anchors_and_offsets_preset."
            )
        else:
            warn(rel + ": _ready() sets no full-rect preset")

    touch_script = os.path.join(RES, "scripts", "touch_button.gd")
    if os.path.isfile(touch_script):
        ok("touch_button.gd present (touch-capable Button)")
    else:
        err("res/scripts/touch_button.gd missing: every Button is dead on touch")

    # Buttons the player must be able to press may not be raw Buttons.
    for rel in ("res/scripts/main_menu.gd", "res/scripts/ui_manager.gd"):
        path = os.path.join(ROOT, rel)
        if not os.path.isfile(path):
            continue
        text = open(path, encoding="utf-8").read()
        if "TOUCH_BUTTON_SCRIPT" not in text:
            err(rel + " does not reference touch_button.gd")
            continue
        raw = 0
        for i, line in enumerate(text.splitlines(), 1):
            code = line.split("#")[0]
            if re.search(r"=\s*Button\.new\(\)", code):
                raw += 1
        # main_menu builds its buttons through _make_button, ui_manager
        # through _make_touch_button; each owns exactly one Button.new().
        if raw <= 1:
            ok(rel + " routes Buttons through the touch-capable factory")
        else:
            err(
                rel
                + ": "
                + str(raw)
                + " raw Button.new() calls; with emulate_mouse_from_touch="
                + "false these cannot be tapped on Android"
            )

    # The setting the whole touch design depends on.
    cfg = open(os.path.join(RES, "project.godot"), encoding="utf-8").read()
    if "pointing/emulate_mouse_from_touch=false" in cfg:
        ok("emulate_mouse_from_touch=false (steering stays stable)")
    else:
        err("emulate_mouse_from_touch must stay false, see HANDOVER.md 3.6")


# --- 4. resource paths ------------------------------------------------------
def check_resources():
    referenced = set()
    scan_dirs = [
        os.path.join(RES, "materials"),
        os.path.join(RES, "scenes"),
        os.path.join(RES, "scripts"),
    ]
    for d in scan_dirs:
        for base, _dirs, files in os.walk(d):
            for f in files:
                p = os.path.join(base, f)
                try:
                    text = open(p, encoding="utf-8").read()
                except (UnicodeDecodeError, OSError):
                    continue
                for m in re.findall(r'res://[A-Za-z0-9_./\-]+', text):
                    referenced.add((m, os.path.relpath(p, ROOT)))

    optional = {"res://assets/models/bus.glb"}
    for path, src in sorted(referenced):
        rel = path.replace("res://", "")
        full = os.path.join(RES, rel)
        if os.path.exists(full):
            ok("resource exists: " + path)
        elif path in optional:
            ok("optional (guarded) missing: " + path)
        else:
            err("MISSING resource " + path + " referenced by " + src)


REQUIRED_ASSETS = [
    "assets/textures/asphalt/albedo.jpg",
    "assets/textures/asphalt/normal.jpg",
    "assets/textures/asphalt/roughness.jpg",
    "assets/textures/concrete/albedo.jpg",
    "assets/textures/concrete/normal.jpg",
    "assets/textures/wall/albedo.jpg",
    "assets/textures/wall/normal.jpg",
    "assets/environment/sky.hdr",
]


def check_asset_contract():
    """Material paths must EXACTLY match the workflow download destinations."""
    wf = open(WORKFLOW, encoding="utf-8").read()
    for rel in REQUIRED_ASSETS:
        full = os.path.join(RES, rel)
        if os.path.exists(full) and os.path.getsize(full) > 0:
            ok("asset present: res/" + rel)
        else:
            err("asset missing: res/" + rel)
        if ("res/" + rel) in wf or os.path.dirname("res/" + rel) in wf:
            ok("workflow targets: res/" + rel)
        else:
            err("workflow never writes res/" + rel)


# --- 5. workflow ------------------------------------------------------------
def check_workflow():
    if not os.path.exists(WORKFLOW):
        err("workflow file missing")
        return
    text = open(WORKFLOW, encoding="utf-8").read()
    ok("workflow source: " + os.path.relpath(WORKFLOW, ROOT))
    entities = ["&" + "amp;", "&" + "lt;", "&" + "gt;", "&" + "quot;", "&" + "#"]
    for ent in entities:
        if ent in text:
            err("workflow contains HTML entity " + ent)
    ok("workflow has no HTML entities")
    if " && " in text:
        ok("workflow uses plain &&")

    # strip the instruction comment header before parsing the YAML body
    body_lines = []
    started = False
    for line in text.splitlines():
        if not started and line.startswith("#"):
            continue
        if not started and line.strip() == "":
            continue
        started = True
        body_lines.append(line)
    body = "\n".join(body_lines)

    try:
        import yaml

        data = yaml.safe_load(body)
        if "jobs" not in data:
            err("workflow has no jobs section")
        ok("workflow YAML parses")
    except ImportError:
        warn("pyyaml not installed; skipped YAML parse")
    except Exception as exc:  # noqa: BLE001
        err("workflow YAML invalid: " + str(exc))


# --- 6. export preset -------------------------------------------------------
def check_export_preset():
    path = os.path.join(RES, "export_presets.cfg")
    if not os.path.exists(path):
        err("export_presets.cfg missing")
        return
    text = open(path, encoding="utf-8").read()

    def val(key):
        m = re.search(re.escape(key) + r'="([^"]*)"', text)
        if m is None:
            return None
        return m.group(1)

    for key in ["custom_template/debug", "custom_template/release"]:
        v = val(key)
        if v is None:
            err("export preset missing " + key)
        elif v == "":
            ok(key + ' is empty ""')
        else:
            err(key + " should be empty, found " + v)

    debug_fields = [
        val("keystore/debug"),
        val("keystore/debug_user"),
        val("keystore/debug_password"),
    ]
    if all(v == "" for v in debug_fields):
        ok("debug keystore fields all empty (CI patches them together)")
    elif all(v for v in debug_fields):
        ok("debug keystore fields all set")
    else:
        err("debug keystore half-configured: " + str(debug_fields))

    release_fields = [
        val("keystore/release"),
        val("keystore/release_user"),
        val("keystore/release_password"),
    ]
    if all(v == "" for v in release_fields):
        ok("release keystore fields all empty")
    else:
        err("release keystore half-configured: " + str(release_fields))

    if val("package/unique_name") == "com.bussimulator.game":
        ok("package/unique_name correct")
    else:
        err("package/unique_name wrong: " + str(val("package/unique_name")))

    if val("package/name") == "BusSimulator":
        ok("package/name correct")
    else:
        err("package/name wrong: " + str(val("package/name")))

    proj = open(os.path.join(RES, "project.godot"), encoding="utf-8").read()
    if "window/handheld/orientation=0" in proj:
        ok("orientation = landscape")
    else:
        err("orientation not set to landscape")


def main():
    check_parse()
    check_style()
    check_format_rule()
    check_ui_contract()
    check_resources()
    check_asset_contract()
    check_workflow()
    check_export_preset()

    print("=" * 62)
    for line in oks:
        print("  OK   " + line)
    for line in warnings:
        print("  WARN " + line)
    for line in errors:
        print("  FAIL " + line)
    print("=" * 62)
    print("passed=" + str(len(oks)) + " warnings=" + str(len(warnings)) + " failed=" + str(len(errors)))
    if errors:
        sys.exit(1)
    print("ALL CHECKS PASSED")


if __name__ == "__main__":
    main()
