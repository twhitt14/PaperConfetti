import json
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from validate import simulator


class SimulatorSelectionTests(unittest.TestCase):
    def inventory(self, existing=True):
        return {
            'runtimes': [
                {'isAvailable': True, 'name': 'iOS 27.2', 'version': '27.2', 'identifier': 'device-specific',
                 'supportedDeviceTypes': [{'identifier': 'com.apple.CoreSimulator.SimDeviceType.iPhone-Duo'}]},
                {'isAvailable': True, 'name': 'iOS 27.2', 'version': '27.2', 'identifier': 'standard',
                 'supportedDeviceTypes': [{'identifier': 'com.apple.CoreSimulator.SimDeviceType.iPhone-16'}]},
            ],
            'devices': {
                'device-specific': [{'name': 'PaperConfetti Example', 'isAvailable': True, 'udid': 'wrong-display'}],
                'standard': [{'name': 'PaperConfetti Example', 'isAvailable': True, 'udid': 'standard-phone'}] if existing else [],
            },
        }

    def output(self, inventory):
        def read(args, **kwargs):
            if '--show-sdk-version' in args: return '27.2\n'
            if 'create' in args: return 'new-phone\n'
            return json.dumps(inventory).encode()
        return read

    def testIdenticalVersionDeviceSpecificRuntimeDoesNotWinByListOrder(self):
        with patch('validate.subprocess.check_output', side_effect=self.output(self.inventory())) as command:
            self.assertEqual(simulator(), 'standard-phone')
            self.assertFalse(any('create' in call.args[0] for call in command.call_args_list))

    def testNewDedicatedDeviceUsesExplicitRepresentativeIPhone(self):
        with patch('validate.subprocess.check_output', side_effect=self.output(self.inventory(False))) as command:
            self.assertEqual(simulator(), 'new-phone')
            self.assertEqual(command.call_args.args[0], ['xcrun', 'simctl', 'create', 'PaperConfetti Example',
                'com.apple.CoreSimulator.SimDeviceType.iPhone-16', 'standard'])
