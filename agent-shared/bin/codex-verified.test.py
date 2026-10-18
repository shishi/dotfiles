#!/usr/bin/env python3
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time
import unittest

WRAPPER = Path(__file__).with_name('codex-verified.sh')
FAKE = r'''#!/usr/bin/env python3
import json, os, pathlib, sys, time
name = pathlib.Path(sys.argv[0]).name
root = pathlib.Path(os.environ['FAKE_ROOT'])
mode = os.environ.get('FAKE_MODE', 'complete')
args = sys.argv[1:]
with (root/'calls').open('a') as f:
    f.write(json.dumps([name, args])+'\n')
if name == 'gitleaks':
    source = pathlib.Path(args[args.index('--source')+1])
    sys.exit(1 if mode == 'secret' and 'PRIVATE_DRAFT' in source.read_text() else 0)
if name == 'codex':
    if args[:2] == ['login','status']:
        print('Logged in using ChatGPT', file=sys.stderr)
        sys.exit(0)
    text = sys.stdin.read()
    resume = 'resume' in args
    attempt = len([entry for entry in map(json.loads,(root/'calls').read_text().splitlines()) if entry[0]=='codex' and 'exec' in entry[1]])
    if resume:
        assert 'session-123' in args and 'run missing verification' in text
    else:
        assert text == 'implement requested behavior'
    (root/'started').write_text('yes')
    if mode == 'slow':
        time.sleep(.5)
    if mode == 'executor_timeout':
        time.sleep(5)
    draft = 'VERIFIED_FINAL' if resume or mode not in ('repair','limit','secret') else 'PRIVATE_DRAFT'
    pathlib.Path(args[args.index('-o')+1]).write_text(draft)
    print(json.dumps({'type':'thread.started','thread_id':'session-123'}), flush=True)
    print(json.dumps({'type':'item.completed','item':{'id':'cmd-1','type':'command_execution','command':'run verification','aggregated_output':'DIRECT_EVIDENCE'+(str(attempt) if mode=='progress_reset' else ''),'exit_code':0,'status':'completed'}}), flush=True)
    if mode == 'file_edit':
        (root/'result.txt').write_text(str(attempt))
        print(json.dumps({'type':'item.completed','item':{'id':'edit-1','type':'file_change','changes':[{'path':'result.txt','kind':'update'}],'status':'completed'}}), flush=True)
    print(json.dumps({'type':'item.completed','item':{'id':'message','type':'agent_message','text':draft}}), flush=True)
    print(json.dumps({'type':'turn.completed','usage':{'input_tokens':1,'output_tokens':1}}), flush=True)
    print('PRIVATE_STDERR',file=sys.stderr,flush=True)
    sys.exit(4 if mode == 'executor_failure' else 0)
if 'auth' in args and 'status' in args:
    print(json.dumps({'loggedIn':True,'authMethod':'claude.ai','apiProvider':'firstParty'}))
    sys.exit(0)
payload = sys.stdin.read()
(root/'judge-input').write_text(payload)
assert '--tools' in args and args[args.index('--tools')+1] == ''
assert '--safe-mode' in args and '--bare' not in args
assert '--strict-mcp-config' in args and '--no-session-persistence' in args
assert 'PRIVATE_STDERR' not in payload
assert 'implement requested behavior' in payload
assert 'current_event_stream' not in payload
data = json.loads(payload)
if 'candidate_answer' not in data:
    plan = {'request_kind':'explanation' if mode in ('explanation', 'explanation_as_complete') else 'action','requirements':['implement behavior','verify requested outcome']}
    if mode == 'bad_requirements':
        plan['requirements'] = []
    print(json.dumps({'type':'result','subtype':'success','is_error':False,'structured_output':plan,'modelUsage':{'claude-fable-test':{}}}))
    sys.exit(0)
if mode == 'judge_timeout':
    time.sleep(5)
if mode == 'judge_failure':
    print('PRIVATE_JUDGE_STDERR',file=sys.stderr)
    sys.exit(5)
if mode == 'malformed':
    print('PRIVATE_MALFORMED_DRAFT')
    sys.exit(0)
assert 'DIRECT_EVIDENCE' in payload
assert data['requirements'] == ['implement behavior','verify requested outcome']
status = 'user_blocker' if mode == 'user_blocker' else ('incomplete' if mode in ('limit','duplicate_progress') or (mode == 'repair' and data['candidate_answer'] == 'PRIVATE_DRAFT') or (mode == 'progress_reset' and data['attempt'] < 4) or (mode == 'file_edit' and data['attempt'] < 3) else 'complete')
verdict = {'status':status,'reason':'observed execution','remaining_work':['run missing verification'] if status == 'incomplete' else [], 'requirements':[{'requirement_index':i,'status':'supported','reason':'directly verified','evidence_indices':[0]} for i in range(2)]}
if status == 'incomplete':
    verdict['requirements'][1]['status'] = 'unproven'
if mode == 'user_blocker':
    verdict['remaining_work'] = ['user must authenticate']
    verdict['requirements'][1]['status'] = 'user_blocker'
if mode == 'bad_evidence':
    verdict['requirements'][0]['evidence_indices'] = [99]
if mode == 'missing_requirement':
    verdict['requirements'].pop()
if mode == 'unsupported_complete':
    verdict['requirements'][1]['status'] = 'unproven'
if mode == 'duplicate_requirement':
    verdict['requirements'][1]['requirement_index'] = 0
if mode == 'empty_evidence':
    verdict['requirements'][1]['evidence_indices'] = []
if mode in ('explanation', 'action_as_explanation'):
    verdict['status'] = 'explanation'
if mode in ('explanation', 'explanation_as_complete'):
    for check in verdict['requirements']:
        check['evidence_indices'] = []
print(json.dumps({'type':'result','subtype':'success','is_error':False,'structured_output':verdict,'modelUsage':{'claude-fable-test':{}}}))
'''


class VerifiedOutput(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.env = dict(os.environ)
        for key in list(self.env):
            if key.startswith(('ANTHROPIC_', 'CLAUDE_CODE_USE_')) or key in ('CODEX_API_KEY', 'OPENAI_BASE_URL', 'GITLEAKS_CONFIG', 'CLAUDE_CONFIG_DIR'):
                self.env.pop(key)
        self.env.update(FAKE_ROOT=str(self.root), XDG_STATE_HOME=str(self.root/'state'), CODEX_HOME=str(self.root/'codex-home'), HOME=str(self.root/'home'))
        Path(self.env['HOME']).mkdir()
        (self.root/'bin').mkdir()
        for name in ('codex','claude','gitleaks'):
            exe = self.root/'bin'/name
            exe.write_text(FAKE)
            exe.chmod(0o755)
        self.env['PATH'] = str(self.root/'bin')+os.pathsep+self.env['PATH']

    def tearDown(self):
        self.tmp.cleanup()

    def run_wrapper(self, mode='complete', stdin=False):
        self.env['FAKE_MODE'] = mode
        return subprocess.run(['bash',str(WRAPPER)]+([] if stdin else ['implement requested behavior']), input='implement requested behavior' if stdin else '', text=True,capture_output=True,env=self.env,cwd=self.root,timeout=10)

    def calls(self, name):
        return [entry[1] for entry in map(json.loads,(self.root/'calls').read_text().splitlines()) if entry[0]==name]

    def assert_private_failure(self, result):
        self.assertNotEqual(result.returncode,0)
        self.assertEqual(result.stdout,'')
        self.assertNotIn('PRIVATE_',result.stderr)
        self.assertNotIn('VERIFIED_FINAL',result.stderr)

    def test_only_verified_final_publishes_and_stdin_works(self):
        result = self.run_wrapper(stdin=True)
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertEqual(result.stdout,'VERIFIED_FINAL\n')
        self.assertNotIn('PRIVATE_',result.stderr)
        self.assertGreaterEqual(len(self.calls('gitleaks')),2)

    def test_stdout_and_stderr_stay_buffered_until_judgement(self):
        self.env['FAKE_MODE']='slow'
        out=self.root/'visible-out'
        err=self.root/'visible-err'
        with out.open('w') as stdout, err.open('w') as stderr:
            proc=subprocess.Popen(['bash',str(WRAPPER),'implement requested behavior'],stdout=stdout,stderr=stderr,env=self.env,cwd=self.root)
            deadline=time.monotonic()+3
            while not (self.root/'started').exists() and proc.poll() is None and time.monotonic()<deadline:
                time.sleep(.01)
            self.assertTrue((self.root/'started').exists())
            self.assertEqual(out.read_text(),'')
            self.assertEqual(err.read_text(),'')
            self.assertEqual(proc.wait(timeout=5),0)
        self.assertEqual(out.read_text(),'VERIFIED_FINAL\n')

    def test_incomplete_resumes_same_session_privately(self):
        result=self.run_wrapper('repair')
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertEqual(result.stdout,'VERIFIED_FINAL\n')
        runs=[args for args in self.calls('codex') if 'exec' in args]
        self.assertEqual(len(runs),2)
        self.assertIn('resume',runs[1])
        self.assertIn('session-123',runs[1])
        self.assertNotIn('PRIVATE_',result.stderr)

    def test_failures_never_publish_draft(self):
        for mode in ('judge_failure','malformed','bad_evidence','executor_failure','secret','judge_timeout','executor_timeout'):
            with self.subTest(mode=mode):
                self.env['CODEX_VERIFIED_EXEC_TIMEOUT']='1'
                self.env['CODEX_VERIFIED_JUDGE_TIMEOUT']='1'
                before = len(self.calls('codex')) if (self.root/'calls').exists() else 0
                self.assert_private_failure(self.run_wrapper(mode))
                runs = [args for args in self.calls('codex')[before:] if 'exec' in args]
                self.assertEqual(len(runs), 1)

    def test_only_one_repair_even_with_new_file_edits(self):
        for mode in ('limit', 'file_edit'):
            with self.subTest(mode=mode):
                before = len(self.calls('codex')) if (self.root/'calls').exists() else 0
                self.assert_private_failure(self.run_wrapper(mode))
                runs=[args for args in self.calls('codex')[before:] if 'exec' in args]
                self.assertEqual(len(runs),2)
                self.assertIn('resume', runs[1])
                for args in runs:
                    self.assertIn('--approve-for-me',args)
                    self.assertNotIn('--dangerously-bypass-approvals-and-sandbox',args)

    def test_every_original_requirement_must_be_proven(self):
        for mode in ('missing_requirement', 'unsupported_complete', 'duplicate_requirement', 'empty_evidence', 'action_as_explanation', 'explanation_as_complete'):
            with self.subTest(mode=mode):
                self.assert_private_failure(self.run_wrapper(mode))

    def test_invalid_requirements_stop_before_execution(self):
        self.assert_private_failure(self.run_wrapper('bad_requirements'))
        self.assertFalse(any('exec' in args for args in self.calls('codex')))

    def test_explanation_request_can_publish_without_execution_citations(self):
        result = self.run_wrapper('explanation')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, 'VERIFIED_FINAL\n')

    def test_genuine_user_blocker_can_include_user_remaining_action(self):
        result=self.run_wrapper('user_blocker')
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertEqual(result.stdout,'VERIFIED_FINAL\n')

    def test_destination_override_rejected_before_model_launch(self):
        for key, value in (('ANTHROPIC_BASE_URL','https://unapproved.invalid'), ('CODEX_API_KEY','acceptance-dummy-not-a-credential')):
            with self.subTest(key=key):
                self.env[key]=value
                self.assert_private_failure(self.run_wrapper())
                if (self.root/'calls').exists():
                    self.assertFalse(any('exec' in args for args in self.calls('codex')))
                    self.assertFalse(any(args and args[0]=='-p' for args in self.calls('claude')))
                self.env.pop(key)


if __name__=='__main__':
    unittest.main()
