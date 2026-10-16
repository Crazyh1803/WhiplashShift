#!/usr/bin/env python3
"""Batch blueprint -> neutral render -> GLB through the local ComfyUI API."""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
import shutil
import struct
import sys
import time
import uuid
from pathlib import Path
from typing import Any

import requests


TOKENS = ("{{INPUT_IMAGE}}", "{{OUTPUT_PREFIX}}")


class PipelineError(RuntimeError):
    pass


def load_json(path: Path) -> Any:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def replace_tokens(value: Any, replacements: dict[str, Any]) -> Any:
    if isinstance(value, dict):
        return {key: replace_tokens(item, replacements) for key, item in value.items()}
    if isinstance(value, list):
        return [replace_tokens(item, replacements) for item in value]
    if isinstance(value, str):
        for token, replacement in replacements.items():
            if value == token:
                return replacement
            value = value.replace(token, str(replacement))
    return value


def assert_api_workflow(path: Path, required_tokens: tuple[str, ...]) -> dict[str, Any]:
    if not path.is_file():
        raise PipelineError(f"Missing API workflow: {path}")
    graph = load_json(path)
    if not isinstance(graph, dict) or not graph or not all(
        isinstance(node, dict) and "class_type" in node and "inputs" in node
        for node in graph.values()
    ):
        raise PipelineError(f"{path} is not ComfyUI API-format JSON (Save (API Format)).")
    serialized = json.dumps(graph)
    missing = [token for token in required_tokens if token not in serialized]
    if missing:
        raise PipelineError(f"{path} is missing template token(s): {', '.join(missing)}")
    return graph


def check_required_files(config: dict[str, Any]) -> None:
    missing = [
        str(Path(item).expanduser()) for item in config.get("required_files", [])
        if not Path(item).expanduser().is_file()
    ]
    if missing:
        raise PipelineError("Missing local model dependency:\n  " + "\n  ".join(missing))


class ComfyClient:
    def __init__(self, base_url: str, timeout: float, poll_seconds: float) -> None:
        self.base_url = base_url.rstrip("/")
        self.timeout = timeout
        self.poll_seconds = poll_seconds
        self.session = requests.Session()
        self.client_id = str(uuid.uuid4())

    def preflight(self) -> dict[str, Any]:
        response = self.session.get(f"{self.base_url}/system_stats", timeout=10)
        response.raise_for_status()
        stats = response.json()
        if not any(device.get("type") == "cuda" for device in stats.get("devices", [])):
            raise PipelineError("ComfyUI is not using CUDA; refusing production generation.")
        return stats

    def upload_image(self, path: Path) -> str:
        with path.open("rb") as handle:
            response = self.session.post(
                f"{self.base_url}/upload/image",
                files={"image": (path.name, handle, "application/octet-stream")},
                data={"type": "input", "overwrite": "true"},
                timeout=120,
            )
        response.raise_for_status()
        result = response.json()
        subfolder = result.get("subfolder", "")
        return f"{subfolder}/{result['name']}".lstrip("/")

    def run(self, workflow: dict[str, Any]) -> dict[str, Any]:
        response = self.session.post(
            f"{self.base_url}/prompt",
            json={"prompt": workflow, "client_id": self.client_id},
            timeout=30,
        )
        if not response.ok:
            raise PipelineError(f"ComfyUI rejected workflow: {response.text}")
        prompt_id = response.json()["prompt_id"]
        deadline = time.monotonic() + self.timeout
        while time.monotonic() < deadline:
            history_response = self.session.get(
                f"{self.base_url}/history/{prompt_id}", timeout=30
            )
            history_response.raise_for_status()
            history = history_response.json().get(prompt_id)
            if history:
                status = history.get("status", {})
                if status.get("completed"):
                    return history
                messages = status.get("messages", [])
                if any(message and message[0] == "execution_error" for message in messages):
                    raise PipelineError(f"ComfyUI execution failed: {messages[-1]}")
            time.sleep(self.poll_seconds)
        raise PipelineError(f"Timed out waiting for ComfyUI prompt {prompt_id}")

    def download(self, file_record: dict[str, str], destination: Path) -> None:
        response = self.session.get(
            f"{self.base_url}/view",
            params={
                "filename": file_record["filename"],
                "subfolder": file_record.get("subfolder", ""),
                "type": file_record.get("type", "output"),
            },
            timeout=300,
        )
        response.raise_for_status()
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(response.content)


def output_records(history: dict[str, Any], suffixes: tuple[str, ...]) -> list[dict[str, str]]:
    records: list[dict[str, str]] = []

    def visit(value: Any) -> None:
        if isinstance(value, dict):
            filename = value.get("filename")
            if isinstance(filename, str) and filename.lower().endswith(suffixes):
                records.append(value)
            else:
                for nested in value.values():
                    visit(nested)
        elif isinstance(value, list):
            for nested in value:
                visit(nested)

    visit(history.get("outputs", {}))
    return records


def glb_summary(path: Path) -> dict[str, Any]:
    data = path.read_bytes()
    if len(data) < 20 or data[:4] != b"glTF":
        raise PipelineError(f"ComfyUI output is not a valid binary GLB: {path}")
    version, declared_length = struct.unpack_from("<II", data, 4)
    if version != 2 or declared_length != len(data):
        raise PipelineError(f"Invalid GLB v2 header or length: {path}")
    offset = 12
    document: dict[str, Any] | None = None
    while offset + 8 <= len(data):
        chunk_length, chunk_type = struct.unpack_from("<II", data, offset)
        offset += 8
        payload = data[offset : offset + chunk_length]
        offset += chunk_length
        if chunk_type == 0x4E4F534A:
            document = json.loads(payload.rstrip(b" \t\r\n\0").decode("utf-8"))
            break
    if document is None:
        raise PipelineError(f"GLB has no JSON scene chunk: {path}")
    return {
        "bytes": len(data),
        "meshes": len(document.get("meshes", [])),
        "nodes": len(document.get("nodes", [])),
        "materials": len(document.get("materials", [])),
        "textures": len(document.get("textures", [])),
    }


def prompt_for(config: dict[str, Any], vehicle: dict[str, str], part: str) -> tuple[str, str]:
    prompts = config["prompts"]
    positive = prompts[part].format(vehicle_id=vehicle["id"])
    negative = prompts["negative_body" if part == "body" else "negative_wheel"]
    return positive, negative


def execute(config_path: Path, selected_ids: set[str]) -> None:
    config = load_json(config_path)
    project_root = Path(config["project_root"]).expanduser().resolve()
    work_root = Path(config["work_root"]).expanduser().resolve()
    render_workflow_path = Path(config["workflows"]["render_api"]).expanduser().resolve()
    mesh_workflow_path = Path(config["workflows"]["mesh_api"]).expanduser().resolve()
    render_template = assert_api_workflow(render_workflow_path, TOKENS)
    mesh_template = assert_api_workflow(
        mesh_workflow_path, ("{{INPUT_IMAGE}}", "{{OUTPUT_PREFIX}}")
    )
    check_required_files(config)

    client = ComfyClient(
        config["server"], float(config.get("timeout_seconds", 3600)),
        float(config.get("poll_seconds", 2)),
    )
    stats = client.preflight()
    print(f"ComfyUI ready at {config['server']}: {stats.get('system', {}).get('os', 'unknown OS')}")

    for vehicle in config["vehicles"]:
        vehicle_id = vehicle["id"]
        if selected_ids and vehicle_id not in selected_ids:
            continue
        blueprint = Path(vehicle["blueprint"]).expanduser().resolve()
        if not blueprint.is_file():
            raise PipelineError(f"Missing blueprint for {vehicle_id}: {blueprint}")
        vehicle_work = work_root / vehicle_id
        vehicle_output = project_root / "godot/assets/vehicles/models" / vehicle_id
        vehicle_work.mkdir(parents=True, exist_ok=True)
        vehicle_output.mkdir(parents=True, exist_ok=True)
        uploaded_blueprint = client.upload_image(blueprint)
        manifest: dict[str, Any] = {
            "vehicle_id": vehicle_id,
            "blueprint": str(blueprint),
            "blueprint_sha256": sha256(blueprint),
            "render_workflow_sha256": sha256(render_workflow_path),
            "mesh_workflow_sha256": sha256(mesh_workflow_path),
            "parts": {},
        }

        for part, output_name in (("body", f"{vehicle_id}.glb"), ("wheel_a", "wheel_a.glb"), ("wheel_b", "wheel_b.glb")):
            positive, negative = prompt_for(config, vehicle, part)
            prefix = f"whiplash/{vehicle_id}/{part}"
            render_graph = replace_tokens(copy.deepcopy(render_template), {
                "{{INPUT_IMAGE}}": uploaded_blueprint,
                "{{PROMPT}}": positive,
                "{{NEGATIVE_PROMPT}}": negative,
                "{{OUTPUT_PREFIX}}": prefix,
                "{{DENOISE}}": float(config["denoise"][part]),
            })
            render_history = client.run(render_graph)
            render_records = output_records(render_history, (".png", ".jpg", ".jpeg", ".webp"))
            if not render_records:
                raise PipelineError(f"Render workflow produced no image for {vehicle_id}/{part}")
            render_path = vehicle_work / f"{part}_neutral.png"
            client.download(render_records[-1], render_path)
            uploaded_render = client.upload_image(render_path)

            mesh_graph = replace_tokens(copy.deepcopy(mesh_template), {
                "{{INPUT_IMAGE}}": uploaded_render,
                "{{OUTPUT_PREFIX}}": prefix,
            })
            mesh_history = client.run(mesh_graph)
            mesh_records = output_records(mesh_history, (".glb",))
            if not mesh_records:
                raise PipelineError(f"Mesh workflow produced no GLB for {vehicle_id}/{part}")
            staged_glb = vehicle_work / output_name
            client.download(mesh_records[-1], staged_glb)
            qa = glb_summary(staged_glb)
            shutil.copy2(staged_glb, vehicle_output / output_name)
            manifest["parts"][part] = {
                "file": output_name,
                "sha256": sha256(staged_glb),
                "prompt": positive,
                "negative_prompt": negative,
                "qa": qa,
            }
            print(f"{vehicle_id}/{part}: {qa['meshes']} mesh(es), {qa['bytes']} bytes")

        manifest["integration"] = {
            "body_material": "Godot StandardMaterial3D runtime override; albedo_color is UI-driven",
            "decals": "opaque body MeshInstance3D surfaces receive Godot Decal projection",
            "wheel_isolation": "body, End A wheel, and End B wheel are separate GLB files",
        }
        manifest_path = vehicle_output / "manifest.json"
        manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
        print(f"installed {vehicle_id} -> {vehicle_output}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, default=Path(__file__).with_name("pipeline_config.json"))
    parser.add_argument("--vehicle", action="append", default=[], help="vehicle id; repeat to limit batch")
    parser.add_argument("--preflight", action="store_true", help="validate config/workflows without queueing")
    args = parser.parse_args()
    try:
        if args.preflight:
            config = load_json(args.config)
            assert_api_workflow(Path(config["workflows"]["render_api"]), TOKENS)
            assert_api_workflow(
                Path(config["workflows"]["mesh_api"]),
                ("{{INPUT_IMAGE}}", "{{OUTPUT_PREFIX}}"),
            )
            check_required_files(config)
            ComfyClient(config["server"], 30, 1).preflight()
            print("preflight passed")
        else:
            execute(args.config, set(args.vehicle))
    except (OSError, ValueError, requests.RequestException, PipelineError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
