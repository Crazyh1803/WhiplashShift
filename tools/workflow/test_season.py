import argparse
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
ERROR = re.compile(r'(^ERROR:|SCRIPT ERROR:|Parse Error:)', re.MULTILINE)


def run_engine(args, timeout):
    engine = os.environ.get('GODOT_BIN') or shutil.which('godot')
    if not engine:
        raise RuntimeError('Godot is not on PATH; set GODOT_BIN to its executable.')
    log = ROOT / '.ai' / 'season-engine.log'
    log.parent.mkdir(exist_ok=True)
    with log.open('w', encoding='utf-8') as output:
        result = subprocess.run([engine, *args], cwd=ROOT, stdout=output,
                                stderr=subprocess.STDOUT, timeout=timeout)
    report = log.read_text(encoding='utf-8', errors='replace')
    print(report, flush=True)
    if result.returncode or ERROR.search(report):
        raise RuntimeError(f'Godot check failed: {args}')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--capture', action='store_true')
    parser.add_argument('--scenes', nargs='+', default=[
        'block_circuit_tests', 'season_course_tests', 'test_main',
        'race_tests', 'course_cues_tests', 'corner_tests', 'racecraft_tests',
        'track_visual_tests', 'driving_hud_tests', 'compact_hud_tests'])
    options = parser.parse_args()
    run_engine(['--headless', '--import', '--path', 'godot'], 180)
    if options.capture:
        run_engine(['--path', 'godot', 'res://tests/city_visual_qa.tscn', '--', '--capture'], 180)
        run_engine(['--path', 'godot', 'res://tests/season_course_tests.tscn', '--', '--capture'], 180)
    else:
        for scene in options.scenes:
            print(f'CHECK {scene}', flush=True)
            run_engine(['--headless', '--fixed-fps', '120', '--path', 'godot',
                        f'res://tests/{scene}.tscn'], 900 if scene == 'race_tests' else 300)
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (RuntimeError, subprocess.TimeoutExpired) as error:
        print(error, file=sys.stderr)
        sys.exit(1)
