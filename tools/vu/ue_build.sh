#!/usr/bin/env bash
# Stand Unreal + the ProjectAirSim Blocks project up on a fresh box, in the order that works.
#
# RE-DERIVED, NOT RESTORED. The original `ue_build.sh` on verivital-a51 was deleted on 2026-09-19 by
# an unscoped `rm -f ~/*.sh`. This is rebuilt from the recorded findings, not recovered, so treat it
# as a checklist that encodes what went wrong rather than as the exact command line that once ran.
#
# WHY IT IS FOUR BUILDS. A built ENGINE is not a provisioned box. The engine tree can be 189 GB with
# a working `UnrealEditor` binary and still render nothing, four times, for four different reasons --
# and each one only surfaces once the previous is fixed, so budget four rounds:
#
#   1. editor exits immediately          Blocks' plugin modules were never compiled:
#                                        "Plugin 'ProjectAirSim' failed to load because module
#                                        'ProjectAirSim' could not be found" -> error code 1.
#   2. that build fails with RulesError  Plugins/ProjectAirSim/SimLibs/shared_libs is ABSENT. The
#                                        plugin's Build.cs calls Directory.GetFiles() on it at
#                                        rules-evaluation time. ~416 MB of native libs -- rsync them
#                                        from a box that has them; rebuilding is slower.
#   3. SDL: No available video device    -RenderOffScreen omitted. On a headless box the editor
#                                        tries to open a window and dies in
#                                        FLinuxApplication::CreateLinuxApplication -- BEFORE any
#                                        -ExecCmds script runs, so it looks like your script failed.
#   4. Couldn't launch ShaderCompileWorker
#                                        It is a SEPARATE TARGET. `make UnrealEditor` does not build
#                                        it.
#
# None of the four is visible from `du -sh UnrealEngine`.
#
# Usage:  ue_build.sh [--engine DIR] [--project UPROJECT] [--libs-from HOST:PATH]
set -euo pipefail

ENGINE="${ENGINE:-$HOME/ansr-final/UnrealEngine}"
PROJECT="${PROJECT:-$HOME/ansr-final/ProjectAirSim-ttj/unreal/Blocks/Blocks.uproject}"
LIBS_FROM="${LIBS_FROM:-}"          # e.g. verivital@lh-lambda-quad:~/.../SimLibs/shared_libs

while [ $# -gt 0 ]; do
  case "$1" in
    --engine)    ENGINE="$2"; shift 2 ;;
    --project)   PROJECT="$2"; shift 2 ;;
    --libs-from) LIBS_FROM="$2"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

BUILD="$ENGINE/Engine/Build/BatchFiles/Linux/Build.sh"
PLUGIN_LIBS="$(dirname "$PROJECT")/Plugins/ProjectAirSim/SimLibs/shared_libs"

say() { printf '\n=== %s\n' "$*"; }

say "0. preflight"
[ -x "$BUILD" ] || { echo "no Build.sh at $BUILD -- is the engine built?" >&2; exit 1; }
[ -f "$PROJECT" ] || { echo "no uproject at $PROJECT" >&2; exit 1; }
echo "  engine : $ENGINE"
echo "  project: $PROJECT"

# STEP 2 BEFORE STEP 1, deliberately: the shared libs must exist before the Blocks build is even
# PARSED, because Build.cs enumerates that directory at rules-evaluation time. Building first just
# produces a RulesError that names nothing useful.
say "1. plugin shared_libs (Build.cs reads this directory at rules time)"
if [ -d "$PLUGIN_LIBS" ] && [ -n "$(ls -A "$PLUGIN_LIBS" 2>/dev/null)" ]; then
  echo "  present: $(du -sh "$PLUGIN_LIBS" | cut -f1)"
elif [ -n "$LIBS_FROM" ]; then
  echo "  absent -- rsyncing from $LIBS_FROM (~416 MB)"
  mkdir -p "$PLUGIN_LIBS"
  rsync -a --info=progress2 "$LIBS_FROM/" "$PLUGIN_LIBS/"
else
  echo "  !! ABSENT and no --libs-from given." >&2
  echo "     The Blocks build will fail with a RulesError that does NOT name this directory." >&2
  echo "     Copy ~416 MB from a box that has them, or rebuild the plugin's native libs." >&2
  exit 1
fi

say "2. BlocksEditor (the plugin modules the editor loads)"
"$BUILD" BlocksEditor Linux Development -Project="$PROJECT"

say "3. ShaderCompileWorker (a SEPARATE target; make UnrealEditor does not build it)"
"$BUILD" ShaderCompileWorker Linux Development

say "4. done -- now render with the repo's own launcher, NOT a hand-rolled command line"
cat <<'NOTE'
  Use scripts/unreal_render.sh (or unreal_nanogs.py). It already passes -RenderOffScreen, which is
  what stops "SDL: No available video device" on a headless box. A hand-rolled launch is how a
  bogus -nullrhi=0 got substituted for it once.

  And when it renders, the pictures can still be wrong:
    * exposure bias band is EV 5-7 (MEASURED). unreal_nanogs.py defaults to +10, which blows the
      mesh to a white silhouette. EV 8 clips 9.9%, EV 9 clips 41%, EV <= 0 is black.
      Sweep with VU_BIAS_SWEEP -- a boot costs ~10 min, so one guess per boot is the expensive way.
    * adding lights does NOTHING by design: the material is EMISSIVE (VU_MESH_EMISSIVE=0.25).
      Proven before the flag was found -- key 10->40 lux and bias 1.0->2.0 gave BYTE-IDENTICAL PNGs.
      Identical output from inputs that differ is never a coincidence.
    * the SPLAT path is the defective one (VU_VISUAL_MESH unset). The mesh path works.
NOTE
