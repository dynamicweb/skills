"""Mutation controls for the ledger gate. Isolated snapshots only; no host access."""
import json
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from validate_ledger import validate_ledgers


class LedgerValidationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.repo = Path(self.temp.name)
        self.assets = self.repo / 'skills/dw-demo-ledger/assets'
        self.root = self.assets / 'releases/1.0.0'
        source = Path(__file__).resolve().parents[2] / 'skills/dw-demo-ledger/assets'
        self.assets.mkdir(parents=True)
        for file in [*source.glob('*.schema.json'), source / 'handlers.json']:
            shutil.copyfile(file, self.assets / file.name)
        self.write('manifest.json', {'schema': 1, 'dwVersion': '1.0.0', 'functionsGlob': 'functions/*.json', 'coverageGlob': 'coverage/*.json'})
        self.function = {'id': 'test.function', 'area': 'test', 'name': 'Test', 'skill': 'dw-demo-ledger', 'status': 'candidate', 'requires': [], 'inputs': [], 'checks': ['probes/test/count.json'], 'notApplicable': [], 'sources': []}
        self.check = {'schema': 1, 'id': 'test.function.count', 'functionId': 'test.function', 'intent': {'proves': 'Rows exist', 'level': 'configured', 'scope': 'all'}, 'assertion': {'kind': 'scalar', 'op': 'ge', 'value': 1}, 'bindings': [{'id': 'sql', 'surface': 'sql', 'status': 'implemented', 'handler': 'sql-scalar', 'localOnly': True, 'query': 'SELECT 1'}]}
        self.coverage = {'schema': 1, 'area': 'test', 'retrieved': '2026-11-11', 'sources': [], 'claims': [{'claim': 'Rows exist', 'url': 'https://example.invalid/docs', 'functionId': 'test.function'}], 'gaps': []}
        self.save()

    def write(self, path, value):
        file = self.root / path
        file.parent.mkdir(parents=True, exist_ok=True)
        file.write_text(json.dumps(value), encoding='utf-8')

    def save(self):
        self.write('functions/test.json', {'schema': 1, 'area': 'test', 'functions': [self.function]})
        self.write('probes/test/count.json', self.check)
        self.write('coverage/test.json', self.coverage)

    def test_valid_snapshot_and_area_coverage(self):
        self.assertEqual([], validate_ledgers(self.repo))

    def test_missing_probe_and_duplicate_function(self):
        (self.root / 'probes/test/count.json').unlink()
        self.write('functions/other.json', {'schema': 1, 'area': 'other', 'functions': [self.function]})
        errors = '\n'.join(validate_ledgers(self.repo))
        self.assertIn('unreadable JSON', errors)
        self.assertIn('duplicate function id', errors)

    def test_unknown_handler_and_nonlocal_sql(self):
        self.check['bindings'][0].update(handler='invented', localOnly=False)
        self.save()
        errors = '\n'.join(validate_ledgers(self.repo))
        self.assertIn('not allowlisted', errors)
        self.assertIn('localOnly', errors)
        self.assertIn('schema validation failed', errors)

    def test_broken_requires_and_coverage(self):
        self.function['requires'] = [{'kind': 'capability', 'id': 'test.absent', 'expected': True}]
        self.coverage['claims'][0]['functionId'] = 'test.absent'
        self.save()
        errors = '\n'.join(validate_ledgers(self.repo))
        self.assertIn('requires unknown function', errors)
        self.assertIn('coverage functionId does not resolve', errors)

    def test_duplicate_check_and_wrong_owner(self):
        self.function['checks'].append('probes/test/second.json')
        self.save()
        copy = dict(self.check, functionId='test.other')
        self.write('probes/test/second.json', copy)
        errors = '\n'.join(validate_ledgers(self.repo))
        self.assertIn('duplicate check id', errors)
        self.assertIn('probe owner differs', errors)

    def test_schema_required_fields_and_path_escape(self):
        del self.check['assertion']['op']
        self.function['checks'].append('../../escape.json')
        self.coverage['claims'][0]['excluded'] = {'reason': 'Conflicting classification'}
        self.save()
        errors = '\n'.join(validate_ledgers(self.repo))
        self.assertIn('invalid probe path', errors)
        self.assertIn('schema validation failed', errors)

    def test_edit_layout_and_field_placement_limits_are_data(self):
        self.check['assertion'] = {'kind': 'offenders'}
        good = {'id': 'sql', 'surface': 'sql', 'status': 'implemented', 'handler': 'pim-edit-layout', 'localOnly': True,
                'arguments': {'aspect': 'tabs-per-family', 'maxTabs': 5}}
        self.check['bindings'] = [good]
        self.save()
        self.assertEqual([], validate_ledgers(self.repo))
        red = [
            ({'aspect': 'pretty'}, "unknown edit-layout aspect 'pretty'"),
            ({'aspect': 'tabs-per-family'}, 'states no maxTabs'),
            ({'aspect': 'scannable', 'maxEditorsPerGroup': 12}, 'states no maxEditorsPerGroup and maxEditorsPerTab'),
            ({'aspect': 'names'}, 'lists no banned name or pattern'),
        ]
        for arguments, message in red:
            self.check['bindings'] = [dict(good, arguments=arguments)]
            self.save()
            self.assertIn(message, '\n'.join(validate_ledgers(self.repo)))
        self.check['bindings'] = [{'id': 'sql', 'surface': 'sql', 'status': 'implemented', 'handler': 'pim-field-placement', 'localOnly': True}]
        self.save()
        self.assertIn('states no minSharePct between 1 and 100', '\n'.join(validate_ledgers(self.repo)))
        self.check['bindings'][0]['arguments'] = {'minSharePct': 50}
        self.save()
        self.assertEqual([], validate_ledgers(self.repo))


if __name__ == '__main__':
    unittest.main()
