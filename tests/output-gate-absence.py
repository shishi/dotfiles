import importlib.util
from copy import deepcopy
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
            def interpretations(state):
                return [dict(id='fixture-' + fixtures.checker.context.digest(e['ref'])[:16], kind='fact',
                    text='This original is ASCII fixture data, not a verification result.', refs=[e['ref']], related=[],
                    target=dict(name='result', revision_refs=[]), validity='current')
                    for e in f.packet(state)['retrieved'] if e['kind'] == 'evidence']
            while f.packet(ready)['remaining_refs']:
                ready = f.reply(ready, dict(kind='need_refs', refs=f.packet(ready)['remaining_refs'], additions=interpretations(ready)))
            ready = f.reply(ready, dict(kind='need_refs', refs=[fixtures.checker.context.ref(sources[1], 'output')], additions=interpretations(ready)))
            fact = dict(id='ground', kind='fact', text='Large original contains ASCII fixture data.', refs=[ground], related=[], target=dict(name='result', revision_refs=[]), validity='current')
            ready = f.update(ready, additions=[fact, *interpretations(ready)])
            self.assertEqual(ready['status'], 'ready')
            self.assertLessEqual(len(ready['prompt'].encode()) + len(ready['system'].encode()) + len(fixtures.checker.context.encoded(ready['schema'])), fixtures.checker.context.LIMIT)

    def test_search_receipt_history_does_not_crowd_out_requested_originals(self):
        f = self.fixture
        rng = random.Random(71)
        noise = ''.join(rng.choices('abcdefghijklmnopqrstuvwxyz0123456789', k=60000))
        f.payload['evidence'] = [{'id': 'verification', 'output': ''.join('VERIFIED' + noise[n:n + 3000] for n in range(0, len(noise), 3000))}]
        ready = f.update(f.ready())
        answer = f.packet(ready)['answers'][0]
        ready = f.reply(ready, dict(kind='need_refs', focus_refs=[answer['ref']], refs=[dict(scope='archive', field='output', literal='VERIFIED', before_seq=0)]))
        receipt = ready['transaction']['archive_searches'][0]
        ready['transaction']['archive_searches'] = [receipt] * 250
        source = next(s for s in ready['transaction']['sources'].values() if s['kind'] == 'evidence')
        wanted = fixtures.checker.context.ref(source, 'output', 30000, 31000)
        result = f.reply(ready, dict(kind='need_refs', refs=[wanted]))
        self.assertEqual(result['status'], 'ready')
        self.assertEqual(len(result['transaction']['archive_searches']), 250)
        self.assertTrue(any(e['ref'] == wanted for e in f.packet(result)['retrieved']))

    def test_revised_answer_keeps_old_receipts_without_reusing_their_absence_proof(self):
        f = self.fixture
        noise = ''.join(random.Random(71).choices('abcdefghijklmnopqrstuvwxyz0123456789', k=20000))
        f.payload['evidence'] = [{'id': 'unrelated', 'output': noise}]
        ready = f.update(f.ready())
        answer = f.packet(ready)['answers'][0]
        ready = f.reply(ready, dict(kind='need_refs', focus_refs=[answer['ref']], refs=[dict(scope='archive', field='output', literal='VERIFIED', before_seq=0)]))
        receipt = ready['transaction']['archive_searches'][0]
        f.payload['draft'] = 'Updated answer.'
        f.payload['evidence'].append({'id': 'later', 'output': 'Later operation.'})
        resumed = f.ready()
        self.assertIn(receipt, resumed['transaction'].get('archive_searches', []))
        packet = f.packet(resumed)
        answer = (packet.get('answers') or packet['answer_preview'])[0]
        self.assertFalse(fixtures.checker.context.searched_claim_originals(resumed['transaction'], answer['ref']))

    def test_completed_visible_lookup_is_not_reexecuted_or_appended(self):
        f = self.fixture
        f.payload['evidence'] = [{'id': 'verification', 'output': 'VERIFIED'}]
        ready = f.update(f.ready())
        answer = f.packet(ready)['answers'][0]
        lookup = dict(kind='need_refs', focus_refs=[answer['ref']], refs=[dict(scope='archive', field='output', literal='VERIFIED', before_seq=0)])
        ready = f.reply(ready, lookup)
        result = f.reply(ready, lookup)
        self.assertEqual(result['status'], 'ready')
        self.assertEqual(len(result['transaction']['archive_searches']), 1)

    def test_cached_lookup_retains_new_grounded_interpretation(self):
        f = self.fixture
        f.payload['evidence'] = [{'id': 'verification', 'output': 'VERIFIED'}]
        ready = f.update(f.ready())
        answer = f.packet(ready)['answers'][0]
        lookup = dict(kind='need_refs', focus_refs=[answer['ref']], refs=[dict(scope='archive', field='output', literal='VERIFIED', before_seq=0)])
        ready = f.reply(ready, lookup)
        original = next(e for e in f.packet(ready)['retrieved'] if 'VERIFIED' in e['text'])
        observation = dict(id='observed-result', kind='fact', text='The original result says VERIFIED.', refs=[original['ref']], related=[], target=dict(name='result', revision_refs=[]), validity='current')
        ready = f.reply(ready, dict(lookup, additions=[observation]))
        self.assertTrue(any(o['text'] == observation['text'] and o['refs'] == observation['refs'] for o in ready['transaction']['retrieval_observations']))

    def test_completed_judgment_keeps_grounded_interpretations_for_the_next_answer(self):
        f = self.fixture
        f.payload['evidence'] = [{'id': 'verification', 'output': 'VERIFIED'}]
        ready = f.update(f.ready())
        answer = f.packet(ready)['answers'][0]
        ready = f.reply(ready, dict(kind='need_refs', focus_refs=[answer['ref']], refs=[dict(scope='archive', field='output', literal='VERIFIED', before_seq=0)]))
        original = next(e for e in f.packet(ready)['retrieved'] if 'VERIFIED' in e['text'])
        observation = dict(id='observed-result', kind='fact', text='The original result says VERIFIED.', refs=[original['ref']], related=[], target=dict(name='result', revision_refs=[]), validity='current')
        ready = f.reply(ready, dict(kind='need_refs', refs=[original['ref']], additions=[observation]))
        stored = ready['transaction']['retrieval_observations'][0]
        checked = f.judgment(ready)
        self.assertEqual(checked['status'], 'checked')
        f.payload['draft'] = 'A revised answer.'
        resumed = f.ready()
        self.assertIn(stored, f.packet(resumed)['retrieval_observations'])
        self.assertTrue(fixtures.checker.context.covered(original['ref'], resumed['transaction']['served_refs']))

    def test_completed_shown_prefix_is_not_rejudged_but_new_bytes_are(self):
        f = self.fixture
        f.payload['shown_text'] = '確認したよ。'
        ready = f.update(f.ready())
        self.assertEqual(f.judgment(ready)['status'], 'checked')
        f.payload['draft'] = 'A revised answer.'
        ready = f.ready()
        self.assertEqual([a['answer_role'] for a in f.packet(ready)['answers']], ['draft'])
        f.payload['shown_text'] += '追加。'
        ready = f.ready()
        shown = [a for a in f.packet(ready)['answers'] if a['answer_role'] == 'shown']
        self.assertEqual([a['text'] for a in shown], ['追加。'])
        self.assertEqual(shown[0]['ref']['start'], len('確認したよ。'.encode()))
        f.payload['shown_text'] = '変更したよ。追加。'
        ready = f.ready()
        self.assertEqual([a['text'] for a in f.packet(ready)['answers'] if a['answer_role'] == 'shown'], ['変更したよ。追加。'])
        f.payload.update(turn_id='another-turn', shown_text='確認したよ。')
        ready = f.ready()
        self.assertEqual([a['text'] for a in f.packet(ready)['answers'] if a['answer_role'] == 'shown'], ['確認したよ。'])

    def test_unfinished_shown_assessment_is_not_reused(self):
        f = self.fixture
        f.payload['shown_text'] = '確認したよ。'
        f.update(f.ready())
        f.payload['draft'] = 'A revised answer.'
        ready = f.ready()
        self.assertEqual([a['text'] for a in f.packet(ready)['answers'] if a['answer_role'] == 'shown'], ['確認したよ。'])

    def test_new_bounded_originals_are_supplied_without_refetching_committed_history(self):
        f = self.fixture
        f.payload['evidence'] = [{'id': 'earlier', 'output': 'Earlier operation.'}]
        self.assertEqual(f.judgment(f.update(f.ready()))['status'], 'checked')
        rng = random.Random(71)
        small = ''.join(rng.choices('abcdefghijklmnopqrstuvwxyz0123456789', k=65000))
        large = ''.join(rng.choices('abcdefghijklmnopqrstuvwxyz0123456789', k=150000))
        f.payload['evidence'] += [{'id': 'fresh', 'output': small}, {'id': 'oversized', 'output': large}]
        f.payload['draft'] = 'The latest result.'
        ready = f.ready()
        originals = f.packet(ready)['retrieved']
        self.assertTrue(any(e['text'] == small for e in originals))
        self.assertFalse(any(e['text'] in (large, 'Earlier operation.') for e in originals))
        self.assertLessEqual(sum(len(fixtures.checker.context.wire_encoded(e)) for e in originals), fixtures.checker.context.UNIT_BYTES)

    def test_observation_ids_are_local_to_a_reply_not_global_state_keys(self):
        f = self.fixture
        f.payload['evidence'] = [{'id': 'verification', 'output': 'VERIFIED'}]
        ready = f.update(f.ready())
        source = next(s for s in ready['transaction']['sources'].values() if s['kind'] == 'evidence')
        original = fixtures.checker.context.ref(source, 'output')
        ready = f.reply(ready, dict(kind='need_refs', refs=[original]))
        observation = dict(id='obs-1', kind='fact', text='The result says VERIFIED.', refs=[original], related=[], target=dict(name='result', revision_refs=[]), validity='current')
        ready = f.reply(ready, dict(kind='need_refs', refs=[original], additions=[observation]))
        self.assertEqual(f.judgment(ready)['status'], 'checked')
        f.payload['draft'] = 'A revised answer.'
        ready = f.ready()
        observation = dict(observation, text='The result does not measure latency.')
        ready = f.reply(ready, dict(kind='need_refs', refs=[original], additions=[observation]))
        self.assertEqual({o['text'] for o in ready['transaction']['retrieval_observations']}, {'The result says VERIFIED.', 'The result does not measure latency.'})

    def test_observation_history_is_retained_without_exhausting_the_model_input(self):
        f = self.fixture
        f.payload['evidence'] = [{'id': 'verification', 'output': 'VERIFIED'}]
        ready = f.update(f.ready())
        source = next(s for s in ready['transaction']['sources'].values() if s['kind'] == 'evidence')
        original = fixtures.checker.context.ref(source, 'output')
        rng = random.Random(71)
        ready['transaction']['retrieval_observations'] = [dict(id=f'observation-{n}', kind='fact',
            text=''.join(rng.choices('abcdefghijklmnopqrstuvwxyz0123456789', k=2000)), refs=[original], related=[],
            target=dict(name='result', revision_refs=[]), validity='current') for n in range(250)]
        ready = fixtures.checker.context_ready(ready['transaction'])
        self.assertEqual(ready['status'], 'ready')
        data = f.packet(ready)
        self.assertEqual(len(ready['transaction']['retrieval_observations']), 250)
        self.assertGreater(data['retrieval_observations_omitted'], 0)
        self.assertEqual(len(data['retrieval_observations']) + data['retrieval_observations_omitted'], 250)

    def test_cached_source_lookup_has_the_same_result_shape(self):
        f = self.fixture
        f.payload['evidence'] = [{'id': 'verification', 'output': 'VERIFIED'}]
        ready = f.update(f.ready())
        source = next(s for s in ready['transaction']['sources'].values() if s['kind'] == 'evidence')
        query = dict(id=source['id'], rev=source['rev'], field='output', literal='VERIFIED', after=0)
        ready = f.reply(ready, dict(kind='need_refs', refs=[query]))
        original = f.packet(ready)['locator_results']
        ready = f.reply(ready, dict(kind='need_refs', refs=[query]))
        self.assertEqual(f.packet(ready)['locator_results'], original)

    def test_persistent_observations_require_original_sources_not_generated_views(self):
        f = self.fixture
        ready = f.ready()
        scope = f.packet(ready)['user_scope']['ref']
        observation = dict(id='summary', kind='unresolved', text='The generated view needs interpretation.', refs=[scope],
                           related=[], target=dict(name='view', revision_refs=[]), validity='current')
        ready = f.reply(ready, dict(kind='need_refs', refs=[scope], additions=[observation]))
        self.assertEqual(ready['transaction'].get('retrieval_observations', []), [])
        self.assertIn('original', f.packet(ready)['validation_feedback'])

    def test_joint_grounding_leaves_room_for_the_next_original(self):
        f = self.fixture
        rng = random.Random(115)
        text = lambda n: ''.join(rng.choices('abcdefghijklmnopqrstuvwxyz0123456789', k=n))
        f.payload['evidence'] = [dict(id='ground', output=text(380000)), dict(id='needed', output='NEEDED' * 200)]
        rules = text(70000)
        with fixtures.patch.object(fixtures.checker, 'response_rules', lambda: rules):
            base = f.ready()['transaction']
            sources = sorted((s for s in base['sources'].values() if s['kind'] == 'evidence'), key=lambda s:s['seq'])
            low, high, best = 0, 380000, None
            while low <= high:
                length = (low + high) // 2
                tx = deepcopy(base)
                wanted = fixtures.checker.context.ref(sources[0], 'output', 0, length)
                fact = dict(id='prior-fact', kind='fact', text='This original contains ASCII fixture data.', refs=[wanted],
                            related=[], target=dict(name='fixture', revision_refs=[]), validity='current')
                tx['candidate_state']['items'] = [fact]
                try:
                    ready = fixtures.checker.context_ready(tx)
                except ValueError as error:
                    self.assertIn('context input limit', str(error))
                    high = length - 1
                    continue
                if any(g['ref'] == wanted for g in f.packet(ready).get('grounding', [])):
                    best, low = ready, length + 1
                else:
                    high = length - 1
            self.assertIsNotNone(best)
            ready = fixtures.checker.context_ready(best['transaction'])
            needed = fixtures.checker.context.ref(sources[1], 'output')
            ready = f.reply(ready, dict(kind='need_refs', refs=[needed]))
            self.assertEqual(ready['status'], 'ready', ready.get('reason'))
            self.assertTrue(any(e['ref'] == needed for e in f.packet(ready)['retrieved']))

    def test_qualified_answer_can_answer_a_question_after_delivery(self):
        f = self.fixture
        f.payload.update(latest_user='Can the current state be verified?', draft='Verification is blocked by the permission denial.',
                         evidence=[dict(id='attempt', output='Permission denied', failed=True)])
        ready = f.ready()
        user = f.packet(ready)['users'][0]['ref']
        question = dict(id='question', kind='question', text='Can the current state be verified?', refs=[user], related=[],
                        target=dict(name='verification', revision_refs=[]), validity='current')
        ready = f.update(ready, additions=[question])
        data = f.packet(ready)
        draft = data['answers'][0]['ref']
        source = next(s for s in ready['transaction']['sources'].values() if s['kind'] == 'evidence')
        original = fixtures.checker.context.ref(source, 'output')
        ready = f.reply(ready, dict(kind='need_refs', refs=[original]))
        claim = dict(id='limitation', answer_ref=draft, text=f.payload['draft'], requirement_ids=['question'],
                     evidence=[dict(ref=original, relation='unresolved')], verdict='qualified')
        result = f.judgment(ready, claims=[claim], decisions=[dict(item_id='question', action='retire', basis='answered',
                            refs=[draft], reason='The answer explains the verified limit on checking the state.')])
        self.assertEqual(result['status'], 'checked', result.get('reason') or result.get('transaction', {}).get('validation_feedback'))
        self.assertEqual(len(result['context_state']['items']), 1)
        confirmed = fixtures.checker.context.confirm_display(f.tmp.name, result['display_receipt'], result['text'])
        self.assertEqual(confirmed['context_state']['items'], [])

    def test_qualified_status_cannot_close_an_action_requirement(self):
        f = self.fixture
        f.payload.update(latest_user='Verify the current state.', draft='Verification is blocked by the permission denial.',
                         evidence=[dict(id='attempt', output='Permission denied', failed=True)])
        ready = f.ready()
        user = f.packet(ready)['users'][0]['ref']
        action = dict(id='action', kind='requirement', text='Verify the current state.', refs=[user], related=[],
                      target=dict(name='verification', revision_refs=[]), validity='current')
        ready = f.update(ready, additions=[action])
        draft = f.packet(ready)['answers'][0]['ref']
        source = next(s for s in ready['transaction']['sources'].values() if s['kind'] == 'evidence')
        original = fixtures.checker.context.ref(source, 'output')
        ready = f.reply(ready, dict(kind='need_refs', refs=[original]))
        claim = dict(id='limitation', answer_ref=draft, text=f.payload['draft'], requirement_ids=['action'],
                     evidence=[dict(ref=original, relation='unresolved')], verdict='qualified')
        for basis, ground in [('completed', original), ('answered', draft)]:
            ready = f.judgment(ready, claims=[claim], decisions=[dict(item_id='action', action='retire', basis=basis,
                              refs=[ground], reason='Attempt to close the action from a qualified status.')])
            self.assertEqual(ready['status'], 'ready')
            self.assertIn('cannot close', f.packet(ready)['validation_feedback'])

    def test_cached_lookup_can_fetch_an_original_that_is_no_longer_visible(self):
        f = self.fixture
        noise = ''.join(random.Random(71).choices('abcdefghijklmnopqrstuvwxyz0123456789', k=20000))
        f.payload['evidence'] = [{'id': 'verification', 'output': noise[:10000] + 'VERIFIED' + noise[10000:]}]
        ready = f.update(f.ready())
        answer = f.packet(ready)['answers'][0]
        lookup = dict(kind='need_refs', focus_refs=[answer['ref']], refs=[dict(scope='archive', field='output', literal='VERIFIED', before_seq=0)])
        ready = f.reply(ready, lookup)
        ready['transaction']['retrieved'] = []
        ready = fixtures.checker.context_ready(ready['transaction'])
        ready = f.reply(ready, lookup)
        self.assertEqual(ready['status'], 'ready')
        self.assertTrue(any('VERIFIED' in e['text'] for e in f.packet(ready)['retrieved']))
        self.assertGreaterEqual(len(ready['transaction']['archive_searches']), 1)

    def test_mixed_lookup_batch_reuses_completed_results(self):
        f = self.fixture
        f.payload['evidence'] = [{'id': 'verification', 'output': 'FIRST\nSECOND'}]
        ready = f.update(f.ready())
        answer = f.packet(ready)['answers'][0]
        first = dict(scope='archive', field='output', literal='FIRST', before_seq=0)
        second = dict(scope='archive', field='output', literal='SECOND', before_seq=0)
        ready = f.reply(ready, dict(kind='need_refs', focus_refs=[answer['ref']], refs=[first]))
        ready = f.reply(ready, dict(kind='need_refs', focus_refs=[answer['ref']], refs=[first, second]))
        self.assertEqual(ready['status'], 'ready')
        self.assertEqual(len(ready['transaction']['archive_searches']), 2)
        self.assertEqual(len(f.packet(ready)['locator_results']), 2)


if __name__ == '__main__':
    unittest.main()
