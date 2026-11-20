"""Mutation controls for the recipe gate. Isolated fixtures only; no host access."""
import copy
import json
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from validate_recipes import render_index, validate_recipes

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
        for name in ("index.json", "0.6.0.json", "0.6.6.json"):
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

    def test_mcp_since_binding_counts_only_from_its_version(self):
        # A write only a newer server can read back: the conservative modes stay those of the oldest proven
        # version, and the provenOn entry of the newer version states the modes proven there.
        step = self.recipe["steps"][0]
        step["bindings"][0]["status"] = "planned"
        step["bindings"][0]["reason"] = "No read projects it on the older server."
        step["bindings"].append(dict(copy.deepcopy(step["bindings"][0]), id="mcp-newer", status="implemented", mcpSince="0.6.6"))
        step["bindings"][1].pop("reason")
        self.recipe["modes"]["mcpOnly"]["usable"] = False
        self.recipe["modes"]["hosted"]["usable"] = False
        older = {"dwVersion": "1.0.0", "mcpVersion": "0.6.3-BETA", "date": "2026-11-19", "evidence": "run"}
        newer = dict(older, mcpVersion="0.6.6-BETA", modes={"mcpOnly": True, "hosted": True})
        self.recipe["provenOn"] = [older, newer]
        self.assertEqual("", self.errors())
        newer["modes"]["mcpOnly"] = False
        self.assertIn("provenOn mcp 0.6.6-BETA modes must be mcpOnly true, hosted true", self.errors())
        newer.pop("modes")
        self.assertIn("a binding carries mcpSince, so a provenOn entry states the modes", self.errors())
        newer["modes"] = {"mcpOnly": True, "hosted": True}
        self.recipe["modes"]["mcpOnly"]["usable"] = True
        self.assertIn("modes.mcpOnly.usable must be false", self.errors())
        self.recipe["modes"]["mcpOnly"]["usable"] = False
        step["bindings"][1]["mcpSince"] = "0.6.9"
        self.assertIn("mcpSince 0.6.9 has no scripts/mcp-tools registry file", self.errors())

    def test_schema_gate_and_since_are_mcp_only_and_take_member_paths(self):
        find = self.recipe["steps"][0]["find"]["bindings"][0]
        find["requiresSchema"] = {"output": ["data[*].fields"]}
        self.assertEqual("", self.errors())
        find["requiresSchema"] = {"output": ["data[0].fields"]}
        self.assertIn("is not a dotted member path", self.errors())
        find["requiresSchema"] = {"output": ["data[*].fields"]}
        find["surface"] = "admin-api"
        self.assertIn("mcpSince and requiresSchema gate MCP bindings only", self.errors())

    def test_a_tool_of_any_supported_registry_is_known(self):
        # save_product_asset_categories is registered from 0.6.6 only; a binding may name it.
        self.recipe["steps"][0]["bindings"][0]["create"]["operation"] = "save_product_asset_categories"
        self.assertNotIn("not in the MCP tool registry", self.errors())

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

    def test_file_tokens_and_object_entries(self):
        args = self.recipe["steps"][0]["find"]["bindings"][0]["arguments"]
        args["areaId"] = "{basename:item.urlName}"
        self.assertEqual("", self.errors())
        args["areaId"] = "{base64:item.nothing}"
        self.assertIn("does not resolve in the input schema", self.errors())

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

    def test_lookup_step_needs_a_find_and_keeps_the_modes(self):
        lookup = {"id": "parent", "title": "Find the parent", "forEach": "pages[*]", "key": "{item.menuText}",
                  "source": "skills/x.md", "find": {"bindings": [dict(PAGES_FIND, arguments={"parentId": 0})]}, "bindings": []}
        self.recipe["steps"].insert(0, lookup)
        self.assertEqual("", self.errors())
        del self.recipe["steps"][0]["find"]
        self.assertIn("is a lookup and needs a find", self.errors())

    def test_scan_step_reads_row_and_states_why_it_cannot_write(self):
        scan = {"id": "names", "title": "Names", "forEach": "pages[*]", "key": "{item.menuText}", "source": "skills/x.md",
                "scan": {"binding": dict(PAGES_FIND, arguments={"parentId": 0}), "text": "{item.menuText}", "replacement": "{item.urlName}",
                         "field": "menuText", "identify": ["id"]},
                "bindings": []}
        self.recipe["steps"].insert(0, scan)
        self.assertIn("states why in scan.unwritable", self.errors())
        scan["scan"]["unwritable"] = "Not measured."
        self.assertEqual("", self.errors())
        self.recipe["steps"][1]["bindings"][0]["create"]["arguments"]["pages"][0]["menuText"] = "{replaced:row.menuText}"
        self.assertIn("reads row outside a scan, prune or retire step", self.errors())

    def test_prune_step_is_scoped_and_deletes_through_the_delete_allowlist(self):
        read = dict(PAGES_FIND, arguments={"parentId": "{scope}"})
        read.pop("match"); read.pop("produces")
        prune = {"id": "reset", "title": "Remove what the input does not name", "forEach": "pages[*]", "key": "{item.menuText}",
                 "source": "skills/x.md",
                 "prune": {"scope": {"values": "{step.pages[item.menuText].id}", "member": "parentPageId"}, "binding": read,
                           "keep": {"field": "menuText", "values": "{input.pages[*].menuText}"}, "identify": ["id"], "max": 10},
                 "bindings": [{"id": "delete", "surface": "mcp", "status": "implemented", "source": "skills/x.md",
                               "delete": {"operation": "delete_order", "arguments": {"id": "{row.id}"}}, "readBack": dict(read)}]}
        self.recipe["steps"].append(prune)
        self.assertEqual("", self.errors())
        prune["bindings"][0]["delete"]["operation"] = "delete_pages"
        self.assertIn("is not on recipeDeleteTools", self.errors())
        prune["bindings"][0]["delete"]["operation"] = "delete_order"
        prune["prune"]["binding"]["arguments"] = {"parentId": 0}
        self.assertIn("must pass {scope} in its arguments", self.errors())
        prune["prune"]["binding"]["arguments"] = {"parentId": "{scope}"}
        prune["bindings"][0]["create"] = {"operation": "save_pages", "arguments": {"pages": []}}
        self.assertIn("declares delete only", self.errors())
        del prune["bindings"][0]["create"]
        self.recipe["steps"][0]["find"]["bindings"][0]["arguments"]["areaId"] = "{scope}"
        self.assertIn("reads scope outside a prune step", self.errors())

    def test_retire_step_updates_only_and_keeps_what_earlier_steps_produced(self):
        read = dict(PAGES_FIND, arguments={"parentId": "{step.pages[item.menuText].id}"})
        read.pop("match"); read.pop("produces")
        retire = {"id": "retire", "title": "Set inactive what the input does not name", "forEach": "pages[*]", "key": "{item.menuText}",
                  "source": "skills/x.md",
                  "retire": {"named": "{input.pages[*].menuText}", "requires": ["pages"], "binding": read, "active": {"field": "active", "value": True},
                             "keep": [{"field": "id", "values": "{step.pages[*].id}"}, {"field": "menuText", "values": "{input.pages[*].menuText}"}],
                             "identify": ["id"], "max": 10},
                  "bindings": [{"id": "deactivate", "surface": "mcp", "status": "implemented", "source": "skills/x.md",
                                "update": {"operation": "save_pages", "arguments": {"pages": [{"id": "{row.id}", "active": False}]}},
                                "readBack": dict(read, match={"id": "{row.id}"})}]}
        self.recipe["steps"].append(retire)
        self.assertEqual("", self.errors())
        retire["retire"]["requires"] = ["later"]
        self.assertIn("retire.requires names later, which is not an earlier step", self.errors())
        retire["retire"]["requires"] = ["pages"]
        retire["bindings"][0]["delete"] = {"operation": "delete_order", "arguments": {"id": "{row.id}"}}
        self.assertIn("a retire step's implemented binding declares update only", self.errors())
        del retire["bindings"][0]["delete"]
        retire["retire"]["keep"][0]["values"] = "{step.nothing[*].id}"
        self.assertIn("names step nothing", self.errors())

    def test_file_tokens_resolve_against_the_input_schema(self):
        create = self.recipe["steps"][0]["bindings"][0]["create"]["arguments"]
        create["content"] = "{base64:item.urlName}"
        create["size"] = "{bytes:item.urlName}"
        self.assertEqual("", self.errors())
        create["content"] = "{base64:item.logoFile}"
        self.assertIn("does not resolve in the input schema", self.errors())

    def test_recipe_lives_at_its_id(self):
        self.recipe["id"] = "test.other"
        self.assertIn("must live at recipes/test/test.other.json", self.errors())


    def test_depends_on_names_a_recipe_its_debts_and_no_cycle(self):
        self.recipe["dependsOn"] = [{"recipe": "test.missing", "why": "Needs it."}]
        self.assertIn("dependsOn names test.missing, which is not a recipe", self.errors())
        self.recipe["dependsOn"] = [{"recipe": "test.function", "why": "Itself."}]
        self.assertIn("dependsOn names the recipe itself", self.errors())
        other = copy.deepcopy(RECIPE)
        other["id"], other["dependsOn"] = "test.other", [{"recipe": "test.function", "why": "Needs pages.", "debtsPaid": ["recycle"]}]
        other["functions"] = ["test.function", "test.other"]
        (self.assets / "recipes/test/test.other.json").write_text(json.dumps(other), encoding="utf-8")
        self.recipe.pop("dependsOn")
        errors = self.errors()
        self.assertIn("debtsPaid names recycle, which test.function does not owe", errors)
        self.recipe["dependsOn"] = [{"recipe": "test.other", "why": "A loop."}]
        self.assertIn("dependsOn forms a cycle", self.errors())

    def test_recipe_index_is_generated_and_checked(self):
        refs = self.repo / "skills/dw-demo-ledger/references"
        refs.mkdir(parents=True)
        (refs / "recipes.md").write_text("# Recipes\n", encoding="utf-8")
        self.assertIn("recipe-index.md: missing", self.errors())
        (refs / "recipe-index.md").write_text(render_index({"test.function": self.recipe}), encoding="utf-8", newline="\n")
        self.assertEqual("", self.errors())
        self.recipe["name"] = "Renamed"
        self.recipe["provenOn"] = [{"dwVersion": "1.0.0", "mcpVersion": "0.6.0", "date": "2026-01-01", "evidence": "run"}]
        self.assertIn("recipe-index.md: out of date", self.errors())


if __name__ == "__main__":
    unittest.main()
