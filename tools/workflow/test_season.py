import argparse
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
ERROR = re.compile(r'(^ERROR:|SCRIPT ERROR:|Parse Error:)', re.MULTILINE)


def run_bounded(command, log, timeout):
    """Run a child with a hard timeout; on expiry it is killed and reaped before raising."""
    log.parent.mkdir(exist_ok=True)
    with log.open('w', encoding='utf-8') as output:
        child = subprocess.Popen(command, cwd=ROOT, stdout=output, stderr=subprocess.STDOUT)
        try:
            code = child.wait(timeout=timeout)
        except BaseException:
            child.kill()
            child.wait()
            raise
    return code, log.read_text(encoding='utf-8', errors='replace')


def find_engine():
    engine = os.environ.get('GODOT_BIN') or shutil.which('godot')
    if not engine:
        raise RuntimeError('Godot is not on PATH; set GODOT_BIN to its executable.')
    return engine


def run_engine(args, timeout):
    code, report = run_bounded([find_engine(), *args], ROOT / '.ai' / 'season-engine.log', timeout)
    print(report, flush=True)
    if code or ERROR.search(report):
        raise RuntimeError(f'Godot check failed: {args}')


def selftest_run_bounded():
    """A child that outlives its timeout must be killed and reaped, not left running."""
    holder = {}
    original = subprocess.Popen

    def spy(*args, **kwargs):
        holder['child'] = original(*args, **kwargs)
        return holder['child']

    subprocess.Popen = spy
    try:
        run_bounded([sys.executable, '-I', '-c', 'import time; time.sleep(60)'], ROOT / '.ai' / 'bounded-selftest.log', 2)
    except subprocess.TimeoutExpired:
        pass
    else:
        raise RuntimeError('run_bounded did not time out a hung child')
    finally:
        subprocess.Popen = original
    if holder['child'].poll() is None:
        raise RuntimeError('run_bounded left a timed-out child running')
    print('PASS: run_bounded kills and reaps a hung child', flush=True)


def check_city_realism_qa():
    """Exit-code contract of the QA scene: 0 healthy, 1 with --selftest-fail, no captures unflagged."""
    engine = find_engine()
    base = [engine, '--headless', '--fixed-fps', '120', '--path', 'godot', 'res://tests/city_realism_qa.tscn']
    log = ROOT / '.ai' / 'city-realism-qa.log'
    code, report = run_bounded(base, log, 300)
    print(report, flush=True)
    if code != 0 or ERROR.search(report) or 'CITY_REALISM_QA: 0 failures' not in report:
        raise RuntimeError(f'City QA healthy run failed (exit {code})')
    if 'CITY_CAPTURE' in report:
        raise RuntimeError('City QA wrote captures without --capture')
    code, report = run_bounded([*base, '--', '--selftest-fail'], log, 300)
    print(report, flush=True)
    if code != 1 or 'CITY_REALISM_QA: 1 failures' not in report:
        raise RuntimeError(f'City QA --selftest-fail did not exit 1 through its own check (exit {code})')
    print('PASS: city QA exits 0 healthy, 1 on --selftest-fail, no captures without --capture', flush=True)


def validate_city_kit():
    for validator in ('validate_city_kit.py', 'validate_habitation_workshop.py', 'validate_city_neighborhood.py', 'validate_city_streets.py',
                      'validate_industrial_market.py', 'test_validate_industrial_market.py',
                      'validate_city_families.py', 'test_validate_city_families.py'):
        result = subprocess.run([sys.executable, '-I', str(ROOT / 'tools' / 'city_pipeline' / validator)],
                                cwd=ROOT, capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=120)
        print(result.stdout + result.stderr, flush=True)
        if result.returncode:
            raise RuntimeError(f'City asset validation failed: {validator}')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--capture', action='store_true')
    parser.add_argument('--menu-capture', action='store_true')
    parser.add_argument('--scenes', nargs='+', default=[
        'season_codec_tests', 'race_modes_tests', 'reverse_race_tests', 'main_menu_visual_qa',
        'city_street_block_tests', 'block_circuit_tests', 'city_kit_tests', 'city_realism_tests','season_course_tests', 'vehicle_audio_tests', 'vehicle_feedback_tests',
        'vehicle_effects_tests', 'bodywork_visual_tests', 'test_main', 'viscera_response_tests',
        'rubble_response_tests', 'armor_response_tests', 'coolant_response_tests', 'effluent_response_tests',
        'ichor_response_tests', 'track_visual_tests', 'viscera_pit_tests', 'boulder_motion_tests',
        'item_tests', 'combat_hud_tests', 'driving_hud_tests', 'dashboard_hud_tests',
        'compact_hud_tests', 'weapon_attachment_tests', 'deployment_oil_tests', 'racecraft_tests',
        'cpu_main', 'race_tests', 'course_cues_tests', 'camera_tests',
        'corner_tests', 'terrain_profile_tests', 'blackjack_refined_tests', 'blackjack_blueprint_tests',
        'consolidation_tests', 'nightshift_blueprint_tests', 'ramjet_blueprint_tests', 'boilerfang_blueprint_tests',
        'helix_blueprint_tests', 'knifeedge_blueprint_tests', 'industrial_market_tests'])
    options = parser.parse_args()
    validate_city_kit()
    selftest_run_bounded()
    run_engine(['--headless', '--import', '--path', 'godot'], 180)
    if options.menu_capture:
        run_engine(['--path', 'godot', 'res://tests/main_menu_visual_qa.tscn', '--', '--capture'], 180)
    elif options.capture:
        run_engine(['--path', 'godot', 'res://tests/city_visual_qa.tscn', '--', '--capture'], 180)
        run_engine(['--path', 'godot', 'res://tests/season_course_tests.tscn', '--', '--capture'], 180)
    else:
        for scene in options.scenes:
            print(f'CHECK {scene}', flush=True)
            run_engine(['--headless', '--fixed-fps', '120', '--path', 'godot',
                        f'res://tests/{scene}.tscn'], 900 if scene in ('race_tests', 'season_course_tests', 'cpu_main', 'reverse_race_tests') else 300)
            if scene == 'city_realism_tests':
                check_city_realism_qa()
    return 0


if __name__ == '__main__':
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
    sys.stderr.reconfigure(encoding='utf-8', errors='replace')
    try:
        sys.exit(main())
    except (RuntimeError, subprocess.TimeoutExpired) as error:
        print(error, file=sys.stderr)
        sys.exit(1)
