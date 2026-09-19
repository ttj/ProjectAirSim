# VU runners — re-derived after a deletion, 2026-09-19

On 2026-09-19 an unscoped `rm -f ~/*.sh` on `verivital-a51` deleted sixteen scratch scripts left
loose in that home directory:

    compatlib.sh  compatlib2.sh  gz_try.sh  gz_try2.sh  interop.sh  isaac_render.sh
    isaac_verify.sh  run_splats.sh  ue_batch.sh  ue_blocks.sh  ue_build.sh  ue_mesh_run.sh
    ue_mesh_run3.sh  ue_more.sh  ue_probe.sh  ue_scw.sh

ext4, no snapshots, nothing in Trash, no copy in any repo: **unrecoverable.** They are re-derived
here from the recorded findings, which survived. **These are equivalents, not restorations** — the
knowledge is faithful, the exact command lines are not.

They live in a repo this time rather than loose in `$HOME`, which is the actual fix.

## What is here

| script | replaces | why it was worth rebuilding |
|---|---|---|
| `ue_build.sh` | `ue_build.sh`, `ue_scw.sh`, `ue_probe.sh` | Standing Unreal up is **four** builds, each invisible until the previous is fixed. That ordering is the whole value. |
| `isaac_compatlibs.sh` | `compatlib.sh`, `compatlib2.sh`, part of `isaac_verify.sh` | The Isaac Sim failure **lies about itself** — a missing `libxml2.so.2` presents as a Python API rename. |

## What was deliberately NOT rebuilt, and why

- **`gz_try.sh`, `gz_try2.sh`** — the Gazebo mesh/texture findings (FBX needs
  `GZ_MESH_FORCE_ASSIMP=1`; gz cannot read DDS and does not sniff magic bytes; Ogre2 multiplies a
  diffuse map by `Kd`, so `Kd 0 0 0` renders black with textures correctly loaded) are already
  **encoded in `vu_attack/render/engines/gz_model.py`**. The scripts were exploration; the
  conclusions shipped. Nothing to recover.
- **`run_splats.sh`, `ue_mesh_run*.sh`, `ue_batch.sh`, `ue_blocks.sh`, `ue_more.sh`** — thin
  wrappers over `scripts/unreal_render.sh` and `unreal_nanogs.py`, which are in the repo and are
  what you should call directly. Hand-rolling a launch is how `-RenderOffScreen` got replaced with
  a bogus `-nullrhi=0` once. The non-obvious part is the environment, and that is documented in
  `ue_build.sh`'s closing notes (the EV 5–7 exposure band, `VU_MESH_EMISSIVE`, the defective splat
  path).
- **`interop.sh`** — one `ros2 topic echo` across a container boundary. The result (cross-distro
  Jazzy→Lyrical DDS interop works, with a caveat about Isaac-specific interface types) is recorded
  in `isaac_compatlibs.sh`.
- **`isaac_render.sh`** — not enough survives to rebuild it honestly. Left out rather than guessed
  at; a plausible-looking script that was never run is worse than no script.
