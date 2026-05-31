#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VM_DIR="$ROOT"
VERSION="$(awk -F': ' '/^Version:/ {print $2; exit}' "$ROOT/control")"
OUT="$ROOT/release/v$VERSION"

rm -rf "$OUT"
mkdir -p "$OUT"

derive_vm_debs() {
  local packages_dir="$1"

  python3 - "$packages_dir" <<'PY'
import os
import re
import shutil
import subprocess
import sys

packages_dir = os.path.abspath(sys.argv[1])

def write_ar(output_path, members):
    if os.path.exists(output_path):
        os.remove(output_path)
    with open(output_path, "wb") as f:
        f.write(b"!<arch>\n")
        for archive_name, src_path in members:
            with open(src_path, "rb") as member_file:
                data = member_file.read()
            name_bytes = archive_name.encode("ascii")
            if len(name_bytes) > 15:
                raise ValueError(f"Archive member name too long: {archive_name}")
            header = name_bytes + b"/" + (b" " * (15 - len(name_bytes)))
            header += b"0".ljust(12)
            header += b"0".ljust(6)
            header += b"0".ljust(6)
            header += b"100644".ljust(8)
            header += str(len(data)).encode("ascii").ljust(10)
            header += b"`\n"
            f.write(header)
            f.write(data)
            if len(data) % 2 != 0:
                f.write(b"\n")

def pack_tar_gz(src_dir, out_path):
    if os.path.exists(out_path):
        os.remove(out_path)
    subprocess.check_call(["tar", "-czf", out_path, "-C", src_dir, "."])

def derive_variant(rootful_deb, arch, output_name):
    temp_dir = os.path.join(packages_dir, "_release_repack")
    if os.path.exists(temp_dir):
        shutil.rmtree(temp_dir)
    os.makedirs(temp_dir)

    try:
        subprocess.check_call(["ar", "x", rootful_deb], cwd=temp_dir)

        debian_binary = os.path.join(temp_dir, "debian-binary")
        control_tar = next(
            os.path.join(temp_dir, name)
            for name in os.listdir(temp_dir)
            if name.startswith("control.tar")
        )
        data_tar = next(
            os.path.join(temp_dir, name)
            for name in os.listdir(temp_dir)
            if name.startswith("data.tar")
        )

        control_dir = os.path.join(temp_dir, "control")
        data_dir = os.path.join(temp_dir, "data")
        os.makedirs(control_dir)
        os.makedirs(data_dir)

        subprocess.check_call(["tar", "-xf", control_tar, "-C", control_dir])
        subprocess.check_call(["tar", "-xf", data_tar, "-C", data_dir])

        control_file = os.path.join(control_dir, "control")
        with open(control_file, "r", encoding="utf-8") as f:
            control = f.read()
        control = re.sub(r"Architecture:\s*\S+", f"Architecture: {arch}", control)
        with open(control_file, "w", encoding="utf-8") as f:
            f.write(control)

        old_app_dir = os.path.join(data_dir, "Applications")
        if os.path.exists(old_app_dir):
            new_app_dir = os.path.join(data_dir, "var", "jb", "Applications")
            os.makedirs(os.path.dirname(new_app_dir), exist_ok=True)
            if os.path.exists(new_app_dir):
                shutil.rmtree(new_app_dir)
            shutil.move(old_app_dir, new_app_dir)

        new_control_tar = os.path.join(temp_dir, "control.tar.gz")
        new_data_tar = os.path.join(temp_dir, "data.tar.gz")
        pack_tar_gz(control_dir, new_control_tar)
        pack_tar_gz(data_dir, new_data_tar)

        output_path = os.path.join(packages_dir, output_name)
        write_ar(output_path, [
            ("debian-binary", debian_binary),
            ("control.tar.gz", new_control_tar),
            ("data.tar.gz", new_data_tar),
        ])
        print(f"[+] Generated {output_name}")
    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)

rootful_candidates = [
    os.path.join(packages_dir, name)
    for name in os.listdir(packages_dir)
    if name.endswith(".deb")
    and name.startswith("com.vanson.modifier_")
    and "rootless" not in name
    and "roothide" not in name
]
if not rootful_candidates:
    raise SystemExit("No rootful VM deb found")

rootful_deb = sorted(rootful_candidates)[0]
rootful_name = os.path.basename(rootful_deb)

if "iphoneos-arm64" in rootful_name:
    roothide_name = rootful_name.replace("iphoneos-arm64", "iphoneos-arm64-roothide")
elif "iphoneos-arm" in rootful_name:
    roothide_name = rootful_name.replace("iphoneos-arm", "iphoneos-arm64-roothide")
else:
    roothide_name = rootful_name.replace(".deb", "_iphoneos-arm64-roothide.deb")

rootless_name = rootful_name.replace(".deb", "-rootless.deb")

derive_variant(rootful_deb, "iphoneos-arm64e", roothide_name)
derive_variant(rootful_deb, "iphoneos-arm64", rootless_name)
PY
}

build_vm() {
  echo "==> Building VM rootful, rootless, roothide, and tipa"
  rm -rf "$VM_DIR/packages"
  make -C "$VM_DIR" clean package FINALPACKAGE=1 DEBUG=0
  derive_vm_debs "$VM_DIR/packages"
  find "$VM_DIR/packages" -maxdepth 1 -type f \( -name '*.deb' -o -name '*.tipa' \) -exec cp {} "$OUT/" \;
}

build_vm

if [ -d "$VM_DIR/.theos/obj" ]; then
  find "$VM_DIR/.theos/obj" -name 'VansonMod.app' -type d -maxdepth 4 -print -quit
fi

echo "Artifacts:"
find "$OUT" -maxdepth 1 -type f -print | sort
echo "Release artifacts written to $OUT"
