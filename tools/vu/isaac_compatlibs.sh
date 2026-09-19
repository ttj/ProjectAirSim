#!/usr/bin/env bash
# Build the PRIVATE compat-lib directory Isaac Sim needs on Ubuntu 26.04, without touching the host.
#
# RE-DERIVED, NOT RESTORED. The originals (`compatlib.sh`, `compatlib2.sh`) were deleted on
# 2026-09-19 by an unscoped `rm -f ~/*.sh`. Rebuilt from the recorded findings.
#
# THE SYMPTOM LIES. Isaac Sim on 26.04 fails with:
#
#     omni.kit.asset_converter has no attribute 'get_instance'
#
# which reads exactly like an API rename between Isaac Sim versions. It is not. The extension's
# NATIVE BINDINGS fail to load, so the Python module imports SUCCESSFULLY and exports NOTHING --
# `dir()` returns [], so every attribute is missing and the first one you touch is the one named in
# the error. Check `dir(omni.kit.asset_converter)` before believing any "no attribute" message from
# an extension with native bindings.
#
# ROOT CAUSE: libxml2.so.2 is absent. Ubuntu 26.04 renamed the package to libxml2-16 and ships only
# .so.16. THE ABIs DIFFER, so symlinking .so.16 to .so.2 is a lie that will fail somewhere worse and
# later. The fix is a private directory of the OLD noble libraries, put on LD_LIBRARY_PATH for Isaac
# Sim ONLY -- the host's own libxml2 stays untouched.
set -euo pipefail

COMPAT="${COMPAT:-$HOME/opt/compat-libs}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# noble packages, fetched as .deb and unpacked -- NOT installed, so nothing on the host changes.
PKGS=(
  "http://archive.ubuntu.com/ubuntu/pool/main/libx/libxml2/libxml2_2.9.14+dfsg-1.3ubuntu3_amd64.deb"
  "http://archive.ubuntu.com/ubuntu/pool/main/i/icu/libicu74_74.2-1ubuntu3_amd64.deb"
)

echo "=== building $COMPAT (private; the host's libxml2 is NOT touched) ==="
mkdir -p "$COMPAT"
for url in "${PKGS[@]}"; do
  f="$WORK/$(basename "$url")"
  echo "  fetching $(basename "$url")"
  curl -fsSL -o "$f" "$url"
  dpkg-deb -x "$f" "$WORK/x"
done
find "$WORK/x" -name 'lib*.so.*' -exec cp -av {} "$COMPAT/" \; | sed 's/^/    /'

echo
echo "=== what landed ==="
ls -1 "$COMPAT" | sed 's/^/  /'
echo
cat <<NOTE
Use it for Isaac Sim ONLY:

    LD_LIBRARY_PATH="$COMPAT:\$LD_LIBRARY_PATH" ./isaac-sim.sh     # or your launcher

VERIFY IT WORKED BY LISTING THE MODULE, not by the absence of an error:

    python -c "import omni.kit.asset_converter as a; print(len(dir(a)))"

An empty dir() means the native bindings still did not load and you are about to misread the next
"no attribute" as an API change.

RELATED, same box, different trap: Isaac ROS 4.6 targets Ubuntu 24.04 noble + ROS 2 Jazzy, so on
26.04 it is a CONTAINER (isaac-ros:4.6-jazzy on nvcr.io/nvidia/cuda:12.6.2-devel-ubuntu24.04). Its
nodes need libnvvpi4 / vpi4-dev, which are in NEITHER the CUDA repo NOR the Isaac ROS CDN -- apt
says only "Depends: libnvvpi4 but it is not installable" and hints nothing. They ship from the
JETSON repo, which despite the name publishes an x86_64/noble tree:

    deb https://repo.download.nvidia.com/jetson/x86_64/noble r38.4 main   # key jetson-ota-public.asc

Cross-distro DDS interop was TESTED and works: a Jazzy container on --network host publishing
std_msgs/String is received by the host's Lyrical \`ros2 topic echo\`. Caveat: Isaac-specific
interface types are not on the host, so nodes consuming those run in the container, or the host
needs the matching interface packages.
NOTE
