import sys
sys.path.insert(0, 'tools/workflow')
import test_season as t

sys.stdout.reconfigure(encoding='utf-8', errors='replace')
t.run_engine(['--headless', '--import', '--path', 'godot'], 300)
t.run_engine(['--headless', '--fixed-fps', '120', '--path', 'godot', 'res://tests/city_backdrop_tests.tscn'], 300)
t.run_engine(['--path', 'godot', 'res://tests/city_backdrop_tests.tscn'], 300)
