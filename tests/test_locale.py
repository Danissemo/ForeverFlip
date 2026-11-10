import json
import re
import unittest
from test_domain import runtime, ROOT
from test_controller import controller_runtime


def translated_pairs():
    for name in ['UI','ItemDisplay','Core','NativeLayout','NativeShopping','Progress','Radar','Stats']:
        source=(ROOT/'ForeverFlip'/(name+'.lua')).read_text(encoding='utf-8-sig')
        for match in re.finditer(r'\bL\(\s*("(?:[^"\\]|\\.)*")\s*,\s*("(?:[^"\\]|\\.)*")\s*\)',source):
            yield json.loads(match[1]), json.loads(match[2])


class LocaleTests(unittest.TestCase):
    def locale_runtime(self):
        l=runtime();p=ROOT/'ForeverFlip/Locale.lua'
        self.assertTrue(p.exists(),'Missing Ukrainian locale')
        l.execute(p.read_text(encoding='utf-8-sig'))
        return l
    def test_every_ui_string_has_ukrainian_translation_and_format_arguments(self):
        l=self.locale_runtime()
        catalog=l.globals().ForeverFlip.Locale.uk
        tokens=lambda s:re.findall(r'%(?:\d+)?(?:\.\d+)?[cdfgiosuxXeEfgG%]',s)
        for source,en in translated_pairs():
            ua=catalog[en]
            self.assertTrue(ua, 'Missing: '+en)
            self.assertEqual(tokens(en),tokens(ua), 'Format changed: '+en)
    def test_automatic_ukrainian_and_existing_languages(self):
        self.locale_runtime().execute('''local L=ForeverFlip.Locale
        GetLocale=function()return 'ukUA'end;assert(L.text('Overview','Overview')=='Огляд')
        GetLocale=function()return 'enUS'end;assert(L.text('Overview','Overview')=='Overview')''')
    def test_translation_returns_one_string_for_variadic_ui_calls(self):
        self.locale_runtime().execute('''local L=ForeverFlip.Locale
        for _,locale in ipairs({'enUS','ukUA'})do
          GetLocale=function()return locale end
          assert(select('#',L.text('Overview','Overview'))==1)
        end''')
    def test_override_preserves_financial_settings_and_reload_notice(self):
        l=controller_runtime()
        l.execute((ROOT/'tests/wow_mock.lua').read_text())
        for name in ['UI','Core']:l.execute((ROOT/'ForeverFlip'/(name+'.lua')).read_text(encoding='utf-8-sig'))
        l.execute('''ForeverFlip.boot('ForeverFlip');AuctionHouseFrame:Hide()
        SlashCmdList.FOREVERFLIP('lang uk')
        assert(ForeverFlip.db.ui.language=='ukUA' and ForeverFlip.db.settings.fee==.05)
        ForeverFlip.attach();assert(ForeverFlip.ui.nav.overview:GetText()=='Старт')
        assert(ForeverFlip.ui.actions.search:GetText()=='Пошук')''')
        l.execute('''for _,section in ipairs({'overview','deals','workbench','trade','watch','portfolio','history','tools','settings'})do
            ForeverFlip.ui:show(section);ForeverFlip.ui:refresh()
        end''')
    def test_font_contains_every_translated_glyph(self):
        from fontTools.ttLib import TTFont
        path=ROOT/'ForeverFlip/Fonts/NotoSans-Regular.ttf'
        self.assertTrue(path.exists(),'Missing bundled Cyrillic font')
        font=TTFont(path);cmap=font.getBestCmap()
        l=self.locale_runtime();strings=[v for _,v in l.globals().ForeverFlip.Locale.uk.items()]
        missing={c for s in strings for c in s if not c.isspace() and ord(c) not in cmap}
        self.assertEqual(missing,set())
        self.assertTrue(set('ІіЇїЄєҐґ').issubset({chr(x)for x in cmap}))
    def test_overview_layout_measures_the_translated_content_after_refresh(self):
        from test_ui import ui_runtime
        ui_runtime().execute('''u:show('overview','day');local p,a,r,x,y=u.actions.toDeals:GetPoint()
        assert(u.actions.toDeals:GetParent()==u.sections.overview.split.pages.day and y<=-200 and y>=-320)
        assert(not u.overviewText:GetText():find('1%.'))''')
    def test_all_forwarded_errors_have_ukrainian_messages_including_dynamic_prefixes(self):
        l=self.locale_runtime()
        l.execute("GetLocale=function()return 'ukUA'end")
        for filename in ['Adapters','Store','Professions','Ledger']:
            source=(ROOT/'ForeverFlip'/(filename+'.lua')).read_text(encoding='utf-8-sig')
            for raw in re.findall(r'return (?:nil|false), ("(?:[^"\\]|\\.)*")',source):
                en=json.loads(raw)
                self.assertNotEqual(l.globals().ForeverFlip.Locale.message(en),en,en)
        l.execute('''local L=ForeverFlip.Locale
        assert(L.message('Invalid legacy row 15')=='Некоректний старий запис 15')
        assert(L.message('search_error: timeout')=='Помилка пошуку: timeout')''')

if __name__=='__main__':unittest.main()
