#!/usr/bin/env python3
"""One command: Release build, device recordings, gesture tests and a local report.

No App Store credentials, upload, or changes to the library's dependencies.
"""
import argparse
import ctypes
import datetime as dt
import fcntl
import html
import json
from pathlib import Path
import re
import signal
import statistics
import subprocess
import sys
import time
import uuid
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / 'Benchmarks/PaperConfettiBenchmarks.xcodeproj'
ARTIFACTS = ROOT / '.artifacts'
LEGACY = 'f45961f97bbae6fff6e2e64546fea0189425ad92'
SCENARIOS = ['control', 'paper-classic-180-single', 'legacy-classic-180-single',
             'paper-classic-180-five', 'legacy-classic-180-five',
             'paper-classic-720-five', 'legacy-classic-720-five',
             'paper-festive-180-five', 'paper-festive-720-five']

class ProfileError(RuntimeError):
    pass


def run(command, log=None, timeout=900):
    command = list(map(str, command))
    try:
        if log:
            with Path(log).open('w') as stream:
                result = subprocess.run(command, cwd=ROOT, stdout=stream, stderr=subprocess.STDOUT, timeout=timeout)
            output = Path(log).read_text(errors='replace')
        else:
            result = subprocess.run(command, cwd=ROOT, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=timeout)
            output = result.stdout
        if result.returncode:
            detail = '\n'.join((output if log else result.stderr).splitlines()[-12:])
            raise ProfileError(f'{command[0]} failed: {detail}' + (f'\nFull log: {log}' if log else ''))
        return output
    except subprocess.TimeoutExpired as error:
        raise ProfileError(f'Timed out: {command[0]}. Partial evidence is preserved.') from error


def device_rows(payload):
    rows = []
    for d in payload.get('result', {}).get('devices', []):
        props = d.get('properties', {})
        hardware = props.get('hardware', d.get('hardwareProperties', {}))
        connection = props.get('connection', d.get('connectionProperties', {}))
        state = props.get('state', d.get('deviceProperties', {}))
        rows.append({'name': state.get('name', '?'), 'id': d.get('identifier'),
                     'udid': hardware.get('udid', d.get('identifier')),
                     'kind': hardware.get('deviceType'), 'simulator': hardware.get('reality') == 'simulated',
                     'state': connection.get('state', connection.get('tunnelState')),
                     'model': hardware.get('productType')})
    return rows


def select_device(rows, requested=None):
    phones = [d for d in rows if d['kind'] == 'iPhone' and not d['simulator'] and d['state'] == 'connected']
    if requested:
        phones = [d for d in phones if requested in (d['id'], d['udid'], d['name'])]
    if len(phones) != 1:
        raise ProfileError('Connect and unlock one iPhone, trust this Mac, and enable Settings → Privacy & Security → Developer Mode. '
                           'If more than one is connected, use --device NAME_OR_UDID. Run --list-devices to check.')
    return phones[0]


def signing_team(explicit):
    settings = ARTIFACTS / 'profile-settings.json'
    saved = json.loads(settings.read_text()) if settings.exists() else {}
    team = explicit or saved.get('team')
    if not team:
        identities = run(['security', 'find-identity', '-v', '-p', 'codesigning'])
        # The parenthesized ID in an Apple Development identity is often the
        # developer's personal ID, NOT the signing team. Read the public cert OU.
        hashes = set(re.findall(r'\b([A-F0-9]{40})\b[^\n]*"Apple Development:', identities))
        certificates = run(['security', 'find-certificate', '-a', '-c', 'Apple Development', '-p'])
        teams = set()
        for pem in re.findall(r'-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----', certificates, re.S):
            metadata = subprocess.check_output(['/usr/bin/openssl', 'x509', '-noout', '-subject',
                '-nameopt', 'RFC2253', '-fingerprint', '-sha1'], input=pem, text=True, timeout=10)
            fingerprint = re.search(r'Fingerprint=([0-9A-F:]+)', metadata, re.I)
            if fingerprint and fingerprint.group(1).replace(':', '').upper() in hashes:
                teams.update(re.findall(r'(?:^|,)OU=([A-Z0-9]{10})(?:,|$)', metadata))
        if len(teams) == 1:
            team = teams.pop()
    if not team or not re.fullmatch(r'[A-Z0-9]{10}', team):
        raise ProfileError('Sign into Xcode → Settings → Accounts, then run once with --team YOUR_10_CHARACTER_TEAM_ID. '
                           'The choice is remembered locally in .artifacts/profile-settings.json.')
    return team, settings


class TraceStart:
    """Register before xctrace; its host Darwin notification starts device playback."""
    def __init__(self):
        self.name = 'org.paperconfetti.trace.' + uuid.uuid4().hex
        self.lib = ctypes.CDLL('/usr/lib/libSystem.B.dylib')
        self.token = ctypes.c_int()
        if self.lib.notify_register_check(self.name.encode(), ctypes.byref(self.token)):
            raise ProfileError('Could not register the Instruments start notification.')
        self.changed()  # Clear initial registration state before starting xctrace.

    def changed(self):
        value = ctypes.c_int()
        if self.lib.notify_check(self.token, ctypes.byref(value)):
            raise ProfileError('Lost the Instruments start notification.')
        return bool(value.value)

    def close(self):
        self.lib.notify_cancel(self.token)


def validate_results(payload, run_id, pass_name, smoke=False):
    if payload.get('run_id') != run_id or payload.get('pass') != pass_name:
        raise ProfileError('Stale or mismatched device results; refusing to report them.')
    if not payload.get('finished') or not payload.get('success'):
        raise ProfileError(payload.get('error') or 'The app did not finish the protocol.')
    if bool(payload.get('simulator')) != smoke:
        raise ProfileError('Results came from the wrong device type.')
    rows = payload.get('rows', [])
    expected = {(name, round_) for round_ in range(1 if smoke else 2 if pass_name == 'cpu' else 4)
                for name in (SCENARIOS[:3] if smoke else SCENARIOS)}
    if pass_name == 'memory':
        expected = {(name, round_) for round_ in range(12) for name in ['paper-festive-180-five', 'legacy-classic-180-five']}
    observed = {(r.get('scenario'), r.get('round')) for r in rows}
    if observed != expected or len(rows) != len(expected):
        raise ProfileError('Missing or duplicate trials; no complete benchmark result.')
    if any(r.get('paper_active_after_settle') for r in rows):
        raise ProfileError('Particle cleanup check failed.')
    if pass_name != 'memory' and any(r.get('callback_count', 0) < 2 for r in rows):
        raise ProfileError('No usable callback samples; this is not a valid timing run.')
    return rows


def saved_measurements(output, pass_name, simulator):
    """Recover independently saved app samples, even when Instruments fails later."""
    path = output / (pass_name + '-measurements.json')
    if not path.exists():
        return None
    payload = json.loads(path.read_text())
    run_id = payload.get('run_id', '')
    if not re.fullmatch(r'[a-zA-Z0-9-]+', run_id):
        raise ProfileError('Invalid measurement identity; refusing recovery.')
    marker = output / ('start-' + run_id)
    if not marker.exists() or marker.read_text() != run_id:
        raise ProfileError('Measurement file has no matching start receipt; refusing recovery.')
    validate_results(payload, run_id, pass_name, smoke=simulator)
    return payload


def terminate_recording(process):
    if process.poll() is None:
        process.terminate()
        try:
            process.wait(timeout=20)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=20)


def finish_recording(process, trace, timeout=900):
    """Allow slow device trace processing without mistaking app completion for export completion."""
    print(f'Finalizing {trace.name}. Instruments may need several minutes after playback finishes…', flush=True)
    started = time.monotonic()
    try:
        if process.poll() is None:
            process.send_signal(signal.SIGINT)
        while process.poll() is None:
            remaining = timeout - (time.monotonic() - started)
            if remaining <= 0:
                terminate_recording(process)
                raise ProfileError(f'Instruments did not finalize {trace.name} within {timeout} seconds. '
                                   'Any saved app measurements are preserved; this trace is partial.')
            try:
                process.wait(timeout=min(20, remaining))
            except subprocess.TimeoutExpired:
                print(f'  Still finalizing {trace.name} ({int(time.monotonic() - started)} seconds). '
                      'Keep the iPhone connected and unlocked.', flush=True)
    except KeyboardInterrupt:
        terminate_recording(process)
        raise
    if process.returncode != 0:
        raise ProfileError(f'Instruments could not finalize {trace.name} (exit {process.returncode}). '
                           'Any saved app measurements are preserved; keep the recording log.')


def summarize(payloads):
    summary = []
    for payload in payloads:
        groups = {}
        for row in payload['rows']:
            if row['warmup']:
                continue
            groups.setdefault(row['scenario'], []).append(row)
        for name, rows in groups.items():
            def median(key):
                values = [r[key] for r in rows if isinstance(r.get(key), (int, float))]
                return statistics.median(values) if values else None
            summary.append({'pass': payload['pass'], 'scenario': name, 'samples': len(rows),
                            'cpu_ms': median('cpu_ms'), 'callback_p99_ms': median('callback_p99_ms'),
                            'settled_footprint_mib': median('footprint_end_bytes') / 1048576
                            if median('footprint_end_bytes') else None})
    return summary


def export_trace(trace, output):
    toc = output / (trace.stem + '-toc.xml')
    run(['xcrun', 'xctrace', 'export', '--input', trace, '--toc', '--output', toc], output / (trace.stem + '-export.log'), 180)
    schemas = sorted({table.get('schema') for table in ET.parse(toc).iter('table') if table.get('schema')})
    # Export the exact schemas this Xcode offers, without guessing a private column layout.
    # These are diagnostics for Instruments review, not fabricated zero-hitch statistics.
    selected = [s for s in schemas if s in ('hitches', 'OSSignpostIntervals', 'os-signpost')]
    # Full per-frame/GPU tables can be enormous; keep them in the trace. Export
    # the compact event/interval tables needed to locate a particular trial.
    exported = []
    for index, schema in enumerate(selected):
        path = output / f'{trace.stem}-table-{index}.xml'
        query = f'/trace-toc/run[@number="1"]/data/table[@schema="{schema}"]'
        try:
            run(['xcrun', 'xctrace', 'export', '--input', trace, '--xpath', query, '--output', path],
                output / f'{trace.stem}-table-{index}.log', 180)
            exported.append({'schema': schema, 'file': path.name})
        except ProfileError as error:
            exported.append({'schema': schema, 'error': str(error)})
    return {'trace': trace.name, 'schemas': schemas, 'exports': exported,
            'hitch_summary': 'Review Animation Hitches in Instruments; callback timing is not rendered-frame timing.'}


def write_report(output, receipt, payloads):
    receipt['summary'] = summarize(payloads)
    (output / 'report.json').write_text(json.dumps(receipt, indent=2) + '\n')
    def cell(value):
        return '—' if value is None else f'{value:.2f}' if isinstance(value, float) else html.escape(str(value))
    rows = ''.join('<tr>' + ''.join(f'<td>{cell(row.get(k))}</td>' for k in
                   ('pass', 'scenario', 'samples', 'cpu_ms', 'callback_p99_ms', 'settled_footprint_mib')) + '</tr>' for row in receipt['summary'])
    first_use = []
    memory_trends = []
    for payload in payloads:
        if payload['pass'] == 'timing':
            first_use = [row for row in payload['rows'] if row.get('first_renderer_use')]
        if payload['pass'] == 'memory':
            for renderer in ('paper', 'legacy'):
                settled = [r['footprint_end_bytes'] / 1048576 for r in payload['rows'] if r['renderer'] == renderer and r['footprint_end_bytes'] > 0]
                if settled:
                    memory_trends.append(f'<li>{renderer}: first settled {settled[0]:.2f} MiB; last {settled[-1]:.2f} MiB; change {settled[-1]-settled[0]:+.2f} MiB. Whole-process samples; inspect allocations before attributing retained memory.</li>')
    cold_rows = ''.join(f'<tr><td>{cell(r["scenario"])}</td><td>{cell(r.get("cpu_ms"))}</td><td>{cell(r.get("first_callback_ms"))}</td></tr>' for r in first_use)
    traces = ''.join(f'<li><a href="{html.escape(t["trace"])}">{html.escape(t["trace"])}</a> {html.escape(t.get("status", ""))} {html.escape(t.get("error", ""))}</li>' for t in receipt.get('traces', []))
    notes = ''.join(f'<li>{html.escape(str(note))}</li>' for note in receipt.get('review_notes', []))
    (output / 'report.html').write_text(f'''<!doctype html><meta charset="utf-8"><title>PaperConfetti profile</title>
<style>body{{font:16px system-ui;max-width:1200px;margin:40px auto;padding:0 24px;background:#111827;color:#e5e7eb}}a{{color:#67e8f9}}td,th{{text-align:left;padding:10px;border-bottom:1px solid #374151}}table{{border-collapse:collapse}}code{{color:#67e8f9}}</style>
<h1>PaperConfetti device profile</h1><p>{html.escape(receipt['status'])}</p>
<p>{html.escape(str(receipt.get('error', '')))}</p><ul>{notes}</ul>
<p>Warm medians below exclude round 0. Raw JSON retains first-use and warm-up trials. CPU is process CPU time. Callback p99 measures main-thread scheduling, <strong>not GPU frames, FPS, or hitch rate</strong>. Physical animation hitches require the Instruments trace.</p>
<p>Compare classic3 rows only against ConfettiSwiftUI 1.1.0. Festive13 and memory-soak rows have different visual workloads. Legacy randomization is unseeded. This measures a standalone host, not a complete Wordie game.</p>
<table><tr><th>Pass</th><th>Scenario</th><th>Samples</th><th>CPU ms</th><th>Callback p99 ms</th><th>Settled MiB</th></tr>{rows}</table>
<h2>First renderer use</h2><table><tr><th>Scenario</th><th>CPU ms across trial</th><th>First callback ms after trigger</th></tr>{cold_rows}</table>
<h2>Settled memory trend</h2><ul>{"".join(memory_trends)}</ul>
<h2>Recordings</h2><ul>{traces}</ul><p>Open Animation Hitches for actual frame delivery, Time Profiler for expensive stacks, and Allocations for retained objects. Use the available signposts to identify trials/cycles; check any recording notes above. There is no automatic performance pass/fail threshold; compare repeat runs on the same phone.</p>
<p>Gesture checks: {html.escape(receipt.get('interactions', 'not run'))}. Memory footprint may retain bounded system/texture caches; inspect its trend and live allocations, not just the initial-to-final difference.</p>
<p><a href="report.json">Run metadata and summary JSON</a></p>''')


class Runner:
    def __init__(self, args, output, device, team):
        self.args, self.output, self.device, self.team = args, output, device, team
        self.sim = args.simulator_smoke
        self.bundle = 'org.paperconfetti.benchmarks' + ('.' + team.lower() if team else '')
        self.derived = ARTIFACTS / ('ProfileSimulatorBuild' if self.sim else 'ProfileDeviceBuild')
        self.destination = ('platform=iOS Simulator,id=' if self.sim else 'platform=iOS,id=') + device['udid']
        self.common = ['xcodebuild', '-project', PROJECT, '-scheme', 'PaperConfettiBenchmarks', '-configuration', 'Release',
                       '-destination', self.destination, '-derivedDataPath', self.derived,
                       '-parallel-testing-enabled', 'NO', '-enableCodeCoverage', 'NO']
        if team:
            self.common += ['DEVELOPMENT_TEAM=' + team, 'BENCHMARK_BUNDLE_PREFIX=' + self.bundle, '-allowProvisioningUpdates', '-allowProvisioningDeviceRegistration']

    def build(self):
        print('Building the optimized benchmark app and gesture tests…', flush=True)
        run(self.common + ['build-for-testing'], self.output / 'build.log', 1200)
        pin = PROJECT / 'project.xcworkspace/xcshareddata/swiftpm/Package.resolved'
        resolved = json.loads(pin.read_text())
        if not any(p['identity'] == 'confettiswiftui' and p['state']['revision'] == LEGACY for p in resolved['pins']):
            raise ProfileError('The legacy comparison revision changed unexpectedly.')
        app = self.derived / 'Build/Products' / ('Release-iphonesimulator' if self.sim else 'Release-iphoneos') / 'PaperConfettiBenchmarks.app'
        command = ['xcrun', 'simctl', 'install', self.device['udid'], app] if self.sim else [
            'xcrun', 'devicectl', 'device', 'install', 'app', '--device', self.device['id'], app, '--timeout', '120']
        run(command, self.output / 'install.log', 150)

    def copy_from(self, source, destination):
        if self.sim:
            container = Path(run(['xcrun', 'simctl', 'get_app_container', self.device['udid'], self.bundle, 'data']).strip())
            destination.write_bytes((container / source).read_bytes())
        else:
            run(['xcrun', 'devicectl', 'device', 'copy', 'from', '--device', self.device['id'],
                 '--domain-type', 'appDataContainer', '--domain-identifier', self.bundle,
                 '--source', source, '--destination', destination, '--timeout', '30'], self.output / 'copy.log', 40)

    def trigger(self, run_id):
        marker = self.output / ('start-' + run_id)
        marker.write_text(run_id)
        if self.sim:
            container = Path(run(['xcrun', 'simctl', 'get_app_container', self.device['udid'], self.bundle, 'data']).strip())
            (container / 'Documents' / marker.name).write_text(run_id)
        else:
            run(['xcrun', 'devicectl', 'device', 'copy', 'to', '--device', self.device['id'],
                 '--domain-type', 'appDataContainer', '--domain-identifier', self.bundle,
                 '--source', marker, '--destination', 'Documents/' + marker.name, '--timeout', '30'], self.output / 'trigger.log', 40)

    def launch_arguments(self, run_id, pass_name):
        return ['--run-id=' + run_id, '--pass=' + pass_name] + (['--smoke'] if self.sim else [])

    def validate_measurements(self, payload, run_id, pass_name):
        return validate_results(payload, run_id, pass_name, smoke=self.sim)

    def launch(self, run_id, pass_name, hold=False):
        arguments = self.launch_arguments(run_id, pass_name) if not hold else ['--run-id=' + run_id, '--pass=' + pass_name]
        if hold:
            arguments.append('--runner-hold')
        if self.sim:
            text = run(['xcrun', 'simctl', 'launch', '--terminate-running-process', self.device['udid'], self.bundle, *arguments])
            return int(text.strip().split(':')[-1])
        path = self.output / (pass_name + '-launch.json')
        run(['xcrun', 'devicectl', 'device', 'process', 'launch', '--terminate-existing', '--device', self.device['id'],
             '--json-output', path, '--timeout', '30', self.bundle, '--', *arguments], self.output / (pass_name + '-launch.log'), 40)
        return json.loads(path.read_text())['result']['process']['processIdentifier']

    def benchmark_processes(self):
        # Resolve the exact installed bundle before selecting any process. Never
        # terminate another app just because its executable has the same name.
        apps_file = self.output / 'installed-apps.json'
        run(['xcrun', 'devicectl', 'device', 'info', 'apps', '--device', self.device['id'],
             '--json-output', apps_file, '--timeout', '20'], self.output / 'installed-apps.log', 30)
        apps = [app for app in json.loads(apps_file.read_text())['result']['apps']
                if app.get('bundleIdentifier') == self.bundle]
        if len(apps) != 1 or not apps[0].get('url', '').startswith('file:///'):
            raise ProfileError('Cannot identify the installed benchmark app safely.')
        prefix = apps[0]['url'].rstrip('/') + '/'
        processes_file = self.output / 'device-processes.json'
        run(['xcrun', 'devicectl', 'device', 'info', 'processes', '--device', self.device['id'],
             '--json-output', processes_file, '--timeout', '20'], self.output / 'device-processes.log', 30)
        return [item['processIdentifier'] for item in json.loads(processes_file.read_text())['result']['runningProcesses']
                if item.get('executable', '').startswith(prefix)]

    def stop_benchmark(self):
        for pid in self.benchmark_processes():
            run(['xcrun', 'devicectl', 'device', 'process', 'terminate', '--device', self.device['id'],
                 '--pid', str(pid), '--timeout', '20'])

    def record(self, pass_name, template, seconds):
        run_id = uuid.uuid4().hex
        if self.sim:
            self.launch(run_id, pass_name)
        else:
            self.stop_benchmark()
        trace = self.output / (pass_name + '.trace')
        recording = None
        recording_started = False
        try:
            if not self.sim:
                notification = TraceStart()
                try:
                    with (self.output / (pass_name + '-record.log')).open('w') as log:
                        recording = subprocess.Popen(['xcrun', 'xctrace', 'record', '--device', self.device['udid'],
                            '--template', template, '--instrument', 'Points of Interest', '--output', str(trace),
                            '--time-limit', f'{seconds + 150}s', '--window', f'{seconds + 150}s',
                            '--notify-tracing-started', notification.name,
                            '--launch', '--', self.bundle, *self.launch_arguments(run_id, pass_name)],
                            stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
                    deadline = time.monotonic() + 90
                    while not notification.changed():
                        if recording.poll() is not None or time.monotonic() > deadline:
                            raise ProfileError(f'Instruments did not start {template}. Check {pass_name}-record.log; approve any macOS developer-tools permission and rerun.')
                        time.sleep(0.2)
                    recording_started = True
                finally:
                    notification.close()
            print(f'{template}: running the automatic scenarios…', flush=True)
            self.trigger(run_id)
            # No device result polling during expected measurement windows.
            deadline = time.monotonic() + seconds
            while time.monotonic() < deadline:
                time.sleep(min(20, max(0, deadline - time.monotonic())))
                if recording and recording.poll() is not None:
                    raise ProfileError(f'Instruments stopped before {pass_name} finished. Partial trace retained.')
            destination = self.output / (pass_name + '-measurements.json')
            for _ in range(12):
                self.copy_from('Documents/results-' + run_id + '.json', destination)
                payload = json.loads(destination.read_text())
                if payload.get('finished'):
                    break
                if getattr(self, 'reject_early_poll', False):
                    raise ProfileError('Playback exceeded the recording budget. This run is incomplete because collecting results may have overlapped a trial; rerun with a larger --trial-budget.')
                time.sleep(10)
            self.validate_measurements(payload, run_id, pass_name)
            print(f'Saved {len(payload["rows"])} {pass_name} trials from the iPhone.' if not self.sim
                  else 'Saved simulator smoke results.', flush=True)
        except KeyboardInterrupt:
            # A second Ctrl-C must not signal the recorder twice through a shared
            # terminal process group. Explicitly stop our isolated recording job.
            if recording:
                terminate_recording(recording)
            raise
        finally:
            if recording:
                try:
                    if recording.poll() is None:
                        if recording_started:
                            finish_recording(recording, trace)
                        else:
                            terminate_recording(recording)
                finally:
                    if recording_started:
                        # Instruments owns this launch and terminates it after
                        # saving. Keep the screen awake during exports/cooldown,
                        # outside every measured recording. Never restart trials.
                        try:
                            self.launch(uuid.uuid4().hex, 'between-passes', hold=True)
                        except ProfileError as error:
                            print(f'Could not keep the benchmark screen awake: {error}', flush=True)
        if recording and recording.returncode != 0:
            raise ProfileError(f'Instruments could not finalize {trace.name} (exit {recording.returncode}). App measurements are preserved.')
        if recording:
            print(f'Exporting {trace.name} tables…', flush=True)
        return payload, export_trace(trace, self.output) if recording else None

    def interactions(self):
        print('Testing real taps, scrolling, navigation and Reduce Motion…', flush=True)
        run(self.common + ['test-without-building', '-resultBundlePath', self.output / 'Interactions.xcresult',
                          '-only-testing:PaperConfettiBenchmarksUITests'],
            self.output / 'interactions.log', 600)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--device', help='Connected physical iPhone name or UDID; automatic when exactly one is connected')
    parser.add_argument('--team', help='Apple development team ID; saved locally after a successful build/install')
    parser.add_argument('--list-devices', action='store_true')
    parser.add_argument('--simulator-smoke', action='store_true', help='Validate automation only, on the dedicated simulator; no performance claim or Instruments recordings')
    args = parser.parse_args()
    ARTIFACTS.mkdir(exist_ok=True)
    with (ARTIFACTS / 'profile.lock').open('w') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise ProfileError('Another profiling run is using the benchmark app. Let it finish first.')
        devices = []
        if not args.simulator_smoke or args.list_devices:
            inventory_file = ARTIFACTS / 'profile-devices.json'
            run(['xcrun', 'devicectl', 'list', 'devices', '--timeout', '30', '--json-output', inventory_file], timeout=40)
            devices = device_rows(json.loads(inventory_file.read_text()))
        if args.list_devices:
            for d in devices:
                if not d['simulator']:
                    print(f'{d["name"]}: {d["state"]} — {d["udid"]}')
            return
        team = None
        if args.simulator_smoke:
            import validate
            udid = validate.simulator()
            state = json.loads(run(['xcrun', 'simctl', 'list', 'devices', '--json']))['devices']
            selected = next(d for group in state.values() for d in group if d['udid'] == udid)
            if selected['state'] != 'Booted':
                run(['xcrun', 'simctl', 'boot', udid])
            run(['xcrun', 'simctl', 'bootstatus', udid, '-b'])
            device = {'name': 'PaperConfetti Example', 'id': udid, 'udid': udid, 'simulator': True}
        else:
            device = select_device(devices, args.device)
            team, settings = signing_team(args.team)
        output = ARTIFACTS / ('profile-' + dt.datetime.now(dt.timezone.utc).strftime('%Y%m%dT%H%M%SZ') + '-' + uuid.uuid4().hex[:6])
        output.mkdir()
        receipt = {'status': 'incomplete', 'started': dt.datetime.now(dt.timezone.utc).isoformat(), 'device': device,
                   'xcode': run(['xcodebuild', '-version']).strip(), 'legacy_revision': LEGACY,
                   'revision': run(['/usr/bin/git', 'rev-parse', 'HEAD']).strip(),
                   'working_tree': run(['/usr/bin/git', 'status', '--short']), 'traces': [], 'interactions': 'not run'}
        payloads = []
        write_report(output, receipt, payloads)
        print(f'Device: {device["name"]}\nResults: {output}', flush=True)
        runner = Runner(args, output, device, team)
        try:
            runner.build()
            if team:
                settings.write_text(json.dumps({'team': team}, indent=2) + '\n')
            passes = [('timing', 'Animation Hitches', 22)] if args.simulator_smoke else [
                ('timing', 'Animation Hitches', 238), ('cpu', 'Time Profiler', 120), ('memory', 'Allocations', 124)]
            for name, template, seconds in passes:
                print(f'Pass {len(payloads) + 1} of {len(passes)}: {template}', flush=True)
                try:
                    payload, trace = runner.record(name, template, seconds)
                except ProfileError as error:
                    # A recorder failure must not discard valid app measurements
                    # or prevent independent CPU/memory/interaction checks.
                    payload = saved_measurements(output, name, args.simulator_smoke)
                    if payload is None:
                        raise
                    trace = {'trace': name + '.trace', 'status': 'failed', 'error': str(error)}
                    receipt.setdefault('recording_errors', []).append(str(error))
                    print(f'Recording issue: {error} Continuing with the remaining checks.', flush=True)
                payloads.append(payload)
                if trace:
                    receipt['traces'].append(trace)
                write_report(output, receipt, payloads)
                if not args.simulator_smoke:
                    print('Cooling down for 20 seconds before the next pass…', flush=True)
                    time.sleep(20)
            runner.interactions()
            receipt['interactions'] = 'passed — real taps, toggle, scroll, navigation, stop and Reduce Motion preview'
            if receipt.get('recording_errors'):
                raise ProfileError('Measurements and interaction checks finished, but some Instruments recordings failed. See report.html.')
            receipt['status'] = 'Simulator automation check passed — not physical performance evidence' if args.simulator_smoke else 'Recordings and interaction checks complete — review traces before making performance claims'
        except (Exception, KeyboardInterrupt) as error:
            receipt['error'] = str(error) or 'Interrupted by user'
            raise
        finally:
            if not args.simulator_smoke:
                try:
                    runner.stop_benchmark()
                except ProfileError as cleanup_error:
                    receipt['cleanup_warning'] = str(cleanup_error)
            known_passes = {payload['pass'] for payload in payloads}
            for name in ('timing', 'cpu', 'memory'):
                if name not in known_passes:
                    try:
                        recovered = saved_measurements(output, name, args.simulator_smoke)
                        if recovered:
                            payloads.append(recovered)
                    except (ProfileError, ValueError, OSError) as recovery_error:
                        receipt.setdefault('recovery_errors', []).append(str(recovery_error))
            known = {t['trace'] for t in receipt['traces']}
            for partial in sorted(output.glob('*.trace')):
                if partial.name not in known:
                    receipt['traces'].append({'trace': partial.name, 'status': 'partial/unverified'})
            receipt['finished'] = dt.datetime.now(dt.timezone.utc).isoformat()
            write_report(output, receipt, payloads)
            print(f'Report: {output / "report.html"}', flush=True)


if __name__ == '__main__':
    try:
        main()
    except (ProfileError, KeyboardInterrupt) as error:
        print(f'\nProfiling stopped: {error or "interrupted"}', file=sys.stderr)
        sys.exit(1)
