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

    def errors_for(self, bindings=None, assertion=None):
        if bindings is not None:
            self.check['bindings'] = bindings
        if assertion is not None:
            self.check['assertion'] = assertion
        self.save()
        return '\n'.join(validate_ledgers(self.repo))

    def test_sql_text_is_one_read_only_select(self):
        sql = dict(self.check['bindings'][0])
        message = 'not a single read-only SELECT statement'
        for query in ['DELETE FROM EcomProducts', 'SELECT 1 CREATE TABLE dbo.LedgerProbe(a int)',
                      'SELECT 1 GRANT CONTROL ON DATABASE::Demo TO public', 'SELECT 1 SELECT 2']:
            self.assertIn(message, self.errors_for([dict(sql, query=query)]), query)
        self.assertEqual('', self.errors_for([dict(sql, query="SELECT COUNT(*) FROM T WHERE a = N'{lang}'{inScope}")]))
        # A not-applicable ground probe is read through the same gate.
        self.function['notApplicable'] = [{'id': 'not-used', 'when': 'Nothing uses it', 'probe': 'probes/test/ground.json'}]
        self.write('probes/test/ground.json', dict(self.check, id='test.function.ground',
                                                    bindings=[dict(sql, query='DELETE FROM EcomProducts')]))
        errors = self.errors_for([sql])
        self.assertIn('probes/test/ground.json: SQL binding is ' + message, errors)

    def test_mcp_and_admin_operations_are_allowlisted_reads(self):
        mcp = {'id': 'mcp', 'surface': 'mcp', 'status': 'implemented', 'handler': 'mcp-count', 'operation': 'get_currencies'}
        self.assertEqual('', self.errors_for([mcp]))
        red = dict(mcp, operation='delete_product', arguments={'productId': '{pimShop}'})
        self.assertIn('MCP tool is not an allowlisted read tool: delete_product', self.errors_for([red]))
        self.assertIn('not an allowlisted read tool: save_product', self.errors_for([dict(mcp, requiredTools=['save_product'])]))
        del red['operation']
        self.assertIn('MCP binding names no operation', self.errors_for([red]))
        admin = {'id': 'admin', 'surface': 'admin-api', 'status': 'implemented', 'handler': 'admin-query-count',
                 'operation': 'FeaturesAll', 'projection': {'rowsPath': 'model.data'}}
        self.assertEqual('', self.errors_for([admin]))
        self.assertIn('Admin operation is not an allowlisted read query: ProductSave', self.errors_for([dict(admin, operation='ProductSave')]))
        self.assertIn('admin-query-count needs projection.rowsPath', self.errors_for([dict(admin, projection={})]))
        flag = dict(admin, handler='admin-feature-flag', projection={})
        self.assertIn('admin-feature-flag needs arguments.featureTypeName', self.errors_for([flag]))
        self.assertEqual('', self.errors_for([dict(flag, arguments={'featureTypeName': 'Some.Feature'})]))

    def test_assertion_kind_fits_the_handler(self):
        self.assertIn('assertion kind offenders does not fit handler sql-scalar', self.errors_for(assertion={'kind': 'offenders'}))
        mcp = {'id': 'mcp', 'surface': 'mcp', 'status': 'implemented', 'handler': 'mcp-count', 'operation': 'get_currencies'}
        self.assertIn('assertion kind offenders does not fit handler mcp-count', self.errors_for([mcp]))
        offenders = {'id': 'sql', 'surface': 'sql', 'status': 'implemented', 'handler': 'sql-offenders', 'localOnly': True,
                     'query': 'SELECT Id FROM T'}
        self.assertEqual('', self.errors_for([offenders]))

    def test_file_bindings_state_their_scope(self):
        files = {'id': 'file', 'surface': 'file', 'status': 'implemented', 'handler': 'files-count'}
        self.assertIn('files-count needs a path', self.errors_for([files]))
        self.assertIn('files-count needs a path', self.errors_for([dict(files, arguments={'folder': 'System'})]))
        self.assertEqual('', self.errors_for([dict(files, arguments={'folder': 'System', 'filter': '*.xml'})]))
        self.assertEqual('', self.errors_for([dict(files, path='System/*.xml')]))
        setting = dict(files, handler='settings-value', path='GlobalSettings.config')
        self.assertIn('settings-value needs arguments.key', self.errors_for([setting]))
        self.assertEqual('', self.errors_for([dict(setting, arguments={'key': '/Globalsettings/A', 'equals': True})]))

    def test_manifest_identity_and_every_snapshot_json(self):
        good = {'schema': 1, 'dwVersion': '1.0.0', 'functionsGlob': 'functions/*.json', 'coverageGlob': 'coverage/*.json'}
        for bad in [{k: v for k, v in good.items() if k != 'dwVersion'}, dict(good, schema=2)]:
            self.write('manifest.json', bad)
            self.assertIn('manifest needs schema 1 and a dwVersion', '\n'.join(validate_ledgers(self.repo)))
        self.write('manifest.json', good)
        for path in ['delta.json', 'delta-review.json', 'evidence/admission.json']:
            file = self.root / path
            file.parent.mkdir(parents=True, exist_ok=True)
            file.write_text('{"cut": ', encoding='utf-8')
            self.assertIn(f'{path}: unreadable JSON', '\n'.join(validate_ledgers(self.repo)))
            file.write_text('{}', encoding='utf-8')
        self.assertEqual([], validate_ledgers(self.repo))

    def test_flag_and_capability_expectations_are_booleans(self):
        self.function['requires'] = [{'kind': 'flag', 'id': 'Some.Feature', 'expected': 'false'}]
        self.save()
        self.assertIn('schema validation failed', '\n'.join(validate_ledgers(self.repo)))
        self.function['requires'] = [{'kind': 'flag', 'id': 'Some.Feature', 'expected': False},
                                     {'kind': 'app', 'id': 'Some.App', 'expected': '1.0.0'}]
        self.save()
        self.assertEqual([], validate_ledgers(self.repo))

    def test_profile_changes_expectations_only(self):
        profile = self.assets / 'profiles/test.json'
        profile.parent.mkdir()
        profile.write_text(json.dumps({'schema': 1, 'id': 'test', 'expectations': {'test.function.count': {'kind': 'offenders'}}}), encoding='utf-8')
        self.assertIn('profile may change only op, value and minimumSubjects: test.function.count states kind', '\n'.join(validate_ledgers(self.repo)))
        profile.write_text(json.dumps({'schema': 1, 'id': 'test', 'expectations': {'test.function.count': {'op': 'ge', 'value': 2}}}), encoding='utf-8')
        self.assertEqual([], validate_ledgers(self.repo))


    def test_delivery_binding_is_an_allowlisted_read_route_with_a_projection(self):
        binding = {'id': 'dwapi', 'surface': 'dwapi', 'status': 'implemented', 'handler': 'dwapi-count',
                   'operation': 'content/areas', 'projection': {'rowsPath': '$'}}
        self.check['bindings'] = [binding]
        self.save()
        self.assertEqual([], validate_ledgers(self.repo))
        for route in ('users/info/profiles/switch', 'users/authenticate/refresh', 'ecommerce/carts/create'):
            binding['operation'] = route
            self.save()
            self.assertIn('delivery route is not an allowlisted read route', '\n'.join(validate_ledgers(self.repo)))
        binding.update(operation='content/areas', projection={})
        self.save()
        self.assertIn('dwapi-count needs projection.rowsPath', '\n'.join(validate_ledgers(self.repo)))
        del binding['operation']
        self.save()
        self.assertIn('delivery binding names no operation', '\n'.join(validate_ledgers(self.repo)))

    def test_persona_sign_in_uses_its_own_route_lists(self):
        binding = {'id': 'signin', 'surface': 'dwapi', 'status': 'implemented', 'handler': 'dwapi-persona-sign-in',
                   'operation': 'users/authenticate', 'arguments': {'readAs': 'users/info'}}
        self.check['bindings'] = [binding]
        self.save()
        self.assertEqual([], validate_ledgers(self.repo))
        binding['operation'] = 'users/authenticate/refresh'
        self.save()
        self.assertIn('sign-in route is not an allowlisted sign-in route', '\n'.join(validate_ledgers(self.repo)))
        binding.update(operation='users/authenticate', arguments={'readAs': 'users/info/profiles/switch'})
        self.save()
        self.assertIn('needs arguments.readAs', '\n'.join(validate_ledgers(self.repo)))
        # The sign-in route is never an anonymous read for dwapi-count.
        self.check['bindings'] = [{'id': 'dwapi', 'surface': 'dwapi', 'status': 'implemented', 'handler': 'dwapi-count',
                                   'operation': 'users/authenticate', 'projection': {'rowsPath': '$'}}]
        self.save()
        self.assertIn('delivery route is not an allowlisted read route', '\n'.join(validate_ledgers(self.repo)))

    def test_repository_file_handlers_state_scope_and_generated_table(self):
        self.check['assertion'] = {'kind': 'offenders', 'minimumSubjects': 1}
        facets = {'id': 'facets', 'surface': 'file', 'status': 'implemented', 'handler': 'files-facet-analyzed',
                  'path': 'System/Repositories/*/*.facets',
                  'arguments': {'generated': {'X.Extender': {'fields': {'A': False, 'B': 'default-fields'}, 'prefixes': {'C_': 'default-fields-if-text'}}}}}
        queries = {'id': 'queries', 'surface': 'file', 'status': 'implemented', 'handler': 'files-query-constant-macros',
                   'path': 'System/Repositories/*/*.query'}
        self.check['bindings'] = [facets, queries]
        self.save()
        self.assertEqual([], validate_ledgers(self.repo))
        facets['arguments']['generated']['X.Extender']['fields']['A'] = 'maybe'
        del queries['path']
        self.save()
        errors = '\n'.join(validate_ledgers(self.repo))
        self.assertIn('state is true, false, default-fields or default-fields-if-text', errors)
        self.assertIn('files-query-constant-macros needs a path pattern', errors)
        facets['arguments'] = {}
        self.save()
        self.assertIn('files-facet-analyzed needs arguments.generated', '\n'.join(validate_ledgers(self.repo)))
        self.check['assertion'] = {'kind': 'scalar', 'op': 'eq', 'value': 0}
        facets['arguments'] = {'generated': {'X.Extender': {'fields': {'A': False}}}}
        queries['path'] = 'System/Repositories/*/*.query'
        self.save()
        self.assertIn('does not fit handler files-facet-analyzed', '\n'.join(validate_ledgers(self.repo)))

    def test_app_expectation_is_true_a_version_or_a_minimum(self):
        for expected in (True, '10.24.2', {'min': '0.6.0-beta'}):
            self.function['requires'] = [{'kind': 'app', 'id': 'Example.App', 'expected': expected}]
            self.save()
            self.assertEqual([], validate_ledgers(self.repo), expected)
        for expected in (False, '', 3, {'max': '1.0.0'}, {'min': '1.0.0', 'max': '2.0.0'}):
            self.function['requires'] = [{'kind': 'app', 'id': 'Example.App', 'expected': expected}]
            self.save()
            self.assertIn('schema validation failed', '\n'.join(validate_ledgers(self.repo)), expected)

    def second_function(self, **change):
        other = dict(self.function, id='test.other', checks=[], requires=[], notApplicable=[])
        other.update(change)
        self.write('functions/test.json', {'schema': 1, 'area': 'test', 'functions': [self.function, other]})
        claims = self.coverage['claims'] + [{'claim': 'Other', 'url': 'https://example.invalid/docs', 'functionId': 'test.other'}]
        self.write('coverage/test.json', dict(self.coverage, claims=claims))

    def test_function_requirements_do_not_form_a_circle(self):
        self.function['requires'] = [{'kind': 'capability', 'id': 'test.other', 'expected': True}]
        self.second_function()
        self.assertEqual([], validate_ledgers(self.repo))
        self.second_function(requires=[{'kind': 'capability', 'id': 'test.function', 'expected': True}])
        self.assertIn('circular function requirement: test.function -> test.other -> test.function', '\n'.join(validate_ledgers(self.repo)))
        self.second_function(notApplicable=[{'id': 'replaced', 'when': 'Other one', 'requiresFunction': 'test.function'}])
        self.assertIn('circular function requirement', '\n'.join(validate_ledgers(self.repo)))

    def test_ground_cites_a_known_other_function(self):
        self.function['notApplicable'] = [{'id': 'replaced', 'when': 'Other one', 'requiresFunction': 'test.other'}]
        self.second_function()
        self.assertEqual([], validate_ledgers(self.repo))
        for cited in ('test.absent', 'test.function'):
            self.function['notApplicable'][0]['requiresFunction'] = cited
            self.second_function()
            self.assertIn(f'ground replaced cites unknown function {cited}', '\n'.join(validate_ledgers(self.repo)))

    def test_ground_names_only_checks_of_its_function(self):
        self.function['notApplicable'] = [{'id': 'scoped', 'when': 'One check only', 'checks': ['test.function.count']}]
        self.save()
        self.assertEqual([], validate_ledgers(self.repo))
        self.function['notApplicable'][0]['checks'] = ['test.other.count']
        self.save()
        self.assertIn('ground scoped names test.other.count, which is not a check of this function', '\n'.join(validate_ledgers(self.repo)))
        self.function['notApplicable'][0]['checks'] = []
        self.save()
        self.assertNotEqual([], validate_ledgers(self.repo))

    def test_function_without_a_coverage_claim(self):
        self.coverage['claims'] = []
        self.save()
        self.assertIn('test.function: function has no coverage claim', '\n'.join(validate_ledgers(self.repo)))
        # The rule is strict: no list of exempt functions is read any more.
        baseline = self.repo / 'scripts/ledger-coverage-baseline.json'
        baseline.parent.mkdir(parents=True, exist_ok=True)
        baseline.write_text(json.dumps({'1.0.0': ['test.function']}), encoding='utf-8')
        self.assertIn('test.function: function has no coverage claim', '\n'.join(validate_ledgers(self.repo)))

    def test_description_requirement_template_proves_and_subjects(self):
        self.function['requires'] = [{'kind': 'app', 'id': 'Some connector app', 'expected': True}]
        self.check['intent']['proves'] = 'Test: count satisfies the selected profile assertion.'
        self.save()
        errors = '\n'.join(validate_ledgers(self.repo))
        self.assertIn('requirement id is a description', errors)
        self.assertIn('intent.proves is the template text', errors)
        self.setUp()
        self.check['assertion'] = {'kind': 'offenders', 'minimumSubjects': 1}
        self.check['bindings'][0]['handler'] = 'sql-offenders'
        self.save()
        self.assertIn('sql-offenders with minimumSubjects needs a subjectsQuery', '\n'.join(validate_ledgers(self.repo)))
        self.check['bindings'][0]['subjectsQuery'] = 'SELECT 1 DROP TABLE x'
        self.save()
        errors = '\n'.join(validate_ledgers(self.repo))
        self.assertNotIn('needs a subjectsQuery', errors)
        self.assertIn('not a single read-only SELECT', errors)
        self.check['bindings'][0]['subjectsQuery'] = 'SELECT COUNT(*) FROM T'
        self.save()
        self.assertEqual([], validate_ledgers(self.repo))


class PrivateLinkTests(unittest.TestCase):
    def setUp(self):
        import importlib.util
        spec = importlib.util.spec_from_file_location('validate_skills', Path(__file__).resolve().parents[1] / 'validate-skills.py')
        self.module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.module)

    def test_private_repository_link_is_found(self):
        text = 'ok\nsee https://github.com/truvio-commerce/Truvio.Commerce.CpqStudio/blob/abc/README.md\n'
        self.assertEqual([2], [line for line, _ in self.module.private_repository_links(text)])
        self.assertEqual(1, len(self.module.private_repository_links('GITHUB.COM/Truvio-Commerce/truvio.commerce.cpqstudio')))

    def test_public_repository_and_plain_name_pass(self):
        text = ('https://github.com/dynamicweb/skills/blob/x/README.md\nTruvio.Commerce.CpqStudio = 0.7.0\n'
                'https://github.com/truvio-commerce/Truvio.Commerce.CpqStudioX')
        self.assertEqual([], self.module.private_repository_links(text))


if __name__ == '__main__':
    unittest.main()

