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

def compile_examples(output):
    # Type checking alone misses diagnostics emitted during SIL/code generation.
    # Keep the package in its declared language mode; this is a separate Swift 6 check.
    version = subprocess.check_output(['swift', '--version'], text=True)
    match = re.search(r'Swift version (\d+)', version)
    if not match or int(match.group(1)) < 6:
        print('Swift 6 compiler check skipped: selected compiler predates Swift 6.', flush=True)
        return False
    sdk = subprocess.check_output(['xcrun', '--sdk', 'iphonesimulator', '--show-sdk-path'], text=True).strip()
    architecture = subprocess.check_output(['uname', '-m'], text=True).strip()
    compiled = output / 'strict-swift6'
    compiled.mkdir()
    common = ['xcrun', 'swiftc', '-sdk', sdk, '-target', architecture + '-apple-ios16.0-simulator',
              '-swift-version', '6', '-strict-concurrency=complete', '-warnings-as-errors', '-parse-as-library']
    command([*common, '-emit-library', '-emit-module', '-module-name', 'PaperConfetti',
             '-emit-module-path', str(compiled / 'PaperConfetti.swiftmodule'),
             '-o', str(compiled / 'libPaperConfetti.dylib'),
             *map(str, sorted((ROOT / 'Sources/PaperConfetti').glob('*.swift')))],
            compiled / 'library.log')
    guide = (ROOT / 'Sources/PaperConfetti/PaperConfetti.docc/ButtonOrigin.md').read_text()
    example = (ROOT / 'Examples/ButtonOrigin.swift').read_text()
    snippets = re.findall(r'```swift\n(.*?)```', guide, re.S)
    if not snippets or snippets[0].strip() != example.strip():
        raise SystemExit('The button-origin DocC example must match Examples/ButtonOrigin.swift.')
    for name in ['QuickStart', 'ButtonOrigin']:
        command([*common, '-c', '-I', str(compiled), str(ROOT / 'Examples' / (name + '.swift')),
                 '-o', str(compiled / (name + '.o'))], compiled / (name + '.log'))
    return True

def simulator():
    data = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', '--json']))
    # Use the selected Xcode's SDK generation, not a newer incompatible runtime
    # that happens to be installed on the host.
    sdk = subprocess.check_output(['xcrun', '--sdk', 'iphonesimulator', '--show-sdk-version'], text=True).strip()
    maximum = tuple(map(int, sdk.split('.')))
    # Device-specific runtimes can share the same version as ordinary iOS.
    # Pixel probes assume one full-width phone display, so never select a
    # dual-display runtime merely because it appears first in simctl's list.
    phone_type = 'com.apple.CoreSimulator.SimDeviceType.iPhone-16'
    runtimes = [r for r in data['runtimes'] if r.get('isAvailable') and r['name'].startswith('iOS ')
                and tuple(map(int, r['version'].split('.'))) <= maximum
                and (not r.get('supportedDeviceTypes') or any(
                    d['identifier'] == phone_type for d in r['supportedDeviceTypes']))]
    if not runtimes:
        raise SystemExit('Install an iOS simulator runtime compatible with the selected Xcode.')
    runtime = max(runtimes, key=lambda r: tuple(map(int, r['version'].split('.'))))
    name = 'PaperConfetti Example'
    existing = [d for d in data['devices'].get(runtime['identifier'], []) if d['name'] == name and d.get('isAvailable')]
    if existing:
        return existing[0]['udid']
    # iPhone 16 is supported by both CI runtime generations (iOS 18+).
    device_type = phone_type
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
    strict_swift6 = compile_examples(output)
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
               'coreSkipped': args.skip_core, 'strictSwift6Compiled': strict_swift6, 'result': 'passed'}
    (output / 'result.json').write_text(json.dumps(receipt, indent=2) + '\n')
    print('All checks passed: ' + str(output))

if __name__ == '__main__':
    main()
