"""Hermetic acceptance and demo-reset tests. No ERP, platform or network access."""
from copy import deepcopy
from datetime import datetime, timedelta, timezone
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, ROOT / path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


acceptance = load("bc_acceptance", "skills/dw-integration-bc/scripts/verify_bc_acceptance.py")
demo = load("bc_fixture", "skills/dw-demo-bc/scripts/bc_demo_fixture.py")


class AcceptanceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.now = datetime(2026, 1, 1, tzinfo=timezone.utc)
        self.spec = {"schema": 1, "tenantId": "00000000-0000-0000-0000-000000000001",
                     "environment": "Sandbox", "companyIds": list(demo.COMPANIES),
                     "requiredScenarios": sorted(acceptance.SCENARIOS)}
        (self.root / "erp.json").write_text('{"observed":"ERP source"}', encoding="utf-8")
        (self.root / "buyer.json").write_text('{"observed":"independent buyer read"}', encoding="utf-8")
        self.report = {"schema": 1, "tenantId": self.spec["tenantId"], "environment": "Sandbox",
                       "mode": "live", "measuredAt": self.now.isoformat(), "results": []}
        for scenario in self.spec["requiredScenarios"]:
            for company in self.spec["companyIds"]:
                self.report["results"].append({"scenario": scenario, "companyId": company, "passed": True,
                                               "assertion": "MOCKORDER1 source and buyer view independently agree",
                                               "proofs": ["erp.json", "buyer.json"]})

    def errors(self, mode="live", age=24):
        return acceptance.validate(self.spec, self.report, self.root, mode, age, self.now)

    def test_complete_two_company_report(self):
        self.assertEqual(self.errors(), [])

    def test_missing_scenario_in_second_company(self):
        self.report["results"].pop()
        self.assertTrue(any("missing" in error for error in self.errors()))

    def test_wrong_company_cannot_replace_expected_coverage(self):
        self.report["results"][0]["companyId"] = "00000000-0000-0000-0000-000000000099"
        errors = self.errors()
        self.assertTrue(any("allowlist" in error for error in errors))
        self.assertTrue(any("missing" in error for error in errors))

    def test_mock_cannot_pass_live(self):
        self.report["mode"] = "mock"
        self.assertTrue(any("mock evidence" in error for error in self.errors()))
        self.assertEqual(self.errors(mode="mock"), [])

    def test_row_cannot_override_mode(self):
        self.report["results"][0]["mode"] = "mock"
        self.assertTrue(any("conflicting" in error for error in self.errors()))

    def test_duplicate_result(self):
        self.report["results"].append(deepcopy(self.report["results"][0]))
        self.assertTrue(any("duplicate results" in error for error in self.errors()))

    def test_boolean_is_required(self):
        for value in (False, "true", 1, None):
            with self.subTest(value=value):
                self.report["results"][0]["passed"] = value
                self.assertTrue(any("did not pass" in error for error in self.errors()))

    def test_environment_and_tenant_binding(self):
        self.report["environment"] = "OtherSandbox"
        self.report["tenantId"] = "00000000-0000-0000-0000-000000000099"
        errors = self.errors()
        self.assertTrue(any("environment" in error for error in errors))
        self.assertTrue(any("tenant" in error for error in errors))

    def test_fresh_utc_report_is_required(self):
        for stamp in ((self.now - timedelta(hours=25)).isoformat(),
                      (self.now + timedelta(minutes=6)).isoformat(),
                      "2026-01-01T00:00:00", None, "bad-date"):
            with self.subTest(stamp=stamp):
                self.report["measuredAt"] = stamp
                self.assertTrue(self.errors())

    def test_age_budget_cannot_disable_check(self):
        for age in (-1, 0, float("nan"), float("inf")):
            self.assertTrue(self.errors(age=age))

    def test_missing_empty_and_escaping_proof(self):
        (self.root / "empty.json").touch()
        for proof in ("missing.json", "empty.json", "../outside.json", "C:\\outside.json"):
            with self.subTest(proof=proof):
                self.report["results"][0]["proofs"] = [proof, "buyer.json"]
                self.assertTrue(self.errors())

    def test_two_names_for_identical_content_are_not_independent(self):
        (self.root / "copy.json").write_bytes((self.root / "erp.json").read_bytes())
        self.report["results"][0]["proofs"] = ["erp.json", "copy.json"]
        self.assertTrue(any("different content" in error for error in self.errors()))

    def test_aliases_are_not_independent_paths(self):
        self.report["results"][0]["proofs"] = ["erp.json", "./erp.json"]
        self.assertTrue(self.errors())

    def test_invalid_spec_is_not_vacuous_pass(self):
        for field, value in (("requiredScenarios", []), ("requiredScenarios", ["unknown"]),
                             ("companyIds", []), ("companyIds", ["invalid"]), ("schema", True)):
            with self.subTest(field=field, value=value):
                saved = deepcopy(self.spec)
                self.spec[field] = value
                self.assertTrue(self.errors())
                self.spec = saved

    def test_malformed_results_fail_cleanly(self):
        for value in (None, "passed", [None], [{"scenario": []}], [{"scenario": "products", "companyId": []}]):
            self.report["results"] = value
            self.assertTrue(self.errors())

    def test_cli_rejects_incomplete_template(self):
        script = ROOT / "skills/dw-integration-bc/scripts/verify_bc_acceptance.py"
        args = [sys.executable, str(script), "--spec", str(ROOT / "skills/dw-integration-bc/assets/templates/integration-spec.example.json"),
                "--evidence", str(ROOT / "skills/dw-integration-bc/assets/templates/acceptance.example.json"), "--mode", "live"]
        result = subprocess.run(args, capture_output=True, text=True, check=False)
        self.assertEqual(result.returncode, 1)
        self.assertNotIn("Traceback", result.stderr)


class DemoFixtureTests(unittest.TestCase):
    def test_reset_returns_exact_baseline(self):
        baseline = demo.fixture("baseline")
        changed = demo.fixture("changed")
        self.assertNotEqual(baseline, changed)
        self.assertEqual(baseline, demo.fixture("reset"))
        self.assertEqual(baseline["products"], changed["products"])
        self.assertEqual(baseline["customers"], changed["customers"])
        self.assertNotEqual(baseline["prices"], changed["prices"])
        self.assertNotEqual(baseline["inventory"], changed["inventory"])

    def test_duplicate_business_numbers_remain_company_qualified(self):
        data = demo.fixture("baseline")
        self.assertEqual(len({row["externalKey"] for row in data["products"]}), 4)
        self.assertEqual(len({row["externalKey"] for row in data["customers"]}), 2)
        self.assertEqual({row["owner"] for row in data["shipTo"]}, {"BC"})

    def test_component_amounts_reconcile_without_phantom_export_line(self):
        data = demo.fixture("baseline")
        order = data["orders"][0]
        self.assertEqual(sum(line["amountMinor"] for line in order["lines"]), order["amountMinor"])
        self.assertNotIn("MARKETINGKIT", {line["item"] for line in order["lines"]})

    def test_default_cli_writes_nothing(self):
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / "mock"
            result = subprocess.run([sys.executable, str(ROOT / "skills/dw-demo-bc/scripts/bc_demo_fixture.py"),
                                     "--out", str(target), "--phase", "baseline"], capture_output=True, text=True, check=False)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("DRY RUN", result.stdout)
            self.assertFalse(target.exists())

    def test_apply_change_reset_preserves_other_files(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            baseline = json.dumps(demo.fixture("baseline"), sort_keys=True)
            demo.write_fixture(root, baseline)
            (root / "proof.txt").write_text("keep", encoding="utf-8")
            demo.write_fixture(root, json.dumps(demo.fixture("changed"), sort_keys=True))
            demo.write_fixture(root, json.dumps(demo.fixture("reset"), sort_keys=True))
            self.assertEqual((root / "mock.json").read_text(encoding="utf-8"), baseline)
            self.assertEqual((root / "proof.txt").read_text(encoding="utf-8"), "keep")

    def test_unowned_directory_is_preserved(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "mock.json").write_text("unrelated", encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "ownership marker"):
                demo.write_fixture(root, "{}")
            self.assertEqual((root / "mock.json").read_text(encoding="utf-8"), "unrelated")

    def test_foreign_marker_is_refused(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / ".bc-demo-fixture.json").write_text('{"owner":"other"}', encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "does not match"):
                demo.write_fixture(root, "{}")


if __name__ == "__main__":
    unittest.main()
