"""Controls for the provider model name rule in validate-skills.py. No host access."""
import importlib.util
import unittest
from pathlib import Path

_PATH = Path(__file__).resolve().parents[1] / "validate-skills.py"
_SPEC = importlib.util.spec_from_file_location("validate_skills", _PATH)
validate_skills = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(validate_skills)


class ModelNameRule(unittest.TestCase):
    def test_provider_model_names_are_found(self):
        for text in ("Cheapest (Haiku-class)", "run it on Sonnet", "an Opus session",
                     "claude-opus-4", "claude-3-5", "gpt-5", "o3-mini", "o4", "gemini-2.5"):
            with self.subTest(text=text):
                self.assertTrue(validate_skills.model_name_hits(text), text)

    def test_tiers_and_agent_products_pass(self):
        for text in ("the small tier", "mid tier or above", "top", "Claude Code", "Codex CLI",
                     "codex exec -m <model>", "ChatGPT", "claude-plugin", "Copilot Studio", "o365"):
            with self.subTest(text=text):
                self.assertEqual(validate_skills.model_name_hits(text), [], text)

    def test_line_numbers(self):
        self.assertEqual(validate_skills.model_name_hits("a\nb Haiku\nc"), [(2, "Haiku")])


if __name__ == "__main__":
    unittest.main()
