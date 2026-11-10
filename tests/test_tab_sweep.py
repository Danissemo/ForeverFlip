import unittest
from test_ui import ui_runtime

SWEEP = r'''
db.ledger={{uid='b',kind='buy',owner='owner',scope='scope',key='1:0:0:0',qty=5,total=500,at=now-4*86400}}
api.bagItems=function()return {{id=1,key={itemID=1},qty=5,bag=0,slot=1}}end
api.deposit=function()return 10 end;api.post=function()return true end
api.queryOwned=function()end;api.owned=function()return {}end
api.mail=function()return {}end
c.candidates={{key={itemID=1},rows=rows,at=now,scope='scope',family=false,kind='commodity'}}
local names={};for k,v in pairs(u.actions)do names[v]=k end
local skip={languageen=true,languageuk=true,languageauto=true,confirm=true,cardConfirm=true,bid=true}
errors={};clicked=0
for _,id in ipairs({'overview','deals','trade','portfolio','workbench','watch','history','tools','settings'})do
  u:show(id);u:refresh()
  local split=u.sections[id].split
  if split then
    for pid,page in pairs(split.pages)do
      u:show(id,pid);u:refresh()
      for w,name in pairs(names)do
        local p=rawget(w,'parent');local onPage=false
        for _=1,6 do if p==page then onPage=true break end;p=p and rawget(p,'parent')end
        if onPage and not skip[name] and w.enabled then
          clicked=clicked+1
          local ok,err=pcall(function()w:Click();u:refresh()end)
          if not ok then errors[#errors+1]=id..'/'..pid..'/'..name..': '..tostring(err)end
          now=now+3
        end
      end
    end
  end
end
'''


class TabSweepTests(unittest.TestCase):
    def test_every_button_on_every_page_runs_without_errors_or_spending(self):
        l = ui_runtime()
        l.execute(SWEEP)
        g = l.globals()
        errors = [g.errors[i] for i in range(1, len(g.errors) + 1)]
        self.assertEqual(errors, [])
        self.assertGreater(g.clicked, 40)
        l.execute("assert(spent==0)")


if __name__ == '__main__':
    unittest.main()
