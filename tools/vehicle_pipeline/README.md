# Local vehicle asset pipeline

This runner sends each blueprint through two ComfyUI API-format workflows: a
controlled neutral render, then Hunyuan3D/TRELLIS image-to-3D. It generates the body,
End A wheel, and End B wheel independently so wheel geometry is physically separate.

## Required workflow preparation

1. Start ComfyUI with `/home/crazyh/ComfyUI/run_comfyui.sh --listen 127.0.0.1 --port 8188`.
2. The included `vehicle_render_api.json` extracts and normalizes the clean side
   elevation from the common 1024×572 blueprint layout. If a future viewpoint-edit or
   ControlNet model is installed, replace it with an API-exported graph containing
   `{{INPUT_IMAGE}}` and `{{OUTPUT_PREFIX}}`.
3. The included `hunyuan3d_api.json` is a ready API payload for the built-in
   Hunyuan3D 2.1 nodes. Replace it with a tested TRELLIS workflow if preferred.
4. Any replacement workflow must be exported with **Save (API Format)** to the path
   in `pipeline_config.json`.

The runner intentionally rejects UI-format workflow JSON and missing tokens. This
prevents a valid-looking request from queueing the wrong image or prompt.

## Execute

```bash
# Ollama and ComfyUI share 8 GB VRAM; release Qwen before loading 3D models.
curl -s http://127.0.0.1:11434/api/generate \
  -d '{"model":"qwen2.5-coder:7b","keep_alive":0}' >/dev/null

/home/crazyh/ComfyUI/run_comfyui.sh --listen 127.0.0.1 --port 8188

# In another terminal:
python3 tools/vehicle_pipeline/run_pipeline.py --preflight
python3 tools/vehicle_pipeline/run_pipeline.py --vehicle blackjack
python3 tools/vehicle_pipeline/run_pipeline.py
```

## Blackjack Color ID guide

`workflows/blackjack_color_id_controlnet_api.json` is a directly queueable ComfyUI
API graph for the Spy Hunter side elevation. It crops the side view, applies Canny
ControlNet at strength `1.0`, and samples for 18 steps with Euler. Queue it after
starting ComfyUI:

```bash
curl -sS -X POST http://127.0.0.1:8188/prompt \
  -H 'Content-Type: application/json' \
  --data-binary "$(jq -n --slurpfile graph \
    tools/vehicle_pipeline/workflows/blackjack_color_id_controlnet_api.json \
    '{prompt: $graph[0]}')"
```

The reviewed project guides are `blackjack_color_id_mask.png` and
`blackjack_protected_parts_mask.png`. Treat them as material-authoring guides, not
UV-ready production masks: a 2D side projection cannot directly address the opposite
side or top surfaces of the GLB.

Outputs install into `godot/assets/vehicles/models/<vehicle-id>/` as the body GLB,
`wheel_a.glb`, `wheel_b.glb`, and a reproducibility/QA manifest. Godot falls back to
the old primitives until each body file exists, so partial batches do not break play.

## Asset contract

- Body GLB: Godot +Y up, End A points -Z, End B points +Z, centered at hub height.
- Body and wheels are separate GLBs; body generation explicitly excludes wheels.
- Body textures/materials are ignored by `vehicle.gd`; all non-wheel mesh surfaces get
  a flat `StandardMaterial3D` override whose `albedo_color` follows the selected paint.
- Imported wheel/rim/tire nodes accidentally present in a body GLB are hidden by name.
- Collision boxes and all four wheel hardpoints live in `vehicle_catalog.gd`; tune those
  values after checking the imported scale. No drive, grip, suspension, mass, or damping
  parameter is modified by the visual integration.
