# Final independent integration review

Second and final runtime integration round following .ai/reviews/20261029-210403-claude.md. Review only the staged diff against HEAD; the base contains Claude-authored asset sources and independently Codex-reviewed tests as read-only context. No authored code is being reviewed by its own author. Source root commit: 13f17e8b937ad78e3c77bff1f6e9d2c2cd23f63d

All initial HIGH/MED runtime findings addressed: interactive load failure returns to menu with error; no null mesh dereference; independent regression coverage (701 engine checks +8 Python tests before final strict import fixes), measured vehicle cost/shadow count and index counting. Tests exposed and lead fixed mistyped version/filename comparison errors and null-camera input after failure; those additions are in this diff. Other source hunks authored by lead are COLOR_0 validation, missing-input manifest failure, propagation of wrapper failure, one-line boot shaft winding and bounded checksum/atomic download. Two asset reviews approved, with these MED fixes needed. The optional source bootstrap now safely fails a bounded request; automatic retries are deliberately deferred because source assets are retained locally and this is not a game-time download.

A separate asset-lead export correction is in progress for wrong COLOR_0/UV0 export bindings discovered by independent tests; do not approve these known asset defects as fixed. It will regenerate actual assets, change known-defect prints and expected-failure tests into hard assertions and undergo separate independent export-code review. This review concerns integration code only. Root rendered16 actual Godot views at1600x900, four night lights/two shadowed spots; final captures follow corrected exports. Existing city775, Blackjack3563, menu746 passed. No vehicle/track changes.

Staged source hashes:
godot/scripts/main_menu.gd 318ee7fb8ff2d97641440c86d7f84500fa88098cbc3f4e9ece3af01d173c3c8e
godot/scripts/industrial_market_benchmark.gd 8f9591a4e4c27bbd2a4ba7fdba59ac348c7c37ea86ece443003ec2030055ee54
godot/scripts/industrial_market_benchmark.gd.uid b0bbdd760d413ceed583fd35861776911f9487bff2031bed00e4b038ea611325
godot/scripts/industrial_market_review.gd da9e56a30b6c0e6599a7e28bff413305541d5e74413e6292cf3b1481c1a3927b
godot/scripts/industrial_market_review.gd.uid a874b57eab78b631ee9deefad2562d39e37d1a51797b8a450dc5881552318440
godot/scenes/industrial_market_review.tscn d23f55e8e421d0a82bfcbe6517b6c1ccc407175eb45a30e2ff8c540d866df5c6
godot/tests/industrial_market_tests.gd 3bae3eaf019e87b059960ff11b1a55c49fb32095da0162dd2a038dee61eeaff9
tools/city_pipeline/build_industrial_market.py 0654e37b3fd60d3a9d4888b48380725e8f828f1ff6359b7ea9f12c0133a7b9c6
tools/city_pipeline/validate_industrial_market.py a449be65e8957c74603d774b92411abb7f5597dbf51d4db11b04f48450141c6f
tools/city_pipeline/industrial_market_base_source.py 41f39f40bf941d6850703c71da78e50c1adcf8dd263c6d8ad62e44d3ef568a7d
tools/city_pipeline/industrial_market_figure.py 70301617b152c2ec58b9f83b5b4af9400f99cf7beb01990c6b3d4e014a3cf096
.ai/blender/run_validator.py 5611415e8e8e23f18e6e87a2b6b4a0f62d22f33d65b0d8a59010166cebff3ef7
tools/city_pipeline/INDUSTRIAL_MARKET.md 0f83b005a54d50ac4e0261877c9c31d4491f44651a94d5eb1d3f324d964d2cc6
godot/assets/city/candidates/industrial_market/ramen_customer.glb.import b55cb0eb1c3049d079fd9242ccedf856e241fdae854322cda6d9e376cd8aa3c7
godot/assets/city/candidates/industrial_market/ramen_vendor.glb.import 3eb865c8c43adc12233328392c03fb6a9cd43d7f71fbca14b2c90d9827d65500
godot/assets/city/candidates/industrial_market/redline_shop.glb.import b9a6047520ae9586e6d0f5d417c8fb1cdfc91630e19241fe1f175e72f65fda6c
