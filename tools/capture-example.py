#!/usr/bin/env python3
"""Capture the actual example UI on its dedicated simulator after validation."""
import subprocess
import time
from validate import ROOT, simulator


def main():
    device = simulator()
    app = ROOT / '.artifacts/DerivedData/Build/Products/Debug-iphonesimulator/PaperConfettiExample.app'
    if not app.exists():
        raise SystemExit('Run python3 tools/validate.py first.')
    output = ROOT / '.artifacts/captures'
    output.mkdir(parents=True, exist_ok=True)
    bundle = 'org.paperconfetti.example'
    subprocess.run(['xcrun', 'simctl', 'bootstatus', device, '-b'], check=True)
    subprocess.run(['xcrun', 'simctl', 'status_bar', device, 'override', '--time', '9:41', '--batteryState', 'charged', '--batteryLevel', '100'], check=True)
    subprocess.run(['xcrun', 'simctl', 'install', device, str(app)], check=True)
    for mode in ['still', 'confetti', 'hearts', 'shower']:
        subprocess.run(['xcrun', 'simctl', 'terminate', device, bundle], capture_output=True)
        subprocess.run(['xcrun', 'simctl', 'launch', device, bundle] + ({'confetti': ['--capture-pop'], 'hearts': ['--capture-hearts'], 'shower': ['--capture-shower']}.get(mode, [])), check=True)
        time.sleep(3)
        subprocess.run(['xcrun', 'simctl', 'io', device, 'screenshot', '--display=1', str(output / (mode + '.png'))], check=True)
    print(output)


if __name__ == '__main__':
    main()
