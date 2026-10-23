"""Regressions reported in-game: clearing, search, versions and crowded panes."""
from pathlib import Path
import unittest
from test_work_orders import fresh

CASES={
'clear_list_removes_active_recipe_without_erasing_craft_state': '''
 inventoryFixture(false,true)
 addon.ShoppingList:SetQuantity(42,4)
 addon.ShoppingList:Open(42)
 local f=addon.ShoppingList.frame
 assert(#addon.ShoppingList.entries>0 and f.Clear:GetText()=='Clear list')
 local state=CraftRosterDB.characters['Tester-Realm'].shoppingList
 state.contributions={[42]={keep=true}}
 f.Clear.scripts.OnClick()
 assert(not state.recipeID and not state.crafter and not state.visible)
 assert(#addon.ShoppingList.entries==0 and not f.Clear:IsEnabled())
 assert(addon.ShoppingList:GetQuantity(42)==4 and state.contributions[42].keep)
 for _,row in ipairs(f.Rows) do assert(not row:IsShown()) end
 dispatch('BAG_UPDATE',0);flushTimers()
 assert(#addon.ShoppingList.entries==0 and f.Message:GetText():find('Choose a recipe',1,true))
 addon.ShoppingList:Open(42)
 assert(#addon.ShoppingList.entries>0 and f.Clear:IsEnabled())
''',
'multiple_search_terms_and_aliases_all_must_match': '''
 CraftRosterDB.recipes[800001]={name='Enchant Bracer - Minor Stamina',profession='Enchanting'}
 CraftRosterDB.recipes[800002]={name='Enchant Bracer - Agility',profession='Enchanting'}
 CraftRosterDB.recipes[800003]={name='Enchant Boots - Minor Stamina',profession='Enchanting'}
 addon.Directory:Toggle()
 local d=addon.Directory;local tab=d.frame.ProfessionsTab
 local function has(id)
  for _,entry in ipairs(d.professionCache.entries) do if entry.id==id then return true end end
 end
 for _,query in ipairs({' WRIST  stamina ','stamina wrist','minor-stamina wrist','Formula: wrist stamina'}) do
  tab.SearchBox:SetText(query);d:RefreshProfessions()
  assert(has(800001) and not has(800002) and not has(800003),query)
 end
 tab.Results:SetVerticalScroll(99999);tab.SearchBox:SetText('800002');d:RefreshProfessions()
 assert(has(800002) and not has(800001) and tab.Results:GetVerticalScroll()==0)
 tab.SearchBox:SetText('not-in-any-craft');tab.SearchBox.scripts.OnTextChanged()
 tab.SearchBox:SetText('800001');tab.SearchBox.scripts.OnTextChanged();flushTimers()
 assert(has(800001) and not has(800002))
''',
'same_name_versions_have_one_row_and_keep_ownership_materials_sources_separate': '''
 CraftRosterDB.recipes[800011]={name='Twin Example Boots',profession='Tailoring',recipeItemID=70001,materials={{itemID=7,name='Herb',count=1}}}
 CraftRosterDB.recipes[800012]={name='Twin Example Boots',profession='Tailoring',recipeItemID=70002,materials={{itemID=7,name='Herb',count=5}}}
 CraftRosterDB.characters['Tester-Realm'].recipes[800011]={}
 CraftRosterDB.characters['Other-Realm']={recipes={[800012]={}}}
 addon.Directory:Toggle()
 local d=addon.Directory;local tab=d.frame.ProfessionsTab
 tab.SearchBox:SetText('Twin Example');d:RefreshProfessions()
 assert(#d.professionCache.entries==1)
 local entry=d.professionCache.entries[1]
 assert(#entry.recipe.versions==2 and entry.recipe.id==800011)
 local row
 for _,frame in ipairs(frames) do if frame.parent==tab.ResultsChild and frame.listEntry and frame:IsShown() then row=frame end end
 row.scripts.OnMouseUp(row,'LeftButton')
 assert(d.selectedRecipe.id==800011 and addon.RecipeSources:Get(d.selectedRecipe.id).itemID==70001)
 addon.SelectedCraft.versionButton.scripts.OnClick()
 assert(d.selectedRecipe.id==800012 and d.selectedRecipe.crafters[1]=='Other-Realm' and #d.selectedRecipe.crafters==1)
 assert(addon.RecipeSources:Get(d.selectedRecipe.id).itemID==70002 and addon.RecipeSources:GetMaterials(d.selectedRecipe.id)[1].count==5)
 assert(#d.professionCache.entries==1 and CraftRosterDB.characters['Tester-Realm'].recipes[800012]==nil)
''',
'legacy_string_keys_collapse_only_the_same_spell_and_preserve_metadata': '''
 CraftRosterDB.recipes[800021]={name='Same spell',profession='Alchemy'}
 CraftRosterDB.recipes['800021']={description='Keep this metadata'}
 CraftRosterDB.characters['Tester-Realm'].recipes[800021]={}
 CraftRosterDB.characters['Tester-Realm'].recipes['800021']={extra=true}
 addon.Directory:Toggle()
 assert(CraftRosterDB.recipes['800021']==nil and CraftRosterDB.recipes[800021].description=='Keep this metadata')
 assert(CraftRosterDB.characters['Tester-Realm'].recipes['800021']==nil and CraftRosterDB.characters['Tester-Realm'].recipes[800021].extra)
 local d=addon.Directory;d.frame.ProfessionsTab.SearchBox:SetText('800021');d:RefreshProfessions()
 assert(#d.professionCache.entries==1 and #d.professionCache.entries[1].recipe.crafters==1)
''',
'enchanting_vendor_has_named_classic_location_not_just_an_id_or_count': '''
 CraftRosterDB.recipes[20026]={name='Enchant Chest - Major Health',profession='Enchanting',recipeItemID=16221,sourceText='Vendor: 11189'}
 local text=addon.RecipeSources:Summary(20026)
 assert(text:find('Vendor: Qia',1,true) and text:find('Winterspring',1,true) and text:find('61.2, 37.21',1,true))
 assert(text:find('unconfirmed in Forever',1,true) and not text:find('11189',1,true))
 local full=addon.RecipeSources:Format(20026)
 assert(not full:find('Vendor: 11189',1,true))
''',
'normal_recipe_uses_width_and_fits_without_scrolling_at_default_size': '''
 inventoryFixture(false,true)
 CraftRosterDB.recipes[1255143]={name='Moonglow Boots',profession='Leatherworking',materials={
 {itemID=7,name='Light Leather',count=12},{itemID=8,name='Cured Light Hide',count=2},{itemID=9,name='Small Lustrous Pearl',count=1}}}
 CraftRosterDB.characters['Tester-Realm'].recipes[1255143]={}
 CraftRosterDB.characters['Other-Realm']={recipes={[1255143]={}}}
 CraftRosterDB.settings.onlineOnly=false
 addon.Directory:Toggle()
 local d=addon.Directory;d.frame.ProfessionsTab.SearchBox:SetText('Moonglow Boots');d:RefreshProfessions()
 local tab=d.frame.ProfessionsTab
 d.selectedRecipe=d.professionCache.entries[1].recipe;d:RefreshDetails();d:RefreshCrafters()
 assert(tab.SelectedCraftScroll:GetWidth()>600 and not addon.SelectedCraft.stacked)
 assert(tab.SelectedCraftContent:GetHeight()<=tab.SelectedCraftScroll:GetHeight()+1,'ordinary selected recipe should fit')
 apart(tab.Results,tab.SelectedCraftScroll);apart(tab.SelectedCraftScroll,tab.ActionBar)
 for _,row in ipairs(addon.SelectedCraft.rows) do if row:IsShown() then inside(row,tab.Details) end end
 addon.SelectedCraft.sourceToggle.scripts.OnClick()
 assert(tab.RecipeSource.Text:GetText():find('ATT Forever',1,true),'full source details still accessible')
''',
'recycled_rows_and_action_buttons_stay_inside_their_panels': '''
 inventoryFixture(false,true);addon.Directory:Toggle()
 local d=addon.Directory;local tab=d.frame.ProfessionsTab
 for _,size in ipairs({{620,420},{1000,680},{1200,800},{760,500}}) do
  d.frame:SetSize(size[1],size[2]);d.frame.scripts.OnSizeChanged(d.frame)
  for _,query in ipairs({'potion','no-such-craft','Alchemy',''}) do
   tab.SearchBox:SetText(query);d:RefreshProfessions()
   for _,frame in ipairs(frames) do
    if frame.parent==tab.ResultsChild and frame:IsShown() and frame.Label then
     inside(frame.Label,frame);inside(frame.RightLabel,frame)
     apart(frame.Label,frame.RightLabel)
     if frame.RecipeLink and frame.RecipeLink:IsShown() then inside(frame.RecipeLink,frame) end
    end
   end
   apart(tab.SelectedCraftScroll,tab.ActionBar)
   apart(tab.Dropdown,tab.CraftRosterRefreshButton)
  end
 end
''',
}
class UsabilityTests(unittest.TestCase):pass
for runtime in ('lua51','luajit21'):
 for profile in ('modern','legacy','minimal'):
  for name,code in CASES.items():
   def check(self,runtime=runtime,profile=profile,code=code):
    lua=fresh(runtime,profile)
    lua.execute((Path(__file__).parent/'layout_mock.lua').read_text())
    lua.execute(code)
   setattr(UsabilityTests,f'test_{runtime}_{profile}_{name}',check)
