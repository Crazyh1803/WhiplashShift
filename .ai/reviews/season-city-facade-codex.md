VERDICT: CHANGES_REQUESTED
FINDINGS:
- [HIGH] godot/shaders/city_facade.gdshader:7 — Both constant declarations use GDScript’s `:=`, which is invalid shader syntax. The facade shader cannot compile. — Use `const float BAY = 3.2;` and `const float FLOOR_H = 3.6;`.