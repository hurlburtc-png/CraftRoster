"""Client-reported rarity, clipped titles, wrapped heights and footer layering."""
from pathlib import Path
import unittest
from test_work_orders import fresh

SETUP='''
CraftRosterDB.recipes[800201]={name='Long Crafted Item Example',profession='Tailoring',recipeItemID=70002,itemLink='item:70001'}
local cached=true
local function info(id)
 if id==70001 and cached then return 'Crafted item','|cff0070dd|Hitem:70001|h[Crafted item]|h|r',3,1,1,'Armor','Cloth',1,'',123 end
 if id==70002 then return 'Pattern: Long Crafted Item Example','|cff1eff00|Hitem:70002|h[Pattern: Long Crafted Item Example]|h|r',2,1,1,'Recipe','Tailoring',1,'',456 end
end
GetItemInfo=info;if C_Item then C_Item.GetItemInfo=info end
addon.Directory:Toggle()
local d=addon.Directory;local tab=d.frame.ProfessionsTab
local function find()
 tab.SearchBox:SetText('800201');d:RefreshProfessions()
 for _,frame in ipairs(frames) do if frame.parent==tab.ResultsChild and frame.listEntry and frame.listEntry.id==800201 and frame:IsShown() then return frame end end
end
'''
CASES={
'crafted_quality_colours_primary_name_without_using_pattern_quality': '''
 local row=find();assert(row)
 assert(row.Label:GetText():find('|cff0070dd',1,true) and not row.Label:GetText():find('|cff1eff00',1,true))
 row.scripts.OnMouseUp(row,'LeftButton')
 assert(tab.DetailsName:GetText():find('|cff0070dd',1,true))
 local short=row.RecipeLink:GetText()
 assert(short:find('|Hitem:70002',1,true) and not short:find('Long Crafted Item Example',1,true))
 assert(row.Label:GetWidth()>row:GetWidth()-70 and row.Label:GetHeight()==32)
 apart(row.Label,row.RightLabel);inside(row.Label,row);inside(row.RecipeLink,row)
''',
'unknown_output_quality_is_neutral_and_updates_when_client_data_arrives': '''
 cached=false
 local row=find();assert(row.Label:GetText():find('|cffffffff',1,true))
 assert(addon.ItemDisplay.pending[70001])
 cached=true;dispatch('GET_ITEM_INFO_RECEIVED',70001,true);flushTimers()
 row=find();assert(row.Label:GetText():find('|cff0070dd',1,true))
''',
'no_teaching_item_does_not_duplicate_the_output_link': '''
 CraftRosterDB.recipes[800201].recipeItemID=nil
 local row=find();assert(row and not row.RecipeLink:IsShown())
 assert(row.CraftLink:IsShown(),'crafted-item icon still has a native tooltip target')
''',
'wrapped_source_measurement_does_not_reuse_a_clipped_previous_height': '''
 local row=find();row.scripts.OnMouseUp(row,'LeftButton')
 tab.RecipeSource.Text:SetHeight(5)
 tab.RecipeSource.Text.GetStringHeight=function(label) return label:GetHeight()==0 and 65 or 5 end
 addon.SelectedCraft:RefreshSources()
 assert(tab.RecipeSource.Text:GetHeight()==65)
''',
'footer_has_opaque_backdrop_and_is_above_scroll_descendants': '''
 assert(tab.ActionBar:GetFrameLevel()>tab.SelectedCraftScroll:GetFrameLevel())
 for _,palette in ipairs(addon.Theme.palettes) do
  addon.Theme:SetPalette(palette.key)
  assert(tab.ActionBar.backdropColor[4]==1)
 end
 assert(tab.GuildKnownCheck,'previous release filter remains present')
 apart(tab.ActionBar,tab.SelectedCraftScroll)
''',
}
class VisualTests(unittest.TestCase):pass
for runtime in ('lua51','luajit21'):
 for profile in ('modern','legacy','minimal'):
  for name,code in CASES.items():
   def check(self,runtime=runtime,profile=profile,code=code):
    lua=fresh(runtime,profile);lua.execute((Path(__file__).parent/'layout_mock.lua').read_text())
    lua.execute(SETUP+code)
   setattr(VisualTests,f'test_{runtime}_{profile}_{name}',check)
