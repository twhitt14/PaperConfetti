import importlib.util
import json
from pathlib import Path
import tempfile
import subprocess
import unittest
from unittest.mock import patch, Mock

SPEC = importlib.util.spec_from_file_location('profile_suite', Path(__file__).resolve().parents[1] / 'profile.py')
p = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(p)


class ProfileTests(unittest.TestCase):
    def phone(self, name='Phone', **changes):
        value = {'name': name, 'id': name, 'udid': 'udid-' + name, 'kind': 'iPhone', 'state': 'connected', 'simulator': False}
        value.update(changes)
        return value

    def test_device_selection_never_uses_simulator_offline_or_watch(self):
        rows = [self.phone('Sim', simulator=True), self.phone('Old', state='unavailable'), self.phone('Watch', kind='AppleWatch')]
        with self.assertRaises(p.ProfileError): p.select_device(rows)
        rows.append(self.phone())
        self.assertEqual(p.select_device(rows)['name'], 'Phone')

    def test_multiple_devices_require_choice(self):
        rows = [self.phone('A'), self.phone('B')]
        with self.assertRaises(p.ProfileError): p.select_device(rows)
        self.assertEqual(p.select_device(rows, 'udid-B')['name'], 'B')
        with self.assertRaises(p.ProfileError): p.select_device(rows, 'missing')

    def test_old_and_new_devicectl_schemas(self):
        old = {'identifier': 'A', 'hardwareProperties': {'udid': 'u', 'deviceType': 'iPhone'},
               'deviceProperties': {'name': 'P'}, 'connectionProperties': {'tunnelState': 'connected'}}
        new = {'identifier': 'A', 'properties': {'hardware': old['hardwareProperties'], 'state': {'name': 'P'},
                                              'connection': {'state': 'connected'}}}
        self.assertEqual(p.device_rows({'result': {'devices': [old]}}), p.device_rows({'result': {'devices': [new]}}))

    def test_signing_uses_certificate_team_not_developer_display_id(self):
        fingerprint = 'A' * 40
        identity = f'1) {fingerprint} "Apple Development: Developer (PERSONAL01)"'
        certificate = '-----BEGIN CERTIFICATE-----\nTEST\n-----END CERTIFICATE-----'
        metadata = 'subject=CN=Apple Development: Developer (PERSONAL01),OU=TEAMABCDE1,O=Company\nsha1 Fingerprint=' + ':'.join(['AA'] * 20)
        with tempfile.TemporaryDirectory() as temp, patch.object(p, 'ARTIFACTS', Path(temp)), \
             patch.object(p, 'run', side_effect=[identity, certificate]), \
             patch.object(p.subprocess, 'check_output', return_value=metadata):
            self.assertEqual(p.signing_team(None)[0], 'TEAMABCDE1')

    def payload(self):
        return {'run_id': 'r', 'pass': 'timing', 'finished': True, 'success': True, 'simulator': True,
                'rows': [{'scenario': name, 'round': 0, 'callback_count': 100} for name in p.SCENARIOS[:3]]}

    def test_rejects_stale_missing_duplicate_or_noop_results(self):
        self.assertEqual(len(p.validate_results(self.payload(), 'r', 'timing', True)), 3)
        for key, value in [('run_id', 'stale'), ('success', False), ('finished', False), ('simulator', False)]:
            bad = self.payload(); bad[key] = value
            with self.subTest(key=key), self.assertRaises(p.ProfileError): p.validate_results(bad, 'r', 'timing', True)
        for mutate in [lambda rows: rows.pop(), lambda rows: rows.append(rows[0]),
                       lambda rows: rows[0].update(callback_count=0),
                       lambda rows: rows[1].update(paper_active_after_settle=True)]:
            bad = self.payload(); mutate(bad['rows'])
            with self.assertRaises(p.ProfileError): p.validate_results(bad, 'r', 'timing', True)

    def test_slow_finalization_is_not_killed_at_old_90_second_limit(self):
        process = Mock(returncode=0)
        process.poll.side_effect = [None, None, None, 0]
        process.wait.side_effect = [subprocess.TimeoutExpired('xctrace', 20), 0]
        with patch.object(p.time, 'monotonic', side_effect=[0, 0, 100, 100]):
            p.finish_recording(process, Path('timing.trace'))
        process.terminate.assert_not_called()
        process.kill.assert_not_called()
        process.send_signal.assert_called_once_with(p.signal.SIGINT)

    def test_unresponsive_recorder_has_bounded_cleanup(self):
        process = Mock(returncode=-15)
        process.poll.return_value = None
        with patch.object(p.time, 'monotonic', side_effect=[0, 901]), self.assertRaises(p.ProfileError):
            p.finish_recording(process, Path('timing.trace'))
        process.terminate.assert_called_once()

    def test_interrupt_during_finalization_stops_our_recorder(self):
        process = Mock()
        process.poll.return_value = None
        process.wait.side_effect = [KeyboardInterrupt(), 0]
        with self.assertRaises(KeyboardInterrupt):
            p.finish_recording(process, Path('timing.trace'))
        process.terminate.assert_called_once()

    def test_samples_survive_recording_failure_but_require_matching_start_receipt(self):
        with tempfile.TemporaryDirectory() as temp:
            output = Path(temp)
            (output / 'timing-measurements.json').write_text(json.dumps(self.payload()))
            with self.assertRaises(p.ProfileError): p.saved_measurements(output, 'timing', True)
            (output / 'start-r').write_text('different')
            with self.assertRaises(p.ProfileError): p.saved_measurements(output, 'timing', True)
            (output / 'start-r').write_text('r')
            self.assertEqual(p.saved_measurements(output, 'timing', True), self.payload())
            self.assertIsNone(p.saved_measurements(output, 'memory', True))

    def test_cleanup_selects_only_the_exact_installed_benchmark_bundle(self):
        runner = p.Runner(Mock(simulator_smoke=False), Path('/tmp'), self.phone(), 'TEAMABCDE1')
        apps = {'result': {'apps': [
            {'bundleIdentifier': runner.bundle, 'url': 'file:///apps/ours.app/'},
            {'bundleIdentifier': 'another.app', 'url': 'file:///apps/other.app/'}]}}
        processes = {'result': {'runningProcesses': [
            {'processIdentifier': 1, 'executable': 'file:///apps/ours.app/Benchmark'},
            {'processIdentifier': 2, 'executable': 'file:///apps/other.app/Benchmark'},
            {'processIdentifier': 3, 'executable': 'file:///apps/ours.app-copy/Benchmark'}]}}
        with patch.object(p, 'run', return_value='') as command, \
             patch.object(Path, 'read_text', side_effect=[json.dumps(apps), json.dumps(processes)]):
            runner.stop_benchmark()
        self.assertEqual(command.call_count, 3)
        self.assertIn('1', command.call_args.args[0])
        self.assertNotIn('2', command.call_args.args[0])
        with patch.object(p, 'run', return_value=''), \
             patch.object(Path, 'read_text', return_value=json.dumps({'result': {'apps': []}})), self.assertRaises(p.ProfileError):
            runner.stop_benchmark()

    def test_summary_excludes_warmup_and_never_invents_missing_metrics(self):
        rows = [{'scenario': 's', 'warmup': w, 'cpu_ms': cpu, 'footprint_end_bytes': 1048576}
                for w, cpu in [(True, 999), (False, 10), (False, 20)]]
        result = p.summarize([{'pass': 'timing', 'rows': rows}])[0]
        self.assertEqual(result['cpu_ms'], 15)
        self.assertEqual(result['samples'], 2)
        self.assertIsNone(result['callback_p99_ms'])
        self.assertEqual(result['settled_footprint_mib'], 1)

    def test_report_escapes_names_and_preserves_failure(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp)
            p.write_report(path, {'status': 'incomplete', 'error': '<script>bad</script>', 'review_notes': ['<script>note</script>'], 'traces': []}, [])
            self.assertIn('&lt;script&gt;', (path / 'report.html').read_text())
            self.assertNotIn('<script>', (path / 'report.html').read_text())
            self.assertEqual(json.loads((path / 'report.json').read_text())['status'], 'incomplete')

if __name__ == '__main__': unittest.main()
