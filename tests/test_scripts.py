"""Offline regression tests: all cluster commands use fake executables."""
import json
from pathlib import Path
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
FAKE_TOOL = r'''
import json, os, pathlib, sys
name = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
with open(os.environ['CALL_LOG'], 'a') as log:
    log.write(json.dumps([name, *args]) + '\n')
if name == 'minikube':
    if args == ['version', '--short']:
        print(os.environ.get('MINIKUBE_CURRENT', 'v1.36.0'))
    if args[0] == os.environ.get('FAIL_ACTION') and args[-1] == 'cluster-1':
        sys.exit(1)
elif name == 'curl':
    url = args[-1]
    if os.environ.get('FAIL_FETCH') in ('all', url):
        sys.exit(22)
    if 'api.github.com' in url:
        print(os.environ.get('MINIKUBE_RELEASE', json.dumps({'tag_name': 'v1.37.0', 'draft': False, 'prerelease': False})))
    elif 'stable-' in url:
        print(os.environ.get('K8S_PATCH', 'v1.34.10'))
    else:
        print(os.environ.get('K8S_LATEST', 'v1.35.1'))
elif name == 'helm':
    if args[0] == os.environ.get('FAIL_HELM'):
        sys.exit(1)
elif name == 'kubectl':
    if 'config' in args:
        print('partial' if os.environ.get('FAIL_EXPORT') else 'fake-kubeconfig')
        sys.exit(1 if os.environ.get('FAIL_EXPORT') else 0)
    if 'init' in args:
        print(json.dumps({'unseal_keys_b64': ['test-key'], 'root_token': 'test-token'}))
        if os.environ.get('FAIL_INIT'):
            sys.exit(1)
    if 'sys/unseal' in args:
        assert json.load(sys.stdin) == {'key': 'test-key'}
'''


class ScriptsTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.work = Path(self.temp.name)
        self.bin = self.work / 'bin'
        self.bin.mkdir()
        self.log = self.work / 'calls.jsonl'
        self.keys = self.work / 'secrets' / 'vault.json'
        # Use an isolated home for the child script; never alter the caller's HOME.
        self.env = {
            'PATH': f'{self.bin}:/usr/bin:/bin',
            'HOME': str(self.work / 'home'),
            'CALL_LOG': str(self.log),
            'KUBE_CONTEXT': 'cluster-1',
            'KEYS_FILE': str(self.keys),
        }
        for tool in ('minikube', 'helm', 'kubectl', 'curl'):
            dest = self.bin / tool
            dest.write_text(f'#!{sys.executable}\n' + FAKE_TOOL)
            dest.chmod(0o755)
        jq = shutil.which('jq')
        if not jq:
            self.skipTest('jq is required')
        (self.bin / 'jq').symlink_to(jq)

    def calls(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()] if self.log.exists() else []

    def run_script(self, script, *args, **env):
        shell = '/bin/zsh' if script == 'minikube.sh' else '/bin/bash'
        return subprocess.run([shell, str(ROOT / script), *args], env=self.env | env,
                              capture_output=True, text=True, timeout=10)

    def test_updates_reports_minikube_patch_and_minor_without_cluster_calls(self):
        result = self.run_script('minikube.sh', 'updates', K8S_VERSION='1.34.8')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('UPDATE Minikube (installed): 1.36.0 -> 1.37.0', result.stdout)
        self.assertIn('UPDATE Kubernetes 1.34 patch: 1.34.8 -> 1.34.10', result.stdout)
        self.assertIn('UPDATE Kubernetes latest stable: 1.34.8 -> 1.35.1', result.stdout)
        self.assertTrue(all(c[0] == 'curl' or c == ['minikube', 'version', '--short'] for c in self.calls()))
        self.assertFalse(Path(self.env['HOME']).exists())

    def test_updates_respects_override_and_compares_versions_numerically(self):
        result = self.run_script('minikube.sh', 'updates', K8S_VERSION='v1.34.10',
                                 K8S_PATCH='v1.34.9', K8S_LATEST='v1.34.10')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('ahead of published stable 1.34.9', result.stdout)
        self.assertIn('Kubernetes latest stable: 1.34.10 (up to date)', result.stdout)
        self.assertFalse('UPDATE Kubernetes' in result.stdout)
        self.assertTrue(any(c[-1].endswith('stable-1.34.txt') for c in self.calls()))

    def test_updates_network_failure_does_not_claim_up_to_date(self):
        result = self.run_script('minikube.sh', 'updates', FAIL_FETCH='all')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('unavailable', result.stdout)
        self.assertNotIn('up to date', result.stdout)
        self.assertEqual(sum(c[0] == 'curl' for c in self.calls()), 3)

    def test_updates_rejects_invalid_or_prerelease_responses(self):
        for payload in ('<html>error</html>', '{"tag_name":"v9.0.0-rc.1","draft":false,"prerelease":true}'):
            result = self.run_script('minikube.sh', 'updates', K8S_VERSION='1.34.8', MINIKUBE_RELEASE=payload)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('Minikube: check unavailable', result.stdout)
            self.assertIn('UPDATE Kubernetes', result.stdout)
        result = self.run_script('minikube.sh', 'updates', K8S_VERSION='1.34.8', K8S_PATCH='v1.35.0')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('patch check unavailable', result.stdout)

    def test_updates_missing_minikube_still_checks_kubernetes(self):
        (self.bin / 'minikube').unlink()
        result = self.run_script('minikube.sh', 'updates', K8S_VERSION='1.34.8')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('current version unavailable', result.stdout)
        self.assertIn('UPDATE Kubernetes', result.stdout)
        self.assertTrue(all(c[0] == 'curl' for c in self.calls()))

    def test_updates_nonstable_config_and_extra_arguments(self):
        result = self.run_script('minikube.sh', 'updates', K8S_VERSION='latest')
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(any('stable-' in c[-1] for c in self.calls()))
        previous = self.calls()
        result = self.run_script('minikube.sh', 'updates', 'extra')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.calls(), previous)

    def test_invalid_profiles_fail_before_tools(self):
        for profiles in ('../escape', '-p', 'a,,b', ',a', 'a,', 'a,a', 'a b', '/'):
            with self.subTest(profiles=profiles):
                result = self.run_script('minikube.sh', 'start', CLUSTERS=profiles)
                self.assertNotEqual(result.returncode, 0, result.stdout)
                self.assertEqual(self.calls(), [])

    def test_invalid_commands_and_flags_fail_before_tools(self):
        for args, env in [(('metrics',), {}), (('registry', 'invalid'), {}),
                          (('start', 'extra'), {}), (('start',), {'REGISTRY': 'yes'}),
                          (('start',), {'METRICS_SERVER': 'yes'})]:
            result = self.run_script('minikube.sh', *args, **env)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(self.calls(), [])

    def test_metrics_explicit_context_without_profile_switch(self):
        for action, helm_action in [('install', 'upgrade'), ('uninstall', 'uninstall')]:
            result = self.run_script('minikube.sh', 'metrics', action, CLUSTERS='cluster-2,cluster-1')
            self.assertEqual(result.returncode, 0, result.stderr)
            call = next(c for c in self.calls() if c[:2] == ['helm', helm_action])
            self.assertEqual(call[call.index('--kube-context') + 1], 'cluster-2')
        self.assertFalse(any(c[:2] == ['minikube', 'profile'] for c in self.calls()))

    def test_metrics_errors_are_not_hidden(self):
        for action, helm_action in [('install', 'repo'), ('uninstall', 'uninstall')]:
            result = self.run_script('minikube.sh', 'metrics', action, FAIL_HELM=helm_action)
            self.assertNotEqual(result.returncode, 0)

    def test_partial_failure_continues_and_exits_nonzero(self):
        for action in ('stop', 'status'):
            result = self.run_script('minikube.sh', action, CLUSTERS='cluster-1,cluster-2', FAIL_ACTION=action)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn(['minikube', action, '-p', 'cluster-2'], self.calls())

    def test_registry_failure_continues_and_exits_nonzero(self):
        result = self.run_script('minikube.sh', 'registry', 'uninstall',
                                 CLUSTERS='cluster-1,cluster-2', FAIL_ACTION='addons')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(['minikube', 'addons', 'disable', 'registry', '-p', 'cluster-2'], self.calls())

    def test_metrics_does_not_require_minikube(self):
        (self.bin / 'minikube').unlink()
        result = self.run_script('minikube.sh', 'metrics', 'install')
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_start_writes_private_configs_and_separate_cidrs(self):
        result = self.run_script('minikube.sh', 'start', CLUSTERS='cluster-1,cluster-2')
        self.assertEqual(result.returncode, 0, result.stderr)
        for i in (1, 2):
            config = Path(self.env['HOME']) / '.kube' / 'clusters' / f'cluster-{i}'
            self.assertEqual(config.read_text(), 'fake-kubeconfig\n')
            self.assertEqual(stat.S_IMODE(config.stat().st_mode), 0o600)
            self.assertTrue(any(f'--service-cluster-ip-range=172.16.{i}.0/24' in c for c in self.calls()))

    def test_failed_export_preserves_existing_config(self):
        config = Path(self.env['HOME']) / '.kube' / 'clusters' / 'cluster-1'
        config.parent.mkdir(parents=True)
        config.write_text('original')
        result = self.run_script('minikube.sh', 'start', FAIL_EXPORT='1')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(config.read_text(), 'original')
        self.assertEqual(list(config.parent.glob('*.tmp.*')), [])

    def test_vault_init_private_no_secrets_in_args_or_output(self):
        result = self.run_script('scripts/vault-init.sh')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(stat.S_IMODE(self.keys.stat().st_mode), 0o600)
        self.assertEqual(stat.S_IMODE(self.keys.parent.stat().st_mode), 0o700)
        visible = result.stdout + result.stderr + self.log.read_text()
        self.assertNotIn('test-key', visible)
        self.assertNotIn('test-token', visible)
        for call in self.calls():
            self.assertIn('--context=cluster-1', call)
        self.assertEqual(sum('sys/unseal' in c for c in self.calls()), 3)

    def test_vault_refuses_overwrite_and_supports_unseal(self):
        self.assertEqual(self.run_script('scripts/vault-init.sh').returncode, 0)
        original = self.keys.read_bytes()
        calls_before = self.calls()
        result = self.run_script('scripts/vault-init.sh')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.keys.read_bytes(), original)
        self.assertEqual(self.calls(), calls_before)
        result = self.run_script('scripts/vault-init.sh', 'unseal')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(sum('init' in c for c in self.calls()), 1)

    def test_failed_init_preserves_recovery_data(self):
        result = self.run_script('scripts/vault-init.sh', FAIL_INIT='1')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(json.loads(self.keys.read_text())['root_token'], 'test-token')
        self.assertEqual(len(self.calls()), 1)

    def test_vault_rejects_symlink_and_missing_context(self):
        self.keys.parent.mkdir()
        target = self.work / 'untouched'
        target.write_text('original')
        self.keys.symlink_to(target)
        for mode in ('init', 'unseal'):
            self.assertNotEqual(self.run_script('scripts/vault-init.sh', mode).returncode, 0)
        self.assertEqual(target.read_text(), 'original')
        self.assertEqual(self.calls(), [])
        # noclobber alone need not protect special-file targets.
        self.keys.unlink()
        self.keys.symlink_to('/dev/null')
        self.assertNotEqual(self.run_script('scripts/vault-init.sh').returncode, 0)
        self.assertEqual(self.calls(), [])
        self.assertNotEqual(self.run_script('scripts/vault-init.sh', KUBE_CONTEXT='').returncode, 0)


if __name__ == '__main__':
    unittest.main()
