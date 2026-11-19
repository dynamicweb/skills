"""Mutation controls for the recipe gate. Isolated fixtures only; no host access."""
import copy
import json
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from validate_recipes import validate_recipes

SOURCE = Path(__file__).resolve().parents[2]

PAGES_FIND = {"id": "mcp-children", "surface": "mcp", "status": "implemented", "operation": "get_pages_by_parent_id",
              "arguments": {"parentId": "{step.pages[item.parent].id|0}", "areaId": "{build.areaId}"}, "rows": "data",
              "match": {"menuText": "{item.menuText}"}, "produces": {"id": "id"}, "source": "skills/x.md"}
RECIPE = {
    "schema": 1, "id": "test.function", "name": "Test pages", "functions": ["test.function"], "skill": "dw-demo-ledger",
    "inputs": {"section": "content.pages", "required": ["pages"]},
    "modes": {"mcpOnly": {"usable": True, "reason": "Every step has MCP bindings."},
              "hosted": {"usable": True, "reason": "No step needs SQL."}, "local": {"usable": True}, "layerDelivered": "verify"},
    "steps": [{
        "id": "pages", "title": "Pages", "forEach": "pages[*]", "key": "{item.menuText}", "source": "skills/x.md",
        "find": {"bindings": [PAGES_FIND]},
        "bindings": [{"id": "mcp-create", "surface": "mcp", "status": "implemented", "source": "skills/x.md",
                      "create": {"operation": "save_pages", "arguments": {"pages": [{"id": 0, "menuText": "{item.menuText}", "parentPageId": "{step.pages[item.parent].id|0}"}]}},
                      "readBack": dict(PAGES_FIND)}]
    }],
    "debts": ["flush:Dynamicweb.Content.PageService"],
    "verify": {"checkIds": ["test.function.count"], "probes": [
        {"id": "unique", "title": "Unique", "forEach": "pages[*]", "minimumSubjects": 1, "bindings": [
            dict(PAGES_FIND, assert_={})]}]},
    "provenOn": [], "traps": ["A trap."]
}
RECIPE["verify"]["probes"][0]["bindings"][0].pop("assert_")
RECIPE["verify"]["probes"][0]["bindings"][0].pop("produces")
RECIPE["verify"]["probes"][0]["bindings"][0]["assert"] = {"kind": "count", "op": "eq", "value": 1}


class RecipeValidationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.repo = Path(self.temp.name)
        assets_src = SOURCE / "skills/dw-demo-ledger/assets"
        self.assets = self.repo / "skills/dw-demo-ledger/assets"
        self.assets.mkdir(parents=True)
        for name in ("recipe.schema.json", "recipe-input.schema.json", "handlers.json"):
            shutil.copyfile(assets_src / name, self.assets / name)
        (self.repo / "skills/dw-demo-ledger/SKILL.md").write_text("---\nname: dw-demo-ledger\n---\n", encoding="utf-8")
        (self.repo / "scripts/mcp-tools").mkdir(parents=True)
        for name in ("index.json", "0.6.0.json"):
            shutil.copyfile(SOURCE / "scripts/mcp-tools" / name, self.repo / "scripts/mcp-tools" / name)
        release = self.assets / "releases/1.0.0"
        (release / "functions").mkdir(parents=True)
        (release / "probes/test").mkdir(parents=True)
        (release / "manifest.json").write_text(json.dumps({"schema": 1, "dwVersion": "1.0.0"}), encoding="utf-8")
        function = {"id": "test.function", "area": "test", "skill": "dw-demo-ledger", "checks": ["probes/test/count.json"]}
        (release / "functions/test.json").write_text(json.dumps({"schema": 1, "area": "test", "functions": [function]}), encoding="utf-8")
        (release / "probes/test/count.json").write_text(json.dumps({"id": "test.function.count", "functionId": "test.function"}), encoding="utf-8")
        self.recipe = copy.deepcopy(RECIPE)
        self.save()

    def save(self):
        path = self.assets / "recipes/test/test.function.json"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(self.recipe), encoding="utf-8")

    def errors(self):
        self.save()
        return "\n".join(validate_recipes(self.repo))

    def test_valid_recipe(self):
        self.assertEqual("", self.errors())

    def test_declared_mode_must_match_the_bindings(self):
        self.recipe["steps"][0]["bindings"][0]["status"] = "planned"
        self.recipe["steps"][0]["bindings"][0]["reason"] = "Shape not documented."
        errors = self.errors()
        self.assertIn("modes.mcpOnly.usable must be false", errors)
        self.assertIn("modes.hosted.usable must be false", errors)

    def test_write_off_the_allowlist_and_unknown_tool(self):
        self.recipe["steps"][0]["bindings"][0]["create"]["operation"] = "delete_pages"
        self.assertIn("not on the recipe write allowlist", self.errors())
        self.recipe["steps"][0]["bindings"][0]["create"]["operation"] = "save_page_invented"
        self.assertIn("not in the MCP tool registry", self.errors())

    def test_read_off_the_read_allowlist(self):
        self.recipe["steps"][0]["find"]["bindings"][0]["operation"] = "search_pages"
        self.assertIn("not on mcpReadTools", self.errors())

    def test_tokens_resolve_against_the_input_schema_and_earlier_steps(self):
        self.recipe["steps"][0]["key"] = "{item.title}"
        self.assertIn("does not resolve in the input schema", self.errors())
        self.recipe["steps"][0]["key"] = "{item.menuText}"
        self.recipe["steps"][0]["find"]["bindings"][0]["arguments"]["areaId"] = "{step.later.id}"
        self.assertIn("not this or an earlier step", self.errors())
        self.recipe["steps"][0]["find"]["bindings"][0]["arguments"]["areaId"] = "{secret.item.menuText}"
        self.assertIn("is a secret outside a write or read-back argument", self.errors())

    def test_token_defaults_and_list_paths(self):
        args = self.recipe["steps"][0]["find"]["bindings"][0]["arguments"]
        args["parentId"] = "{step.pages[item.parent].id|item.menuText}"
        args["areaId"] = "{item.rows[*].sort}"
        self.assertEqual("", self.errors())
        args["parentId"] = "{step.pages[item.parent].id|item.nothing}"
        self.assertIn("does not resolve in the input schema", self.errors())
        args["parentId"] = "{step.pages[item.parent].id|not a path}"
        self.assertIn("neither a JSON literal nor an input path", self.errors())

    def test_sql_is_a_parameterised_single_select(self):
        self.recipe["steps"][0]["find"]["bindings"].insert(0, {
            "surface": "sql", "status": "implemented", "localOnly": True, "source": "skills/x.md",
            "query": "DELETE FROM Page WHERE PageMenuText = '{item.menuText}'"})
        errors = self.errors()
        self.assertIn("a token inside SQL text", errors)
        self.assertIn("not a single read-only SELECT", errors)

    def test_forbidden_strings(self):
        self.recipe["traps"].append("see https://host.example.invalid/admin")
        self.recipe["steps"][0]["bindings"][0]["create"]["arguments"]["password"] = "literal"
        errors = self.errors()
        self.assertIn("holds a URL or host", errors)
        self.assertIn("holds a credential literal", errors)

    def test_functions_and_checks_resolve_in_the_release(self):
        self.recipe["functions"].append("test.absent")
        self.recipe["verify"]["checkIds"].append("other.check")
        errors = self.errors()
        self.assertIn("function test.absent is not in the newest release snapshot", errors)
        self.assertIn("ledger check other.check is not a check", errors)

    def test_implemented_write_needs_an_implemented_read_back(self):
        del self.recipe["steps"][0]["bindings"][0]["readBack"]
        errors = self.errors()
        self.assertIn("needs an implemented read-back", errors)
        self.assertIn("recipe schema validation failed", errors)

    def test_recipe_lives_at_its_id(self):
        self.recipe["id"] = "test.other"
        self.assertIn("must live at recipes/test/test.other.json", self.errors())


if __name__ == "__main__":
    unittest.main()
