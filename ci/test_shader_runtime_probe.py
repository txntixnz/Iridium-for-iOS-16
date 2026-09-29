"""Test orchestration with fake tools; does not test Apple compilation."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).with_name('check-ios16-shader-runtime.sh')


class ShaderRuntimeProbeTests(unittest.TestCase):
    def run_probe(self, fail=''):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / 'ci').mkdir()
            (root / 'ci/runtime-inputs.json').write_text('[]')
            bindir = root / 'bin'
            bindir.mkdir()
            fake = bindir / 'fake'
            fake.write_text('#!' + sys.executable + '\n' + r'''
import json, os, pathlib, sys
name = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
with open('calls.jsonl', 'a') as f:
    f.write(json.dumps([name] + args) + '\n')
if name == 'uname':
    print('Darwin')
elif name == 'python3':
    if args[:1] == ['ci/fetch-runtime-inputs.py']:
        p = pathlib.Path('testrepos/Madeira/toolchains/llvm-project/llvm/cmake/modules/AddLLVM.cmake')
        p.parent.mkdir(parents=True)
        p.write_text('MATCHES "Darwin"\nMATCHES "Darwin"\n')
    else:
        os.execv(sys.executable, [sys.executable] + args)
elif name == 'xcrun':
    if '--show-sdk-path' in args:
        print('/fake/iPhoneOS.sdk')
    elif 'otool' in args and '-l' in args:
        print('cmd LC_BUILD_VERSION\nplatform 2\nminos 16.0\nsdk 26.0')
    elif '-o' in args:
        out = pathlib.Path(args[args.index('-o') + 1])
        if out.stem == os.environ.get('FAIL_UNIT'):
            print('deliberate compiler failure', file=sys.stderr)
            sys.exit(1)
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text('test-only fake output')
''')
            fake.chmod(0o755)
            for name in ('uname', 'python3', 'xcrun', 'xcodebuild', 'cmake', 'xxd'):
                (bindir / name).symlink_to(fake)
            env = dict(os.environ, PATH=str(bindir) + os.pathsep + os.environ['PATH'], FAIL_UNIT=fail)
            result = subprocess.run(['bash', str(SCRIPT.resolve())], cwd=root, env=env,
                                    stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
            calls = [json.loads(line) for line in (root / 'calls.jsonl').read_text().splitlines()]
            return result, calls

    def test_success_compiles_all_units_and_checks_real_link_flags(self):
        result, calls = self.run_probe()
        self.assertEqual(result.returncode, 0, result.stdout)
        compiles = [c for c in calls if 'clang++' in c and '-c' in c]
        self.assertEqual(len(compiles), 18)
        for c in compiles:
            self.assertIn('arm64-apple-ios16.0', c)
            self.assertIn('-Werror=unguarded-availability-new', c)
        links = [c for c in calls if '-dynamiclib' in c]
        self.assertEqual(len(links), 1)
        self.assertIn('-Wl,-undefined,error', links[0])
        self.assertTrue(any(c.startswith('-Wl,-force_load,') for c in links[0]))
        self.assertTrue(any('-DCMAKE_OSX_DEPLOYMENT_TARGET=16.0' in c for c in calls))
        self.assertTrue(any(c[:2] == ['python3', 'ci/fetch-runtime-inputs.py'] for c in calls))

    def test_compile_failure_collects_remaining_units_and_blocks_link(self):
        result, calls = self.run_probe('dxbc_converter')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('deliberate compiler failure', result.stdout)
        self.assertEqual(sum('clang++' in c and '-c' in c for c in calls), 18)
        self.assertFalse(any('-dynamiclib' in c for c in calls))

    def test_link_failure_fails_the_job(self):
        result, calls = self.run_probe('airconv-link-check')
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(any('-dynamiclib' in c for c in calls))
        self.assertNotIn('Translator compiled and linked', result.stdout)


if __name__ == '__main__':
    unittest.main()
