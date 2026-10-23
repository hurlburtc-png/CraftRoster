"""Guild-known search uses saved ownership, independently of online status."""
from pathlib import Path
import unittest
from test_work_orders import fresh

SETUP='''
CraftRosterDB.recipes[800101]={name='Filter Test Known',profession='Alchemy'}
CraftRosterDB.recipes[800102]={name='Filter Test Offline',profession='Alchemy'}
CraftRosterDB.recipes[800103]={name='Filter Test Unknown',profession='Alchemy'}
CraftRosterDB.characters['Tester-Realm'].recipes[800101]={}
CraftRosterDB.characters['Offline-Realm']={recipes={[800102]={}}}
addon.Directory:Toggle()
local d=addon.Directory;local tab=d.frame.ProfessionsTab
local function search()
 tab.SearchBox:SetText('Filter Test');d:RefreshProfessions()
 local found={}
 for _,entry in ipairs(d.professionCache.entries) do if entry.recipe then found[entry.id]=entry end end
 return found
end
local function toggle(value)
 tab.GuildKnownCheck:SetChecked(value);tab.GuildKnownCheck.scripts.OnClick(tab.GuildKnownCheck)
end
'''
CASES={
'offline_and_own_recipes_are_included_but_catalogue_is_hidden': '''
 local found=search();assert(found[800101] and found[800102] and found[800103])
 toggle(true);found=search()
 assert(found[800101] and found[800102] and not found[800103])
 assert(CraftRosterDB.settings.guildKnownOnly)
 CraftRosterDB.settings.onlineOnly=true;d:RefreshProfessions();found=search()
 assert(found[800102],'offline recipe must stay searchable')
 toggle(false);found=search();assert(found[800103])
''',
'favorites_and_profession_filters_compose_with_guild_known': '''
 toggle(true);CraftRosterDB.favorites={[800102]=true,[800103]=true};CraftRosterDB.settings.favoritesOnly=true
 local found=search();assert(found[800102] and not found[800101] and not found[800103])
 d.selectedProfession='Enchanting';found=search();assert(not next(found))
''',
'removing_ownership_and_invalidating_index_updates_results': '''
 toggle(true);local found=search();assert(found[800102])
 CraftRosterDB.characters['Offline-Realm'].recipes={};d:InvalidateIndex();flushTimers()
 found=search();assert(not found[800102])
 CraftRosterDB.characters['Offline-Realm'].recipes[800103]={};d:InvalidateIndex();flushTimers()
 found=search();assert(found[800103])
''',
'checkbox_is_below_search_and_does_not_overlap_filters_at_any_size': '''
 for _,size in ipairs({{620,420},{1000,680},{1200,800}}) do
  d.frame:SetSize(size[1],size[2]);d.frame.scripts.OnSizeChanged(d.frame)
  inside(tab.GuildKnownCheck,tab)
  apart(tab.GuildKnownCheck,tab.SearchBox);apart(tab.GuildKnownCheck,tab.Dropdown)
  apart(tab.GuildKnownCheck,tab.Results);apart(tab.GuildKnownCheck,tab.FavoritesCheck)
  apart(tab.GuildKnownCheck,tab.CraftRosterRefreshButton)
 end
 toggle(true);d.frame:Hide();d:Toggle()
 assert(CraftRosterDB.settings.guildKnownOnly and tab.GuildKnownCheck:GetChecked())
''',
}
class GuildKnownTests(unittest.TestCase):pass
for runtime in ('lua51','luajit21'):
 for profile in ('modern','legacy','minimal'):
  for name,code in CASES.items():
   def check(self,runtime=runtime,profile=profile,code=code):
    lua=fresh(runtime,profile)
    lua.execute((Path(__file__).parent/'layout_mock.lua').read_text())
    lua.execute(SETUP+code)
   setattr(GuildKnownTests,f'test_{runtime}_{profile}_{name}',check)
