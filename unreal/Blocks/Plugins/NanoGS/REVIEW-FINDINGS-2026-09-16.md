# NanoGS plugin — review findings, 2026-09-16

Twelve findings raised against this plugin the moment its source entered version control
(ttj/ProjectAirSim#1). **None of them were introduced by that commit** — the code had been
running untracked on one machine, so nothing had ever reviewed it. They are recorded here
rather than as issues because this repository has issues disabled, and here they version with
the code they describe.

## Status: OPEN, and deliberately not fixed yet

The plugin WORKS — it is what renders the lab splat in Unreal today. Nothing here was changed,
because at the time of writing neither machine could verify a fix:

- `lh-lambda-quad`'s GPU is dead (driver 580.178.04 installed against a running 580.173.02)
- `verivital-a51` had Unreal cloned and `Setup.sh` complete, but not yet built

Editing a GPU renderer that cannot be compiled or run would risk the working code this commit
exists to protect. **Fix these once the A51 can build and run the plugin, and verify each one
against an actual render.**

## The two P1s are both buffer overruns, and both are conditional

Neither fires in the ordinary path. The first needs an asset with more splats than
`gs.MaxRenderBudget`; the second needs `gs.DebugForceLODLevel >= 0` set at the same time as a
budget. That is probably why the lab has not hit them — but both can cause GPU corruption or
device loss, so the conditions are worth knowing before someone raises the budget or reaches
for the debug override.

---

### P1 — NanoGS/Private/NanoGS.cpp:581

**Clamp the last fallback dispatch to the render budget**

When `gs.MaxRenderBudget` ends partway through a proxy, the offset check admits that proxy and `DispatchCalcViewDataGlobal` still dispatches its full splat count. `ResizeIfNeeded` has allocated the global buffers only up to the budget, while the non-compaction shader is given `MaxRenderBudget = 0`, so the boundary proxy writes past `GlobalViewDataBuffer`; this affects the default non-Nanite path whenever an asset contains more splats than the configured budget and can cause GPU corruption or device loss. Clamp the dispatched count for the boundary proxy or enforce the budget inside this shader path.

Useful? React with 👍 / 👎.

### P1 — NanoGS/Private/NanoGS.cpp:315

**Disable the allocation cap when forced LOD overrides the budget**

When both `gs.MaxRenderBudget > 0` and `gs.DebugForceLODLevel >= 0`, this clears only the local budget value, but `FGaussianGlobalAccumulator::ResizeIfNeeded` independently rereads `gs.MaxRenderBudget` and still allocates capped buffers. The subsequent compaction prefix sum, view-data shader, sort, and draw all receive an unlimited budget and can therefore address beyond those buffers. The debug override must also be passed through to allocation rather than letting allocation and dispatch use different limits.

Useful? React with 👍 / 👎.

### P2 — NanoGSEditor/Private/GaussianSplatAssetFactory.cpp:180

**Invalidate shared render data after reimporting**

When an already-rendered non-Nanite asset is reimported, this overwrites its bulk data but leaves `Asset->RenderData` and all existing scene proxies untouched. `GetOrCreateRenderData` consequently keeps returning the previously initialized buffers, so placed actors continue rendering the old splats even though the asset and package now contain the new data. Unlike the Nanite build/clear paths, this path never resets `RenderData` or broadcasts `OnAssetChanged`; it should do both after successful initialization.

Useful? React with 👍 / 👎.

### P2 — NanoGS/Private/GaussianSplatAsset.cpp:228

**Include Gaussian extents in primitive bounds**

These bounds include only splat centers and ignore each Gaussian's scale and rotation. A large splat whose center is outside the view can still cover visible pixels, but both Unreal's primitive culling and the explicit proxy-frustum test use this undersized box, causing splats near view or streaming boundaries to disappear and pop. Expand the bounds by each splat's transformed covariance/scale extent rather than adding only its position.

Useful? React with 👍 / 👎.

### P2 — NanoGS/Private/PLYFileReader.cpp:450

**Decode each accepted PLY scalar type correctly**

The header parser accepts `double`, `uchar`, `int`, and `short` properties and advances offsets using their actual sizes, but this accessor always interprets every accepted property as a 32-bit float. A valid binary-little-endian PLY that uses any of those declared types for a consumed field is therefore imported with corrupted positions, scales, rotations, or colors; for one- and two-byte fields the read also spans adjacent properties. Preserve the property's declared type and convert it here, or reject non-float fields during header parsing.

Useful? React with 👍 / 👎.

### P2 — NanoGS/Public/GaussianDataTypes.h:436

**Preserve positions beyond the half-float range**

Every imported position is unconditionally repacked into float16 centimeters for GPU rendering, whose documented range here is only about ±655 meters. Assets with coordinates outside that range—such as a splat scene located one kilometer from its local origin—overflow or saturate during packing, producing invalid or displaced splats even though the asset stores the original positions as float32. Rebase positions to a per-asset or per-chunk origin, or retain sufficient precision for large-coordinate scenes.

Useful? React with 👍 / 👎.

### P2 — NanoGS/Private/NanoGS.cpp:223

**Honor the frustum-culling toggle**

Even when a component sets `bEnableFrustumCulling` to false, every proxy is still unconditionally rejected by this frustum test; the value copied into `FGaussianSplatSceneProxy` is never consulted anywhere. Thus disabling the exposed option has no effect, including for debugging conservative bounds or intentionally rendering off-center Gaussian tails. Gate this test—and the cluster-level frustum test where applicable—on the component setting.

Useful? React with 👍 / 👎.

### P2 — NanoGS/Public/GaussianSplatComponent.h:66

**Apply the configured sort cadence**

`SortEveryNthFrame` is exposed as a performance control, but it is never read after declaration. Whenever the camera changes, the global path recalculates and radix-sorts every frame regardless of values from 2 through 10, so users receive none of the advertised GPU-cost reduction. Feed this setting into the sort-cache invalidation cadence or remove the nonfunctional option.

Useful? React with 👍 / 👎.

### P2 — NanoGS/Private/GaussianSplatAsset.cpp:746

**Preserve original splats when disabling Nanite**

If the source PLY has moved or is unavailable, this path explicitly keeps the unified buffer containing both original and generated LOD splats, but execution then clears the hierarchy and disables Nanite below. The non-Nanite renderer consequently treats every appended LOD representation as an ordinary splat and draws it together with its originals, producing duplicate geometry, excessive opacity, and inflated work. Abort the disable operation when restoration fails, or persist enough information to truncate/rebuild the original-only buffers without the source file.

Useful? React with 👍 / 👎.

### P2 — NanoGS/Private/GaussianSplatComponent.cpp:35

**Rebind asset delegates after editor assignment**

Changing `SplatAsset` in the Details panel assigns the new pointer before this callback, but this branch only recreates rendering and never removes the delegate from the old asset or subscribes to the new one. The still-valid old delegate handle also prevents later subscription attempts, so Nanite builds or other broadcasts from the newly assigned asset no longer refresh this component. Track the subscribed asset and explicitly unsubscribe/re-subscribe when this property changes.

Useful? React with 👍 / 👎.

### P2 — NanoGS/Private/GaussianSplatComponent.cpp:13

**Disable the empty component tick**

Every Gaussian splat component is registered for a game-thread tick each frame, but `TickComponent` performs no work beyond calling `Super`. Scenes composed of many splat tiles therefore pay avoidable tick-registration and dispatch overhead for every tile on every frame. Leave ticking disabled until the component has actual per-frame game-thread work.

Useful? React with 👍 / 👎.

### P2 — NanoGS/Private/NanoGS.cpp:628

**Restrict debug clearing to the current view**

With cluster debug mode enabled, `EClear` is used as the load action for the shared scene-color attachment. Render-target load clears apply to the whole attachment rather than the current viewport, so in split-screen, stereo, or other multi-view families each later view erases scene color already rendered for earlier views outside its viewport. Preserve `ELoad` and draw the debug background only over the current `ViewRect`.

Useful? React with 👍 / 👎.


---

*Raised by the Codex reviewer on ttj/ProjectAirSim#1 and transcribed verbatim. Line numbers are
as of commit `3e169d6a`, the commit that first tracked this source.*
