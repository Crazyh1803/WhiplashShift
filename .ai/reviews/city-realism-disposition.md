# City realism review disposition

Asset review: 20261030-155448-codex.md, APPROVE with four MED findings. Glyph-only emissive validation fixed in socket handoff. Remaining tangent, arcade hull and effective emission corrections delegated as city-realism-review-fixes; validate again on integration.

Runtime review rounds: 20261030-160046-claude.md CHANGES_REQUESTED, then 20261030-160252-claude.md APPROVE. HIGH missing actor resource guard fixed: production validates ResourceLoader, PackedScene cast and finite sockets, frees partial pairs and skips unavailable actors. QA asserts geometry and actor budgets; independent full-route regression follows. Incremental rendering_groups and cached route sample positions replace rebuilding every placement for every candidate. Capture directories are created only with --capture. Public static material preparation keeps source resources private. Invalid light direction falls back to a finite default.

Second-round MED on zero near-end margin is stale: city_realism.gd sets SELF fade and visibility_range_end_margin=10 for both LODs, begin margin10 for the far LOD. Paired chunks have the same origin and custom AABB. Runtime centre distances are near140+10, far140-10 through450+10, exactly the conservative150/130/460 window used by layout. The QA uses these same inclusive limits. Independent tests must verify those properties, overlap costs and paired bounds. No third review round requested.

Second-round LOW load diagnostic and curb cache guard fixed in 094ec48. Remaining LOW group cloning is retained: it copies only per-chunk aggregate statistics, not mesh data or full placement arrays, and avoids corrupting accepted groups on a rejected candidate. Review artifacts are intentionally retained as project audit records, following AGENTS.md review requirements; generated scratch files will be removed.


Canonical tangent correction completed through the asset lead: increasing exported V, unmirrored unit-quad w=-1 and mirrored w=+1, independently derived gradient sign checked. All 24 runtime GLBs patched with unchanged positions/UVs/colours/triangles, and the idempotent second patch changed zero bytes. The 11 source tests pass; no third asset review round was requested for that correction.

Independent city test review 20261030-162522-codex.md APPROVE requested actual merged-vertex comparisons and bounded QA children. Delegated follow-up implements per-material bidirectional world-space vertex comparison and a Python timeout/kill/reap helper with a hung-child self-test. Review round2 20261030-163242-codex.md APPROVE requested including the MultiMesh instance transform and rejecting script errors in healthy QA. Root applied those exact small fixes, with an additional deliberately displaced-instance detector. All HIGH are fixed; final integrated verification follows the geometry-only import change.

Fresh-scene imports revealed external PNG dependency reimports despite GLB handling0. The durable asset fix uses the already-approved texture-free/named-library option, with textured sources retained outside Godot, instead of relying on repeated cache cleanup. Technical diagnosis is 20261030-163055-debug-claude.md.


Final binding review 20261030-163824-codex.md APPROVE identified lost vertex-colour multiplication in the Blender preview rebind path. Asset lead fixed it and exercised a fresh row-workshop build plus headless imported material topology (actual Color layer). Review 20261030-164400-codex.md APPROVE has no findings. Runtime game materials are unchanged by this source-preview fix.

Integrated verification completed: 17 city-family and13 benchmark Python tests, full targeted headless city/legacy/course/benchmark/menu suites, QA exit/timeout contracts and228 real Vulkan city checks pass. The instance mutation detector requires a real renderer and two frames plus frame_post_draw to read the updated buffer; escalation164605 documents the deferred-readback issue. This validates the actual mutated MultiMesh instead of substituting a synthetic transform. Cold and regenerated geometry imports preserve every shared PNG sidecar. All17 final captures pass. No HIGH or MED remains open.
