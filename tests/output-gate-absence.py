import importlib.util
from pathlib import Path
import random
import unittest


spec = importlib.util.spec_from_file_location('context_tests', Path(__file__).with_name('output-gate-context.py'))
fixtures = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fixtures)


class AbsenceTests(unittest.TestCase):
    def setUp(self):
        self.fixture = fixtures.ContextTests()
        self.fixture.setUp()
        self.addCleanup(self.fixture.doCleanups)

    def test_fetched_evidence_survives_update_and_revised_answer(self):
        f = self.fixture
        f.payload['evidence'] = [{'id': 'verification', 'output': 'x' * 10000 + 'VERIFIED' + 'y' * 10000}]
        ready = f.ready()
        source = next(s for s in ready['transaction']['sources'].values() if s['kind'] == 'evidence')
        wanted = fixtures.checker.context.ref(source, 'output', 10000, 10008)
        ready = f.reply(ready, dict(kind='need_refs', refs=[wanted]))
        ready = f.update(ready)
        self.assertTrue(any(e['ref'] == wanted for e in f.packet(ready)['retrieved']))
        f.payload['draft'] = 'Updated answer.'
        f.payload['evidence'].append({'id': 'inspection', 'output': 'No target changes.'})
        resumed = f.ready()
        self.assertTrue(any(e['ref'] == wanted and e['text'] == 'VERIFIED' for e in f.packet(resumed)['retrieved']))
        self.assertEqual(f.packet(resumed)['answers'][0]['text'], 'Updated answer.')
        self.assertEqual(f.judgment(resumed)['status'], 'checked')

    def test_unread_archive_requires_lookup_before_absence_can_be_reported(self):
        f = self.fixture
        noise = ''.join(random.Random(71).choices('abcdefghijklmnopqrstuvwxyz0123456789', k=20000))
        f.payload['evidence'] = [{'id': 'verification', 'output': noise[:10000] + 'VERIFIED' + noise[10000:]}]
        ready = f.update(f.ready())
        answer = f.packet(ready)['answers'][0]
        claim = dict(id='result', answer_ref=answer['ref'], text=answer['text'], requirement_ids=[], evidence=[], verdict='unverified')
        result = f.judgment(ready, claims=[claim])
        self.assertEqual(result['status'], 'ready')
        self.assertIn('evidence search', f.packet(result)['validation_feedback'])
        ready = f.reply(result, dict(kind='need_refs', focus_refs=[answer['ref']], refs=[dict(scope='archive', field='output', literal='VERIFIED', before_seq=0)]))
        original = f.packet(ready)['retrieved'][0]
        self.assertIn('VERIFIED', original['text'])
        claim.update(verdict='supported', temporal_scope='historical', evidence=[dict(ref=original['ref'], relation='supports')])
        checked = f.judgment(ready, claims=[claim])
        self.assertEqual(checked['status'], 'checked')
        self.assertEqual(checked['findings'], [])

    def test_complete_search_can_establish_genuine_absence(self):
        f = self.fixture
        noise = ''.join(random.Random(71).choices('abcdefghijklmnopqrstuvwxyz0123456789', k=20000))
        f.payload['evidence'] = [{'id': 'unrelated', 'output': noise}]
        ready = f.update(f.ready())
        answer = f.packet(ready)['answers'][0]
        ready = f.reply(ready, dict(kind='need_refs', focus_refs=[answer['ref']], refs=[dict(scope='archive', field='output', literal='VERIFIED', before_seq=0)]))
        claim = dict(id='result', answer_ref=answer['ref'], text=answer['text'], requirement_ids=[], evidence=[], verdict='unverified')
        checked = f.judgment(ready, claims=[claim])
        self.assertEqual(checked['status'], 'checked')
        self.assertTrue(checked['findings'])

    def test_search_for_another_answer_range_does_not_prove_absence(self):
        f = self.fixture
        noise = ''.join(random.Random(71).choices('abcdefghijklmnopqrstuvwxyz0123456789', k=20000))
        f.payload['evidence'] = [{'id': 'unrelated', 'output': noise}]
        ready = f.update(f.ready())
        answer = f.packet(ready)['answers'][0]
        other_range = dict(answer['ref'], end=answer['ref']['start'] + 1)
        ready = f.reply(ready, dict(kind='need_refs', focus_refs=[other_range], refs=[dict(scope='archive', field='output', literal='VERIFIED', before_seq=0)]))
        claim = dict(id='result', answer_ref=answer['ref'], text=answer['text'], requirement_ids=[], evidence=[], verdict='unverified')
        result = f.judgment(ready, claims=[claim])
        self.assertEqual(result['status'], 'ready')

    def test_unresolved_available_evidence_does_not_replace_search_of_unread_originals(self):
        f = self.fixture
        noise = ''.join(random.Random(71).choices('abcdefghijklmnopqrstuvwxyz0123456789', k=20000))
        f.payload['evidence'] = [{'id': 'verification', 'output': noise}, {'id': 'other', 'output': 'Commit exists.'}]
        ready = f.update(f.ready())
        data = f.packet(ready)
        other = next(e for e in data['catalog_grounding'] if e['ref']['field'] == 'output' and e['text'] == 'Commit exists.')
        claim = dict(id='result', answer_ref=data['answers'][0]['ref'], text='Done.', requirement_ids=[], evidence=[dict(ref=other['ref'], relation='unresolved')], verdict='unverified')
        self.assertEqual(f.judgment(ready, claims=[claim])['status'], 'ready')

    def test_source_match_continuations_must_finish_before_absence_is_judged(self):
        f = self.fixture
        noise = ''.join(random.Random(71).choices('abcdefghijklmnopqrstuvwxyz0123456789', k=60000))
        output = ''.join('VERIFIED' + noise[n:n + 3000] for n in range(0, len(noise), 3000))
        f.payload['evidence'] = [{'id': 'verification', 'output': output}]
        ready = f.update(f.ready())
        answer = f.packet(ready)['answers'][0]
        ready = f.reply(ready, dict(kind='need_refs', focus_refs=[answer['ref']], refs=[dict(scope='archive', field='output', literal='VERIFIED', before_seq=0)]))
        detail = f.packet(ready)['locator_results'][0]['matches'][0]
        self.assertIsNotNone(detail['remaining_after'])
        claim = dict(id='result', answer_ref=answer['ref'], text=answer['text'], requirement_ids=[], evidence=[], verdict='unverified')
        ready = f.judgment(ready, claims=[claim])
        self.assertEqual(ready['status'], 'ready')
        while detail['remaining_after'] is not None:
            query = dict(detail['locator'], after=detail['remaining_after'])
            ready = f.reply(ready, dict(kind='need_refs', focus_refs=[answer['ref']], refs=[query]))
            detail = f.packet(ready)['locator_results'][0]
        self.assertEqual(f.judgment(ready, claims=[claim])['status'], 'checked')

    def test_update_lookup_keeps_its_answer_scope_for_judgment(self):
        f = self.fixture
        noise = ''.join(random.Random(71).choices('abcdefghijklmnopqrstuvwxyz0123456789', k=20000))
        f.payload['evidence'] = [{'id': 'unrelated', 'output': noise}]
        ready = f.ready()
        data = f.packet(ready)
        answer = (data.get('answer_preview') or data['answers'])[0]
        ready = f.reply(ready, dict(kind='update', user_coverage=[u['ref'] for u in data['users']],
            decisions=[], additions=[], unresolved=[], focus_refs=[answer['ref']],
            catalog_coverage=[dict(id=c['id'], rev=c['rev'], disposition='unrelated', related_item_ids=[], reason='unrelated') for c in data.get('catalog', [])],
            refs=[dict(scope='archive', field='output', literal='VERIFIED', before_seq=0)]))
        answer = f.packet(ready)['answers'][0]
        claim = dict(id='result', answer_ref=answer['ref'], text=answer['text'], requirement_ids=[], evidence=[], verdict='unverified')
        self.assertEqual(f.judgment(ready, claims=[claim])['status'], 'checked')

    def test_retained_originals_fit_the_judgment_input_budget(self):
        f = self.fixture
        rng = random.Random(71)
        text = lambda n: ''.join(rng.choices('abcdefghijklmnopqrstuvwxyz0123456789', k=n))
        rules = text(70000)
        f.payload['evidence'] = [{'id': 'ground', 'output': text(250000)}, {'id': 'recent', 'output': text(105000)}]
        with fixtures.patch.object(fixtures.checker, 'response_rules', lambda: rules):
            ready = f.ready()
            sources = [s for s in ready['transaction']['sources'].values() if s['kind'] == 'evidence']
            ground = fixtures.checker.context.ref(sources[0], 'output')
            ready = f.reply(ready, dict(kind='need_refs', refs=[ground]))
            while f.packet(ready)['remaining_refs']:
                ready = f.reply(ready, dict(kind='need_refs', refs=f.packet(ready)['remaining_refs']))
            ready = f.reply(ready, dict(kind='need_refs', refs=[fixtures.checker.context.ref(sources[1], 'output')]))
            fact = dict(id='ground', kind='fact', text='Prior verified result.', refs=[ground], related=[], target=dict(name='result', revision_refs=[]), validity='current')
            ready = f.update(ready, additions=[fact])
            self.assertEqual(ready['status'], 'ready')
            self.assertLessEqual(len(ready['prompt'].encode()) + len(ready['system'].encode()) + len(fixtures.checker.context.encoded(ready['schema'])), fixtures.checker.context.LIMIT)


if __name__ == '__main__':
    unittest.main()
