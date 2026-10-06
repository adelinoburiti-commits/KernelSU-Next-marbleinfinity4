#!/usr/bin/env bash
set -euo pipefail

python3 - config/managers.json "${GITHUB_OUTPUT:-}" <<'PY'
import json
import os
import sys

config_path = sys.argv[1]
github_output = sys.argv[2]

with open(config_path, encoding="utf-8") as fh:
    managers = json.load(fh)

build_all = os.environ.get("BUILD_ALL", "false") == "true"
all_sources = os.environ.get("ALL_SOURCES", "false") == "true"
enable_susfs_override = os.environ.get("ENABLE_SUSFS", "")
kernel_source_input = os.environ.get("KERNEL_SOURCE_INPUT", "") or "aosp-pablo"
source_ref_input = os.environ.get("SOURCE_REF_INPUT", "")

SHORT = {"aosp-pablo": "aosp", "clo-marble": "clo"}

if all_sources and source_ref_input:
    print("::error::Leave 'source_ref' empty when building both sources (it would apply to both).", file=sys.stderr)
    sys.exit(1)

sources = ["aosp-pablo", "clo-marble"] if all_sources else [kernel_source_input]

selected = [
    ("kernelsu", os.environ.get("BUILD_KERNELSU", "false")),
    ("kernelsu-next", os.environ.get("BUILD_KERNELSU_NEXT", "false")),
]

include = []

for source in sources:
    for manager, wanted in selected:
        if not build_all and wanted != "true":
            continue
        meta = managers[manager]
        susfs = meta.get("susfs")
        manager_susfs = bool(susfs) and susfs is not False
        if enable_susfs_override == "false":
            manager_susfs = False
        label = f"{SHORT.get(source, source)}-{manager}"
        if manager_susfs:
            label += "-susfs"
        include.append(
            {
                "source": source,
                "manager": manager,
                "enable_susfs": "true" if manager_susfs else "false",
                "label": label,
            }
        )

if not include:
    print("::error::No managers selected. Enable at least one build_* checkbox.", file=sys.stderr)
    sys.exit(1)

if all_sources and len({i["manager"] for i in include}) < 2:
    print("::warning::Combined zip needs both KernelSU and KernelSU-Next; tick both (or build_all).", file=sys.stderr)

matrix = json.dumps({"include": include}, separators=(",", ":"))
if github_output and github_output != "/dev/null":
    with open(github_output, "a", encoding="utf-8") as fh:
        fh.write(f"matrix={matrix}\n")
print(matrix)
PY
