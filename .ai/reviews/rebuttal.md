# Tangent review resolution

Asset review round 2 (20261030-160655-codex.md) APPROVE retains a MED on tangent handedness. The asset lead used decreasing exported V in the generated bitangent and then tested that same convention. Root agrees with the independent reviewer: use increasing exported V consistently with glTF/MikkTSpace. Correct generator/validator fixture signs and regenerate the asset tangent buffers through the asset lead. This is a technical correction, not an unresolved request for human judgement. No third review round will be run for this scope; verify the corrected convention with an independently derived gradient and synthetic mirrored/unmirrored geometry.

Reference: https://registry.khronos.org/glTF/specs/2.0/glTF-2.0.html#meshes-using-primitive-data, bitangent=cross(normal.xyz,tangent.xyz)*tangent.w, MikkTSpace recommended for missing tangents. Do not apply a second image-origin flip to an already exported UV.
