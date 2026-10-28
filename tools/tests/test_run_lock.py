import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import run_lock as lock


class RunLockTests(unittest.TestCase):
    def identity(self, root, pid=98765):
        return {'pid': pid, 'started': 'Wed Oct 28 00:00:00 2026',
                'command': f'/usr/bin/python3 {root}/tools/compare.py --suite all'}

    def test_acquires_stale_unlocked_receipt_without_signalling(self):
        with tempfile.TemporaryDirectory() as d, patch.object(lock, 'process_identity', return_value=self.identity(d)), patch.object(lock.os, 'kill') as kill:
            root=Path(d); path=root/'.artifacts/profile.lock'; path.parent.mkdir()
            path.write_text('{"pid": 1}')
            with lock.RunLock(root) as owned:
                self.assertFalse(owned.replaced)
                self.assertEqual(json.loads(path.read_text())['mode'], 'comparison')
            kill.assert_not_called()

    def test_declining_keeps_owner_and_lock_intact(self):
        with tempfile.TemporaryDirectory() as d, patch.object(lock, 'process_identity', return_value=self.identity(d)), patch.object(lock.sys.stdin, 'isatty', return_value=True), patch('builtins.input', return_value='n'), patch.object(lock.os, 'kill') as kill:
            with lock.RunLock(d) as owner:
                before=owner.path.read_text()
                with self.assertRaisesRegex(lock.RunLockError, 'left running'):
                    with lock.RunLock(d, interactive=True): pass
                self.assertEqual(owner.path.read_text(),before)
                with self.assertRaisesRegex(lock.RunLockError, 'already running'):
                    with lock.RunLock(d): pass
            kill.assert_not_called()

    def test_yes_waits_for_owner_cleanup_then_takes_same_lock(self):
        with tempfile.TemporaryDirectory() as d, patch.object(lock, 'process_identity', return_value=self.identity(d)), patch.object(lock.sys.stdin, 'isatty', return_value=True), patch('builtins.input', return_value='yes'), patch.object(lock, 'verified_owner', return_value=98765):
            owner=lock.RunLock(d).__enter__(); inode=owner.path.stat().st_ino
            with patch.object(lock.os, 'kill', side_effect=lambda *_: owner.__exit__()) as kill:
                with lock.RunLock(d, interactive=True, mode='visual review') as replacement:
                    self.assertTrue(replacement.replaced)
                    self.assertEqual(replacement.path.stat().st_ino,inode)
                    self.assertEqual(json.loads(replacement.path.read_text())['mode'],'visual review')
                kill.assert_called_once_with(98765,lock.signal.SIGINT)

    def test_changed_owner_while_prompting_is_not_signalled(self):
        with tempfile.TemporaryDirectory() as d, patch.object(lock, 'process_identity', return_value=self.identity(d)), patch.object(lock.sys.stdin, 'isatty', return_value=True), patch.object(lock.os, 'kill') as kill:
            with lock.RunLock(d) as owner:
                def change_owner(_):
                    owner.file.seek(0); owner.file.truncate()
                    json.dump({**self.identity(d), 'pid': 98766}, owner.file); owner.file.flush()
                    return 'yes'
                with patch('builtins.input', side_effect=change_owner), self.assertRaisesRegex(lock.RunLockError, 'different comparison'):
                    with lock.RunLock(d, interactive=True): pass
            kill.assert_not_called()

    def test_noninteractive_requires_explicit_restart(self):
        with tempfile.TemporaryDirectory() as d, patch.object(lock, 'process_identity', return_value=self.identity(d)), patch.object(lock.sys.stdin, 'isatty', return_value=False), patch.object(lock.os, 'kill') as kill:
            with lock.RunLock(d):
                with self.assertRaisesRegex(lock.RunLockError, '--restart'):
                    with lock.RunLock(d, interactive=True): pass
            kill.assert_not_called()

    def test_stubborn_owner_never_allows_overlapping_run(self):
        with tempfile.TemporaryDirectory() as d, patch.object(lock, 'process_identity', return_value=self.identity(d)), patch.object(lock, 'verified_owner', return_value=98765), patch.object(lock.os, 'kill'):
            with lock.RunLock(d):
                with self.assertRaisesRegex(lock.RunLockError, 'still cleaning up'):
                    with lock.RunLock(d, restart=True, timeout=0): pass

    def test_pid_reuse_unrelated_process_and_other_repo_are_not_signalled(self):
        root=Path('/tmp/paper-confetti'); owner=self.identity(root)
        with patch.object(lock, 'process_identity', return_value=owner):
            self.assertEqual(lock.verified_owner(owner,root),98765)
        for change in [{'started':'new process'}, {'command':'/usr/bin/python3 /tmp/other/tools/compare.py'},
                       {'command':'/bin/sh /tmp/paper-confetti/tools/compare.py'},
                       {'command':'/usr/bin/python3 /tmp/paper-confetti/tools/unrelated.py'}]:
            current={**owner,**change}
            # Matching receipts still cannot authorize unrelated commands.
            receipt=owner if 'started' in change else current
            with patch.object(lock, 'process_identity', return_value=current), self.assertRaises(lock.RunLockError):
                lock.verified_owner(receipt,root)
        with self.assertRaises(lock.RunLockError): lock.verified_owner({**owner,'pid':os.getpid()},root)

    def test_relative_script_requires_the_correct_actual_working_directory(self):
        root=Path('/tmp/paper-confetti');owner={**self.identity(root),'command':'python3 tools/compare.py --suite all'}
        with patch.object(lock, 'process_identity', return_value=owner), patch.object(lock.subprocess,'run',return_value=Mock(stdout='p98765\nn/tmp/paper-confetti\n')):
            self.assertEqual(lock.verified_owner(owner,root),98765)
        with patch.object(lock, 'process_identity', return_value=owner), patch.object(lock.subprocess,'run',return_value=Mock(stdout='p98765\nn/tmp/other\n')), self.assertRaises(lock.RunLockError):
            lock.verified_owner(owner,root)

if __name__=='__main__': unittest.main()
