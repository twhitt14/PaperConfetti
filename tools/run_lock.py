"""One repository-owned profiling runner; explicit, verified stop/restart handoff."""
import fcntl
import json
import os
from pathlib import Path
import shlex
import signal
import subprocess
import sys
import time


class RunLockError(RuntimeError):
    pass


def process_identity(pid):
    def ps(field):
        result = subprocess.run(['/bin/ps', '-p', str(pid), '-o', field + '='],
                                text=True, capture_output=True, timeout=5)
        return result.stdout.strip() if result.returncode == 0 else ''
    return {'pid': pid, 'started': ps('lstart'), 'command': ps('command')}


def verified_owner(owner, root):
    """Do not signal a reused PID, a shell, or any unrelated Python process."""
    root = Path(root).resolve()
    pid = owner.get('pid')
    if not isinstance(pid, int) or pid <= 1 or pid == os.getpid():
        raise RunLockError('The running comparison could not be identified safely. Stop it in its original terminal with Control-C.')
    current = process_identity(pid)
    if not current['started'] or any(current[k] != owner.get(k) for k in ('started', 'command')):
        raise RunLockError('The comparison process changed. No process was stopped; try again.')
    try:
        arguments = shlex.split(current['command'])
        python = Path(arguments[0]).name.startswith('python')
        script = next(a for a in arguments[1:] if not a.startswith('-'))
        if not Path(script).is_absolute():
            result = subprocess.run(['/usr/sbin/lsof', '-a', '-p', str(pid), '-d', 'cwd', '-Fn'],
                                    capture_output=True, text=True, timeout=5, check=True)
            cwd = next(line[1:] for line in result.stdout.splitlines() if line.startswith('n'))
            script = str(Path(cwd) / script)
        allowed = {root / 'tools/compare.py', root / 'tools/profile.py'}
        if not python or Path(script).resolve() not in allowed:
            raise ValueError('Not this repository\'s comparison runner')
    except (ValueError, IndexError, StopIteration, subprocess.SubprocessError) as error:
        raise RunLockError('The lock belongs to an unrecognized process. No process was stopped.') from error
    return pid


class RunLock:
    def __init__(self, root, *, restart=False, interactive=False, mode='comparison', timeout=120):
        self.root = Path(root).resolve()
        self.path = self.root / '.artifacts/profile.lock'
        self.restart, self.interactive, self.mode, self.timeout = restart, interactive, mode, timeout
        self.file = None
        self.replaced = False

    def try_lock(self):
        try:
            fcntl.flock(self.file, fcntl.LOCK_EX | fcntl.LOCK_NB)
            return True
        except BlockingIOError:
            return False

    def owner(self):
        # Another owner can be flushing its small receipt immediately after acquiring the lock.
        for _ in range(10):
            self.file.seek(0)
            try:
                owner = json.load(self.file)
                if isinstance(owner, dict):
                    return owner
            except (ValueError, OSError):
                pass
            time.sleep(0.1)
        raise RunLockError('An older comparison is running without a process receipt. Stop it in its original terminal with Control-C, then rerun this command.')

    def __enter__(self):
        self.path.parent.mkdir(parents=True, exist_ok=True)
        # Never unlink/truncate a held lock: contenders must wait on the same inode.
        self.file = self.path.open('a+')
        try:
            if not self.try_lock():
                owner = self.owner()
                if not self.restart:
                    if not self.interactive or not sys.stdin.isatty():
                        raise RunLockError('A comparison is already running. Use --restart to stop it and open a fresh session, or --stop to stop it only.')
                    print('A PaperConfetti comparison is already running.\nCompleted results will be kept; the current recording may be incomplete.', flush=True)
                    try:
                        answer = input('Stop it and open Visual Review? [y/N] ').strip().lower()
                    except EOFError:
                        answer = ''
                    if answer not in ('y', 'yes'):
                        raise RunLockError('Existing comparison left running. Nothing was changed.')
                # It may have finished while the user read the prompt.
                if not self.try_lock():
                    if self.owner() != owner:
                        raise RunLockError('A different comparison took over while waiting. No process was stopped; run the command again.')
                    pid = verified_owner(owner, self.root)
                    print('Stopping the existing comparison and its recorder…', flush=True)
                    try:
                        os.kill(pid, signal.SIGINT)
                    except ProcessLookupError:
                        pass
                    deadline = time.monotonic() + self.timeout
                    while not self.try_lock():
                        if time.monotonic() >= deadline:
                            raise RunLockError('The previous comparison is still cleaning up. No second run was started. Wait briefly, then rerun with --restart.')
                        time.sleep(0.25)
                    self.replaced = True
            identity = process_identity(os.getpid())
            identity['mode'] = self.mode
            self.file.seek(0); self.file.truncate()
            json.dump(identity, self.file); self.file.flush()
            return self
        except BaseException:
            self.file.close(); self.file = None
            raise

    def __exit__(self, *_):
        if self.file:
            fcntl.flock(self.file, fcntl.LOCK_UN)
            self.file.close(); self.file = None
