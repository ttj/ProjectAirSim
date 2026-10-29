# Architecture

Source map checked at `180002369c10a05c7b9e1ef7b71661528c1f37a7`.
This is TTJ's fork of IAMAI's Project AirSim, which builds on Microsoft's AirSim work. The common simulation libraries can run under an Unreal host or the lightweight Project AirSim Runtime; clients use network services/topics to load scenes, control robots and consume state/sensors. The fork also preserves lab-specific NanoGS rendering integration and setup helpers. Source availability is not proof that a particular engine, plugin, scene or lab machine is qualified.

## Read first

- [README.md](README.md) gives current upstream capabilities, architecture and supported-platform guidance. Its badges/releases point at IAMAI upstream; they do not report this fork's exact-head CI.
- [docs/development/use_source.md](docs/development/use_source.md) explains the simulation-library, Unreal-plugin and client build layers.
- [docs/config.md](docs/config.md), [docs/config_scene.md](docs/config_scene.md) and [docs/config_robot.md](docs/config_robot.md) define scene/robot/controller/sensor configuration.
- [docs/client_setup.md](docs/client_setup.md) and [docs/api.md](docs/api.md) describe client setup/API use; [samples/projectairsim_runtime/README.md](samples/projectairsim_runtime/README.md) defines the lighter host's limits.

## Module map

| Area | Responsibility and useful seam |
| --- | --- |
| [CMakeLists.txt](CMakeLists.txt), [build.sh](build.sh), [build.cmd](build.cmd) | Build orchestration and dependencies. The root CMake project adds core simulation, server, physics, rendering, tools, vehicle APIs and samples; it is distinct from Unreal's build system. |
| [core_sim/](core_sim) | Common simulation objects and lifecycle. `Simulator` in [simulator.hpp](core_sim/include/core_sim/simulator.hpp) exposes simulator/scene load, start, stop and service registration. |
| [simserver/](simserver) | `SimServer` hosts the simulator and client-facing communication; [simserver.hpp](simserver/include/simserver.hpp) is the public seam. |
| [physics/](physics), [vehicle_apis/](vehicle_apis), [mavlinkcom/](mavlinkcom), [rendering/](rendering) | Physics backends, controller/vehicle integrations, MAVLink support and rendering interfaces used by the common framework. Configuration selects the relevant implementations. |
| [unreal/Blocks/](unreal/Blocks) | Unreal example environment and plugins. The [ProjectAirSim plugin](unreal/Blocks/Plugins/ProjectAirSim) adapts robots, sensors and host interactions to Unreal and links built simulation libraries. |
| [samples/projectairsim_runtime/](samples/projectairsim_runtime) | `main.cpp` and `ground_collision_host.cpp` provide an engine-independent server host with limited flat-ground collision handling. It does not supply Unreal-rendered sensors or general scene-mesh collisions. |
| [client/python/projectairsim/](client/python/projectairsim) | Python package metadata and `src/projectairsim`. `ProjectAirSimClient` owns transport; `World` loads/configures scenes; `Drone` and related classes expose robot APIs. [client/cpp/](client/cpp) holds the separate C++ client and related bridge support. |
| [client/python/example_user_scripts/](client/python/example_user_scripts) | Existing client demos and simulation configurations. They are applications that connect to a running host, not source-only tests. |
| [unreal/Blocks/Plugins/NanoGS/](unreal/Blocks/Plugins/NanoGS) | Lab Gaussian-splat plugin source/shaders. `NanoGSLabProbe.cpp` adds `NanoGS.SpawnLab` and delayed screenshot/exit console probes. The [dated review findings](unreal/Blocks/Plugins/NanoGS/REVIEW-FINDINGS-2026-09-16.md) record unresolved renderer issues. |
| [tools/vu/](tools/vu) | Lab-specific `ue_build.sh` and `isaac_compatlibs.sh` preserve re-derived setup knowledge. They are active build/download helpers, not qualification receipts or exact recovered operator commands. |

## Data and dependency flow

A simulation host starts `SimServer` and the common `Simulator`. Scene JSONC identifies robots and their configurations; those select physics, controllers, actuators and sensors. The host supplies engine-dependent rendering/collision integration. Client calls travel through service requests; state and sensor data return on topics. In the Python client, `ProjectAirSimClient.connect()` opens separate `pynng` topic/service sockets (defaults `8989`/`8990`); subscriptions start a receive thread. `World` resolves scene/robot configurations and sends load requests, while `Drone` addresses robot services/topics.

Scene positions and many vehicle APIs use SI metres in NED (`x` north, `y` east, `z` down); scene `rpy` is in radians. Unreal host coordinates and lab ENU data require their established conversion boundaries. The lab's existing [trace_to_adk_csv.py](https://github.com/ttj/vu-autonomy/blob/main/scripts/trace_to_adk_csv.py) exports the canonical NED trajectory through `surrogate.trace.write_ned_trajectory_csv`; [adk_replay.py](https://github.com/ttj/vu-autonomy/blob/main/scripts/adk_replay.py) imports/replays it through the client. Reuse those adapters instead of creating another axis/heading conversion or replay controller. Replayed poses and rendered images are simulation evidence, not measured onboard estimates.

The Unreal path additionally depends on an appropriate engine checkout/toolchain, the built simulation libraries and content/plugin assets. NanoGS adds a separate rendering path and GPU resource/shader requirements; having its source or successfully importing a Python client does not prove that path renders correctly. Runtime shares server/physics/controller APIs but deliberately lacks cameras, LiDAR, radar and general mesh collision support described in its README.

## Setup and entrypoints

Choose the host before setup. Follow the existing source/client guides for the selected supported platform and use the Python package's [pyproject.toml](client/python/projectairsim/pyproject.toml) for its actual dependency/extra definitions. A client installation does not build simulation libraries or Unreal plugins. Source builds use the existing `build.sh` / `build.cmd` targets; `simlibs_debug` and `simlibs_release` are documented library/runtime build entrypoints. Read the target descriptions before execution: `all` includes clean/build/test/package operations.

For the engine-independent path, the Runtime README gives the built executable location and `projectairsim_runtime_demo.py` entrypoint. For Unreal, use the existing source/prebuilt environment instructions and matching client example/configuration. These start simulation and may compile/download substantial dependencies; they were not run for this documentation change.

The repository has existing GitHub workflows under [.github/workflows/](.github/workflows). Their path/label gates matter: the root architecture file is not in the current docs workflow's path list, and the self-hosted workflow requires `run-self-hosted`. The Sphinx workflow removes its two generated `build` directories before rebuilding. Read its commands before dispatching it under any preservation constraint; a docs build is separate from simulator/Unreal/render validation, and successful job status alone does not establish that every autodoc import rendered successfully.

## Traps and change boundaries

- Keep upstream, this TTJ fork, programme mirrors and prebuilt containers distinct. The lab's [external-project catalogue](https://github.com/ttj/vu-autonomy/blob/main/config/external_projects.json) names the fork/local checkout; a badge or another checkout's build result does not establish this source's state.
- Runtime's compatible API does not make it a photoreal camera or obstacle-mesh substitute. Select evidence claims according to the host and actual sensor path.
- Python object construction is not uniformly passive. `World` can load a scene and imports a null trajectory during initialization; examples can arm/fly simulated vehicles. Inspect examples before using them as a smoke test.
- Native libraries and Unreal modules are different build products. `tools/vu/ue_build.sh` records separate plugin/shared-library, headless display and ShaderCompileWorker prerequisites. Its comments are dated findings, not current host checks.
- `tools/vu/isaac_compatlibs.sh` is an Isaac-specific compatibility helper stored here; it downloads/unpacks libraries and creates output. It is not a Project AirSim dependency installer or a harmless environment probe.
- NanoGS's dated findings remain a separate renderer review queue. The lab probes can spawn actors, capture screenshots and exit the host. Neither this guide nor a docs build resolves or requalifies those findings.
- Existing maps, engine trees, service configuration and flight kits have separate ownership. This document adds no engine installation, renderer change, provider pin or deployment step.

Index searched: lab CODE_MAP/CODE_INDEX and external-project declarations; safe sibling README/docs and canonical trajectory/replay adapters; target README/build/config/client/core/server/runtime/Unreal/NanoGS/tools/workflows and all-state architecture PR/issue search.

Reusing: `Simulator`, `SimServer`, existing client `ProjectAirSimClient` / `World` / `Drone`, Runtime and Unreal hosts, lab NanoGS/tools helpers and canonical `vu-autonomy` trace/replay adapters. New because: this safe TTJ fork lacked a root architecture onboarding guide; existing implementation and documentation remain unchanged.
