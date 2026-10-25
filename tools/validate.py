#!/usr/bin/env python3
"""Run the same independent package/example checks locally and in CI."""
import argparse
import datetime
import json
import pathlib
import re
import subprocess

ROOT = pathlib.Path(__file__).resolve().parents[1]

def command(args, log, cwd=ROOT):
    print('+ ' + ' '.join(map(str, args)), flush=True)
    with log.open('w') as output:
        result = subprocess.run(args, cwd=cwd, stdout=output, stderr=subprocess.STDOUT)
    if result.returncode:
        print('\n'.join(log.read_text(errors='replace').splitlines()[-40:]))
        raise SystemExit(f'Failed; full log: {log}')

def simulator():
    data = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', '--json']))
    # Use the selected Xcode's SDK generation, not a newer incompatible runtime
    # that happens to be installed on the host.
    sdk = subprocess.check_output(['xcrun', '--sdk', 'iphonesimulator', '--show-sdk-version'], text=True).strip()
    maximum = tuple(map(int, sdk.split('.')))
    runtimes = [r for r in data['runtimes'] if r.get('isAvailable') and r['name'].startswith('iOS ')
                and tuple(map(int, r['version'].split('.'))) <= maximum]
    if not runtimes:
        raise SystemExit('Install an iOS simulator runtime compatible with the selected Xcode.')
    runtime = max(runtimes, key=lambda r: tuple(map(int, r['version'].split('.'))))
    name = 'PaperConfetti Example'
    existing = [d for d in data['devices'].get(runtime['identifier'], []) if d['name'] == name and d.get('isAvailable')]
    if existing:
        return existing[0]['udid']
    # Prefer an installed standard iPhone type already compatible with this runtime.
    phones = [d for d in data['devices'].get(runtime['identifier'], [])
              if d.get('isAvailable') and 'iPhone' in d['name'] and d.get('deviceTypeIdentifier')]
    if phones:
        device_type = phones[0]['deviceTypeIdentifier']
    else:
        # iPhone 16 is supported by both CI runtime generations (iOS 18+).
        device_type = next(d['identifier'] for d in data['devicetypes'] if d['name'] == 'iPhone 16')
    return subprocess.check_output(['xcrun', 'simctl', 'create', name, device_type, runtime['identifier']], text=True).strip()

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--core-only', action='store_true', help='Physics tests without Xcode/Simulator')
    parser.add_argument('--skip-core', action='store_true')
    parser.add_argument('--device', help='Existing dedicated test simulator UUID')
    args = parser.parse_args()
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ')
    output = ROOT / '.artifacts' / ('validation-' + stamp)
    output.mkdir(parents=True)
    if not args.skip_core:
        command(['swift', 'test'], output / 'core.log')
        command(['swift', 'build', '-c', 'release'], output / 'core-release.log')
    if args.core_only:
        print('Core checks passed: ' + str(output)); return
    device = args.device or simulator()
    devices = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', 'devices', '--json']))['devices']
    selected = next(d for rows in devices.values() for d in rows if d['udid'] == device)
    if selected['name'] != 'PaperConfetti Example':
        raise SystemExit('Use only the dedicated simulator named PaperConfetti Example.')
    if selected['state'] != 'Booted':
        command(['xcrun', 'simctl', 'boot', device], output / 'boot.log')
    command(['xcrun', 'simctl', 'bootstatus', device, '-b'], output / 'bootstatus.log')
    derived = ROOT / '.artifacts' / 'DerivedData'
    destination = 'platform=iOS Simulator,id=' + device
    common = ['-destination', destination, '-derivedDataPath', str(derived), '-parallel-testing-enabled', 'NO']
    command(['xcodebuild', '-scheme', 'PaperConfetti', *common,
             '-resultBundlePath', str(output / 'PackageTests.xcresult'), 'test'], output / 'package-ios.log')
    command(['xcodebuild', '-project', 'Examples/PaperConfettiExample.xcodeproj', '-scheme', 'PaperConfettiExample',
             *common, '-resultBundlePath', str(output / 'ExampleTests.xcresult'), 'test'], output / 'example-ios.log')
    command(['xcodebuild', '-project', 'Examples/PaperConfettiExample.xcodeproj', '-scheme', 'PaperConfettiExample',
             '-configuration', 'Release', '-destination', 'generic/platform=iOS Simulator',
             '-derivedDataPath', str(derived), 'build'], output / 'example-release.log')
    command(['xcodebuild', '-scheme', 'PaperConfetti', '-destination', 'generic/platform=iOS Simulator',
             '-derivedDataPath', str(derived), 'docbuild'], output / 'documentation.log')
    receipt = {'completedAt': datetime.datetime.now(datetime.timezone.utc).isoformat(), 'simulator': device,
               'xcode': subprocess.check_output(['xcodebuild', '-version'], text=True).strip(),
               'swift': subprocess.check_output(['swift', '--version'], text=True).strip(),
               'coreSkipped': args.skip_core, 'result': 'passed'}
    (output / 'result.json').write_text(json.dumps(receipt, indent=2) + '\n')
    print('All checks passed: ' + str(output))

if __name__ == '__main__':
    main()
