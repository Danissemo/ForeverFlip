import ast
from pathlib import Path
import tempfile
import unittest

from test_controller import controller_runtime
from test_domain import ROOT


class AuditEnvironmentTests(unittest.TestCase):
    def test_register_skips_copying_skill_onto_itself(self):
        source = ROOT.parents[1] / 'setup/register_codex.py'
        if not source.exists():
            source = ROOT / 'environment/setup/register_codex.py'
        tree = ast.parse(source.read_text(encoding='utf-8'))
        function = next((n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name == 'copy_skill'), None)
        self.assertIsNotNone(function, 'Registrar must have an idempotent copy_skill boundary')
        import shutil
        namespace = {'shutil': shutil}
        exec(compile(ast.Module(body=[function], type_ignores=[]), str(source), 'exec'), namespace)
        with tempfile.TemporaryDirectory() as folder:
            file = Path(folder) / 'SKILL.md'
            file.write_text('original', encoding='utf-8')
            self.assertFalse(namespace['copy_skill'](file, file))
            self.assertEqual(file.read_text(), 'original')
            target = Path(folder) / 'copy.md'
            self.assertTrue(namespace['copy_skill'](file, target))
            self.assertEqual(target.read_text(), 'original')

    def test_widget_hooks_chain_and_hidden_clicks_can_be_rejected(self):
        l = controller_runtime()
        l.execute((ROOT/'tests/wow_mock.lua').read_text())
        l.execute('''local p=CreateFrame('Frame');local b=CreateFrame('Button',nil,p)
        local n=0;b:SetScript('OnShow',function()n=n+1 end)
        b:HookScript('OnShow',function()n=n+10 end);p:Show();b:Show();assert(n==11)
        assert(b:IsVisible());p:Hide();assert(not b:IsVisible())
        STRICT_MOCK_CLICKS=true;b:SetScript('OnClick',function()n=n+100 end)
        b:Click();assert(n==11);p:Show();b:Click();assert(n==111)''')


if __name__ == '__main__':
    unittest.main()
