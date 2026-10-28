#!/usr/bin/env python3
"""Install the article comparison on iPhone, or record it on the dedicated simulator.
Screen recordings illustrate appearance; they are never benchmark measurements.
"""
import argparse
import datetime as dt
import json
from pathlib import Path
import signal
import subprocess
import time
import uuid
import profile as p
from run_lock import RunLock

CASES = ['legacy-180', 'native-180', 'legacy-720', 'native-720',
         'legacy-1800', 'native-1800', 'festive-1800', 'festive-5760']

class ArticleRunner(p.Runner):
    def launch_arguments(self, run_id, pass_name):
        result = ['--article-demo', '--article-run-id=' + run_id]
        if self.args.case: result.append('--article-case=' + self.args.case)
        if self.sim: result.append('--article-autostart')
        return result

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--simulator', dest='simulator_smoke', action='store_true')
    parser.add_argument('--device')
    parser.add_argument('--team')
    parser.add_argument('--case', choices=CASES)
    parser.add_argument('--skip-build', action='store_true', help='Reuse the current benchmark build; rebuild after source edits')
    args = parser.parse_args()
    p.ARTIFACTS.mkdir(exist_ok=True)
    with RunLock(p.ROOT, mode='article recording'):
        output = p.ARTIFACTS / ('article-' + dt.datetime.now(dt.timezone.utc).strftime('%Y%m%dT%H%M%SZ') + '-' + uuid.uuid4().hex[:6])
        output.mkdir()
        team = None
        if args.simulator_smoke:
            import validate
            udid = validate.simulator()
            inventory = json.loads(p.run(['xcrun','simctl','list','devices','--json']))
            device = next(d for ds in inventory['devices'].values() for d in ds if d['udid'] == udid)
            if device['state'] != 'Booted': p.run(['xcrun','simctl','boot',udid])
            p.run(['xcrun','simctl','bootstatus',udid,'-b'])
            device = {'name':'PaperConfetti Example','udid':udid,'id':udid,'simulator':True}
        else:
            inventory = output/'devices.json'
            p.run(['xcrun','devicectl','list','devices','--timeout','30','--json-output',inventory],timeout=40)
            device = p.select_device(p.device_rows(json.loads(inventory.read_text())),args.device)
            team, settings = p.signing_team(args.team)
        runner = ArticleRunner(args,output,device,team)
        if not args.skip_build:
            runner.build()
            if team: settings.write_text(json.dumps({'team':team},indent=2)+'\n')
        receipt = {'purpose':'Editorial visual demonstration, not a performance measurement',
                   'revision':p.run(['/usr/bin/git','rev-parse','HEAD']).strip(),
                   'dirty':bool(p.run(['/usr/bin/git','status','--porcelain']).strip()),
                   'legacy_revision':p.LEGACY, 'simulator':runner.sim,
                   'cases':[args.case] if args.case else CASES,
                   'xcode':p.run(['xcodebuild','-version']).strip()}
        run_id = uuid.uuid4().hex
        runner.launch(run_id,'article')
        if not runner.sim:
            receipt['status']='Opened on iPhone; recording requires the owner to start screen recording and tap Start comparison.'
            print('Ready on your iPhone. Start Screen Recording in Control Center, return to the app, then tap Start comparison. The full sequence takes about 72 seconds. Stop cancels it; Start replays it. Record without Instruments, Low Power Mode, or Reduce Motion. Use a Focus to hide personal notifications.',flush=True)
        else:
            movie=output/'comparison.mp4'
            recording=None
            with (output/'record.log').open('w') as log:
                try:
                    recording=subprocess.Popen(['xcrun','simctl','io',device['udid'],'recordVideo','--codec=h264',str(movie)],stdout=log,stderr=log)
                    deadline=time.monotonic()+10
                    while 'Recording started' not in (output/'record.log').read_text():
                        if recording.poll() is not None or time.monotonic()>deadline: raise p.ProfileError('Screen recorder did not start')
                        time.sleep(0.05)
                    container=Path(p.run(['xcrun','simctl','get_app_container',device['udid'],runner.bundle,'data']).strip())
                    deadline=time.monotonic()+240
                    print(f'Recording {len(receipt["cases"])} comparison clips…',flush=True)
                    while time.monotonic()<deadline:
                        try:
                            payload=json.loads((container/'Documents/article-session.json').read_text())
                        except (FileNotFoundError,json.JSONDecodeError):
                            payload={}
                        if payload.get('run_id')==run_id and payload.get('finished'):
                            if not payload.get('success'): raise p.ProfileError(payload.get('status','Demo stopped'))
                            if [c['id'] for c in payload['clips']] != receipt['cases']: raise p.ProfileError('Incomplete clip sequence')
                            receipt['playback']=payload
                            time.sleep(1)
                            break
                        if recording.poll() is not None: raise p.ProfileError('Screen recorder stopped unexpectedly')
                        time.sleep(0.25)
                    else: raise p.ProfileError('The comparison did not finish; recording retained')
                finally:
                    if recording and recording.poll() is None:
                        recording.send_signal(signal.SIGINT);recording.wait(timeout=20)
            p.run(['xcrun','simctl','io',device['udid'],'screenshot',output/'after.png'])
            receipt['status']='Simulator movie captured; inspect for completed sequence. Not physical-device evidence.'
        (output/'receipt.json').write_text(json.dumps(receipt,indent=2)+'\n')
        print('Article recording output:',output,flush=True)

if __name__=='__main__':
    try: main()
    except (p.ProfileError,KeyboardInterrupt) as error: raise SystemExit(str(error) or 'Recording stopped')
