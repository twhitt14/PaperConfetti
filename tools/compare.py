#!/usr/bin/env python3
"""Controlled PaperConfetti renderer/factor study. See Documentation/RENDERER_STUDY.md."""
import argparse
import datetime as dt
import hashlib
import html
import json
import math
from pathlib import Path
import statistics
import sys
import time
import uuid

import profile as p
import hitches
from run_lock import RunLock, RunLockError

MANIFEST = p.ROOT / 'Benchmarks/Study.json'


def manifest():
    data = json.loads(MANIFEST.read_text())
    cases = data['scenarios']
    names = [c['id'] for c in cases]
    if data['schema'] != 1 or len(names) != len(set(names)):
        raise p.ProfileError('Invalid study manifest')
    return cases


def select_cases(suite, only=None):
    cases = manifest()
    if only:
        ids = only.split(',')
        if len(set(ids)) != len(ids) or any(name not in {c['id'] for c in cases} for name in ids):
            raise p.ProfileError('Unknown or duplicate --only case. Use --list.')
        return [next(c for c in cases if c['id'] == name) for name in ids]
    return [c for c in cases if (suite == 'all' and 'stress' not in c['suites']) or suite in c['suites']]


def chunks(cases, maximum=4):
    # A cold-cache trial must be the first and only case in a fresh process.
    warm = [c for c in cases if c['prewarm']]
    return [warm[i:i+maximum] for i in range(0, len(warm), maximum)] + [[c] for c in cases if not c['prewarm']]


def validate(payload, run_id, phase, cases, rounds, simulator):
    if payload.get('schema') != 2 or payload.get('run_id') != run_id or payload.get('pass') != phase:
        raise p.ProfileError('Stale or incompatible study result')
    if payload.get('simulator') != simulator or not payload.get('finished') or not payload.get('success'):
        raise p.ProfileError(payload.get('error') or 'Study did not finish on the expected device')
    expected = {(c['id'], r) for c in cases for r in range(rounds)}
    rows = payload.get('rows', [])
    if len(rows) != len(expected) or {(r.get('scenario'), r.get('round')) for r in rows} != expected:
        raise p.ProfileError('Missing/duplicate study trials')
    for row in rows:
        spec = next(c for c in cases if c['id'] == row['scenario'])
        if row.get('requested_particles') != spec['count'] or not row.get('idle_after_settle'):
            raise p.ProfileError('Renderer emitted no particles or failed cleanup')
        if spec['renderer'] == 'sprite' and (row.get('sprite_particles_started') != spec['count'] or row.get('sprite_scene_updates', 0) < 1):
            raise p.ProfileError('SpriteKit never started the complete population')
        if phase != 'memory' and row.get('callback_count', 0) < 2:
            raise p.ProfileError('No usable scheduling samples')
        for key in ('duration_s', 'cpu_ms', 'footprint_end_bytes'):
            if not isinstance(row.get(key), (int, float)) or not math.isfinite(row[key]) or row[key] < 0:
                raise p.ProfileError('Missing/invalid measurement')
        if row['footprint_end_bytes'] <= 0:
            raise p.ProfileError('Process footprint measurement unavailable')
        if row['duration_s'] < (1.8 if phase == 'memory' else 5.3):
            raise p.ProfileError('Trial ended too early')
    return rows


class StudyRunner(p.Runner):
    cases = []
    rounds = 3
    reject_early_poll = True

    def launch_arguments(self, run_id, pass_name):
        result = ['--run-id=' + run_id, '--pass=' + pass_name,
                  '--study=' + ','.join(c['id'] for c in self.cases), '--study-rounds=' + str(self.rounds)]
        if self.args.visual_review:
            result.append('--visual-review')
        return result

    def validate_measurements(self, payload, run_id, pass_name):
        return validate(payload, run_id, pass_name, self.cases, self.rounds, self.sim)


def write_report(output, receipt, payloads):
    def median(rows, key):
        values = [r[key] for r in rows if isinstance(r.get(key), (int, float))]
        return statistics.median(values) if values else None
    def cell(value):
        return 'unavailable' if value is None else f'{value:.2f}' if isinstance(value, float) else html.escape(str(value))
    groups = {}
    for payload in payloads:
        for row in payload['rows']:
            # Cold-cache trials are intentionally first-use, never mixed into warm comparisons.
            if row['warmup'] and row.get('texture_prewarmed', True):
                continue
            groups.setdefault((payload['pass'], row['scenario']), []).append(row)
    summary = []
    for (phase, name), rows in groups.items():
        summary.append(dict(phase=phase, scenario=name, samples=len(rows),
            **{key: median(rows, key) for key in ('cpu_ms','setup_ms','first_callback_ms','callback_p99_ms','hitch_count','hitch_ms','max_hitch_ms','launch_hitch_ms','flight_hitch_ms')},
            settled_mib=median(rows,'footprint_end_bytes') / 1048576,
            peak_sampled_mib=(median(rows,'footprint_peak_sampled_bytes') / 1048576 if median(rows,'footprint_peak_sampled_bytes') is not None else None),
            first_settled_mib=rows[0]['footprint_end_bytes'] / 1048576,
            last_settled_mib=rows[-1]['footprint_end_bytes'] / 1048576))
    receipt['summary'] = summary
    (output / 'report.json').write_text(json.dumps(receipt, indent=2) + '\n')
    keys = ['phase','scenario','samples','cpu_ms','setup_ms','callback_p99_ms','hitch_count','hitch_ms','max_hitch_ms','launch_hitch_ms','flight_hitch_ms','settled_mib']
    rows = ''.join('<tr>' + ''.join(f'<td>{cell(row[k])}</td>' for k in keys) + '</tr>' for row in summary)
    links = ''
    for recording in receipt.get('recordings', []):
        directory, phase = recording['directory'], recording['phase']
        trace = f'{directory}/{phase}.trace'
        trace_link = (f'<a href="{html.escape(trace)}">Instruments trace</a>' if (output / trace).exists()
                      else 'No instrument trace available')
        evidence = recording.get('hitches', {})
        links += (f'<li><a href="{html.escape(directory)}/{html.escape(phase)}-measurements.json">{html.escape(directory)}</a> — '
                  f'{html.escape(evidence.get("status", "unavailable"))}: {html.escape(evidence.get("reason", ""))} {trace_link}</li>')
    memory = ''.join(f'<li>{cell(r["scenario"])}: first settled {r["first_settled_mib"]:.2f} → last {r["last_settled_mib"]:.2f} MiB; sampled peak median {r["peak_sampled_mib"]:.2f} MiB.</li>' for r in summary if r['phase']=='memory')
    audits = {}
    for payload in payloads:
        for row in payload['rows']:
            audits.setdefault(row['scenario'], row.get('audit', {}))
    audit_rows = ''
    for name, audit in audits.items():
        textures = audit.get('textures', [])
        if not textures:
            continue
        values = [name, len(textures), audit.get('texture_bytes'),
                  max(t['width_px'] for t in textures), max(t['height_px'] for t in textures),
                  statistics.mean(t['nontransparent_fraction'] for t in textures),
                  audit.get('minimum_track_samples'), audit.get('maximum_track_samples'),
                  audit.get('position_interpolation_max_error_points'), audit.get('opacity_interpolation_max_error'),
                  audit.get('native_pose_texture_count', 0), audit.get('native_pose_texture_bytes', 0), audit.get('grouping_max_error_points')]
        audit_rows += '<tr>' + ''.join(f'<td>{cell(v)}</td>' for v in values) + '</tr>'
    (output / 'report.html').write_text(f'''<!doctype html><meta charset="utf-8"><title>PaperConfetti renderer study</title>
<style>body{{font:15px system-ui;background:#111827;color:#e5e7eb;margin:32px}}a{{color:#67e8f9}}td,th{{text-align:left;padding:10px;border-bottom:1px solid #374151;white-space:nowrap}}table{{border-collapse:collapse}}.table{{overflow:auto}}p{{max-width:1100px;line-height:1.6}}</style>
<h1>Renderer and shape study</h1><p>{html.escape(receipt['status'])}</p><p>{html.escape(receipt.get('error',''))}</p>
<p>Warm medians exclude round zero. Cold-textures results are explicitly first-use trials from fresh processes. A one-round smoke run intentionally has no warm summary. Raw measurements retain every trial, texture dimensions/alpha coverage, requested particle counts and interpolation accuracy.</p>
<p>CPU is whole-process CPU over the complete trial. Setup includes synchronous particle preparation/animation submission, not the later Core Animation commit. Callback p99 is scheduling, <strong>not rendered FPS</strong>. Actual hitch fields require complete, matching Animation Hitches + Points of Interest exports for this process; absent evidence stays unavailable. Hitch duration is unioned within each trial, with launch = first 500ms. It is not Apple's animation-active hitch time ratio. CPU and memory passes run separately; don't compare their CPU with the timing pass.</p>
<p>The parabolic-v4 candidates give each piece its own seeded rise/fall timing, shape, color and spin. Native particles use one emitter layer per piece; SpriteKit uses a moving node and finite emitter per piece. Both offer flat and independent 3D tilt. Eight cached native starting poses add bitmap memory, listed separately. The shared-flight diagnostic trades individual timing for fewer groups. The released PaperConfetti baseline retains its original physics, so this is an appearance/performance comparison, not identical output. Loads above 2,000 use multiple seeded batches in the benchmark only. Opaque-proxy is diagnostic rectangles. Compare repeated sessions on the same physical device and thermal state.</p>
<div class="table"><table><tr>{''.join(f'<th>{k}</th>' for k in keys)}</tr>{rows}</table></div>
<h2>Memory trends</h2><ul>{memory}</ul><p>Whole-process footprint, including framework caches. Use Allocations to attribute retained objects. Cancellation and natural completion are both checked.</p>
<h2>Texture and trajectory audit</h2><p>First trial per scenario; computed outside timing. Dimensions and bytes describe CPU CGImage backing, not total GPU allocations. Alpha fraction is nontransparent pixels divided by bitmap area. Padding changes that denominator. Error compares sampled/interpolated position and opacity with the underlying physics. CAEmitterLayer audits interpolation and any diagnostic grouping deviation from the new individual paths; native birth offsets, drift and tilt are excluded. SpriteKit evaluates the same analytic flight on each scene update: its interpolation fields are unavailable, not measured zeros. Scene updates/started-particle checks prove scheduling, not actual GPU frame delivery.</p>
<div class="table"><table><tr><th>Scenario</th><th>Images</th><th>Bytes</th><th>Max width px</th><th>Max height px</th><th>Nonzero-alpha fraction</th><th>Min samples</th><th>Max samples</th><th>Position error pt</th><th>Opacity error</th><th>Extra pose images</th><th>Pose bytes</th><th>Grouping error pt</th></tr>{audit_rows}</table></div>
<h2>Recordings</h2><ul>{links}</ul><p>Every trace is a bounded chunk. Open it in Instruments, locate “Renderer study” in Points of Interest, then inspect the Animation Hitches, commit, render-server and GPU tracks. Inspect render costs even if process CPU is low.</p>
<p><a href="report.json">Full provenance and summary</a> · <a href="Study.json">Exact scenario matrix</a></p>''')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--suite', choices=['renderers','factors','shapes','stress','all'], default='renderers')
    parser.add_argument('--only', help='Comma-separated scenario IDs; use --list')
    parser.add_argument('--phase', choices=['all','timing','cpu','memory'], default='all')
    parser.add_argument('--rounds', type=int, choices=range(1,7), default=3, help='Includes one warm-up; default 3. Memory uses at least 6 cycles.')
    parser.add_argument('--trial-budget', type=int, choices=range(9,31), default=9, help='Seconds reserved per timing/CPU trial including untimed audit; default 9')
    parser.add_argument('--device'); parser.add_argument('--team')
    parser.add_argument('--list', action='store_true')
    parser.add_argument('--simulator-smoke', action='store_true')
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument('--visual-review', action='store_true', help='Install/open hands-on replay mode, without Instruments')
    mode.add_argument('--collect-visual', action='store_true', help='Copy saved subjective observations from the installed app, without rebuilding')
    parser.add_argument('--restart', action='store_true', help='Stop an existing repository-owned run before starting this one')
    mode.add_argument('--stop', action='store_true', help='Stop the active comparison without starting another')
    args = parser.parse_args()
    if args.suite == 'stress': args.trial_budget = max(15, args.trial_budget)
    cases = [] if args.stop else select_cases(args.suite, args.only)
    if args.visual_review and not args.only and args.suite == 'renderers':
        cases = select_cases('all', 'emitter-3d-720,emitter-720,sprite-3d-720,sprite-atlas-3d-720,sprite-720,sprite-atlas-720,layers-720,adaptive-keyframes,paper-720')
    if args.list:
        for c in cases:
            print(f'{c["id"]:24} {c["renderer"]:8} {c["count"]:3} particles; {c["shapes"]}; {c["size"]}pt; texture scale {c["textureScale"] or "device"}')
        return
    p.ARTIFACTS.mkdir(exist_ok=True)
    with RunLock(p.ROOT, restart=args.restart or args.stop, interactive=args.visual_review,
                 mode='visual review' if args.visual_review else 'comparison') as lock:
        if args.stop:
            print('Comparison stopped. Completed results are preserved.' if lock.replaced else 'No comparison is running.', flush=True)
            return
        team = None
        if args.simulator_smoke:
            import validate as validator
            udid = validator.simulator()
            devices = json.loads(p.run(['xcrun','simctl','list','devices','--json']))['devices']
            selected = next(d for group in devices.values() for d in group if d['udid']==udid)
            if selected['state'] != 'Booted': p.run(['xcrun','simctl','boot',udid])
            p.run(['xcrun','simctl','bootstatus',udid,'-b'])
            device = {'name':'PaperConfetti Example','id':udid,'udid':udid,'simulator':True}
        else:
            inventory = p.ARTIFACTS / 'study-devices.json'
            p.run(['xcrun','devicectl','list','devices','--timeout','30','--json-output',inventory], timeout=40)
            device = p.select_device(p.device_rows(json.loads(inventory.read_text())), args.device)
            team, settings = p.signing_team(args.team)
        output = p.ARTIFACTS / ('study-' + dt.datetime.now(dt.timezone.utc).strftime('%Y%m%dT%H%M%SZ') + '-' + uuid.uuid4().hex[:6])
        output.mkdir()
        (output / 'Study.json').write_bytes(MANIFEST.read_bytes())
        receipt = {'status':'incomplete','device':device,'started':dt.datetime.now(dt.timezone.utc).isoformat(),
                   'xcode':p.run(['xcodebuild','-version']).strip(), 'revision':p.run(['/usr/bin/git','rev-parse','HEAD']).strip(),
                   'working_tree':p.run(['/usr/bin/git','status','--short']),
                   'source_sha256':{str(f.relative_to(p.ROOT)):hashlib.sha256(f.read_bytes()).hexdigest()
                       for folder in ('Benchmarks/App','Benchmarks/Motion','Sources/PaperConfetti','tools') for f in (p.ROOT / folder).glob('*.swift' if folder!='tools' else '*.py')},
                   'manifest_sha256':hashlib.sha256(MANIFEST.read_bytes()).hexdigest(), 'selected':[c['id'] for c in cases], 'recordings':[]}
        payloads = []
        runner = StudyRunner(args, output, device, team)
        runner.cases = cases
        write_report(output, receipt, payloads)
        print(f'Results: {output}', flush=True)
        keep_open = False
        try:
            if args.collect_visual:
                runner.copy_from('Documents/visual-observations.jsonl', output / 'visual-observations.jsonl')
                receipt['status'] = 'Subjective observations copied; not performance measurements'
                return
            runner.build()
            if team: settings.write_text(json.dumps({'team':team},indent=2)+'\n')
            if args.visual_review:
                runner.launch(uuid.uuid4().hex, 'visual')
                print('Visual Review is open on your device. Use Replay, Shuffle, Next, or the Experiment menu. No performance recording is running.', flush=True)
                receipt['status'] = 'Visual review opened — replay, switch variants, and record Smooth/Launch hitch/Flight hitch'
                keep_open = True
                return
            if args.simulator_smoke and not args.only:
                cases = [c for c in cases if c['id'] in ('control','paper-720','layers-720','emitter-720','emitter-3d-720','sprite-720','sprite-3d-720','sprite-atlas-720','sprite-atlas-3d-720')]
            phases = (['timing'] if args.simulator_smoke else ['timing','cpu','memory']) if args.phase=='all' else [args.phase]
            for phase in phases:
                phase_cases = cases
                # Memory endurance focuses on renderer paths, not every texture experiment.
                if phase=='memory' and not args.only and args.suite != 'stress':
                    phase_cases = [c for c in manifest() if c['id'] in ('paper-720','layers-720','emitter-720','emitter-3d-720','sprite-720','sprite-3d-720','sprite-atlas-720','sprite-atlas-3d-720')]
                chunk_size = 2 if phase == 'memory' else max(1, min(4, 85 // (args.rounds * args.trial_budget)))
                for index, selected in enumerate(chunks(phase_cases, maximum=chunk_size)):
                    repetitions = args.rounds if not selected[0]['prewarm'] else 1
                    for cold_repeat in range(repetitions):
                        rounds = (2 if phase == 'memory' else 1) if args.simulator_smoke else 1 if not selected[0]['prewarm'] else max(6,args.rounds) if phase=='memory' else args.rounds
                        part = output / f'{phase}-{index:02}-{cold_repeat:02}'; part.mkdir()
                        runner.output = part; runner.cases = selected; runner.rounds = rounds
                        seconds = math.ceil(2 + len(selected) * rounds * (args.trial_budget if phase!='memory' else 7))
                        print(f'{phase}: {", ".join(c["id"] for c in selected)} ({rounds} rounds)', flush=True)
                        entry = {'directory':part.name,'phase':phase,'scenarios':[c['id'] for c in selected]}
                        receipt['recordings'].append(entry)
                        try:
                            payload, trace = runner.record(phase, {'timing':'Animation Hitches','cpu':'Time Profiler','memory':'Allocations'}[phase], seconds)
                        except p.ProfileError as error:
                            entry['error'] = str(error)
                            saved = part / (phase+'-measurements.json')
                            if not saved.exists(): raise
                            payload = json.loads(saved.read_text()); identity=payload.get('run_id','')
                            marker = part / ('start-'+identity)
                            if not marker.exists() or marker.read_text()!=identity: raise
                            runner.validate_measurements(payload,identity,phase)
                            trace = None
                        entry['trace'] = trace
                        entry['hitches'] = hitches.from_exports(part,trace or {},payload) if phase=='timing' else {'status':'not collected in this pass'}
                        if entry['hitches']['status']=='available':
                            for row in payload['rows']:
                                row.update(next(r for r in entry['hitches']['rows'] if (r['scenario'],r['round'])==(row['scenario'],row['round'])))
                        payloads.append(payload)
                        (part / 'attributed-measurements.json').write_text(json.dumps(payload,indent=2)+'\n')
                        write_report(output,receipt,payloads)
                        if not args.simulator_smoke:
                            print('Cooling for 20 seconds…',flush=True); time.sleep(20)
            runner.output = output
            runner.interactions()
            receipt['interactions'] = 'passed'
            incomplete = any(r.get('error') or (r['phase']=='timing' and r['hitches']['status']!='available') for r in receipt['recordings'])
            receipt['status'] = ('Simulator automation passed — not device performance evidence' if args.simulator_smoke else
                                 'App measurements complete; some trace evidence unavailable — see recordings' if incomplete else 'Requested recordings and interaction checks complete; see each pass for available metrics')
        except (Exception, KeyboardInterrupt) as error:
            receipt['error']=str(error) or 'Interrupted'; raise
        finally:
            if not runner.sim and not keep_open and not args.collect_visual:
                try: runner.stop_benchmark()
                except p.ProfileError as error: receipt['cleanup_warning']=str(error)
            receipt['finished']=dt.datetime.now(dt.timezone.utc).isoformat()
            write_report(output,receipt,payloads)
            print(f'Report: {output / "report.html"}',flush=True)


if __name__=='__main__':
    try: main()
    except (p.ProfileError, RunLockError, KeyboardInterrupt) as error:
        print(f'Comparison stopped: {str(error) or "interrupted"}',file=sys.stderr); sys.exit(1)
