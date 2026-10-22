"""Recipe preview and live inventory without opening the shopping window."""
import unittest
from test_work_orders import fresh

SETUP = '''
inventoryFixture(false,true)
CraftRosterDB.recipes[42].profession='Alchemy'
addon.Directory:Toggle()
addon.Directory.selectedRecipe={id=42,name='Potion',profession='Alchemy',crafters={}}
addon.Directory:RefreshDetails()
'''

CASES = {
'craft_button_uses_selected_quantity_and_existing_guards': '''
    CraftRosterDB.characters['Tester-Realm'].recipes[42]={}
    addon.SelectedCraft:Refresh()
    addon.ShoppingList:SetQuantity(42,3); flushTimers()
    GetNumTradeSkills=function() return 1 end
    GetTradeSkillRecipeLink=function() return 'enchant:42' end
    local calls=0
    DoTradeSkill=function(index,count) assert(index==1 and count==3); calls=calls+1 end
    local button=addon.SelectedCraft.craftButton
    assert(button:GetText()=='Craft')
    assert(addon.Directory.frame.ProfessionsTab.CraftRosterQuantityUp:GetWidth()>=32)
    button.scripts.OnClick(); assert(calls==1)
    button.scripts.OnClick(); assert(calls==1,'duplicate clicks are throttled')
    clock=clock+1
    InCombatLockdown=function() return true end
    button.scripts.OnClick(); assert(calls==1)
    assert(#addon.WorkOrders:GetOrders()==0,'direct crafting must not create a fake work order')
''',
'guild_craft_button_prepares_selected_crafter_request': '''
    addon.Directory.selectedCrafter='Crafter-Realm'
    addon.SelectedCraft:RefreshMaterials()
    local chosen
    addon.Requests.WhisperPlayer=function(_,id,crafter) chosen={id,crafter} end
    local button=addon.SelectedCraft.craftButton
    assert(button:GetText()=='Request craft')
    button.scripts.OnClick()
    assert(chosen[1]==42 and chosen[2]=='Crafter-Realm')
    chosen=nil; addon.Directory.selectedCrafter=nil
    button.scripts.OnClick(); assert(not chosen)
''',
'moonglow_boots_acquisition_uses_forever_vendor_not_old_quest': '''
    CraftRosterDB.recipes[1255143]={name='Moonglow Boots',profession='Leatherworking'}
    addon.Directory.selectedRecipe={id=1255143,name='Moonglow Boots',profession='Leatherworking',crafters={}}
    addon.SelectedCraft:Refresh()
    local text=addon.Directory.frame.ProfessionsTab.RecipeSource.Text:GetText()
    assert(text:find('Granny Finespindle',1,true) and text:find('Ironforge (39.3, 33.7)',1,true))
    assert(text:find('Alliance',1,true) and text:find('ATT Forever reference',1,true))
    assert(not text:find('Source unknown',1,true) and not text:find('Quest:',1,true))
    local old=addon.RecipeSources:Format(8322)
    assert(not old:find('Granny Finespindle',1,true),'different recipes must not inherit acquisition by name')
''',
'closed_shopping_list_still_tracks_bag_changes_and_quantity': '''
    assert(not addon.ShoppingList.frame)
    assert(addon.SelectedCraft.entries[1].owned==24 and addon.SelectedCraft.entries[1].required==3)
    inventory[1].count=1; inventory[2].count=0
    dispatch('BAG_UPDATE',0); dispatch('BAG_UPDATE_DELAYED'); flushTimers()
    assert(addon.SelectedCraft.entries[1].owned==1)
    addon.ShoppingList:SetQuantity(42,4); flushTimers()
    assert(addon.SelectedCraft.entries[1].required==12 and not addon.ShoppingList.frame)
    addon.ShoppingList:Open(42); addon.ShoppingList:Close()
    inventory[1].count=6; dispatch('BAG_UPDATE',0); flushTimers()
    assert(addon.SelectedCraft.entries[1].owned==6 and not addon.ShoppingList.frame:IsShown())
''',
'bag_burst_is_coalesced_and_hidden_directory_does_no_inventory_work': '''
    if not C_Timer then return end
    flushTimers()
    local calls=0
    GetItemCount=function() calls=calls+1; return 5 end
    for i=1,20 do dispatch('BAG_UPDATE',0) end
    assert(calls==0); flushTimers(); assert(calls==1)
    addon.Directory.frame:Hide()
    for i=1,20 do dispatch('BAG_UPDATE',0) end
    flushTimers(); assert(calls==1)
''',
'location_below_recipe_and_materials_remain_independent': '''
    CraftRosterDB.recipes[42].recipeItemID=123
    CraftRosterDB.recipes[42].sourceText='Vendor: Example seller\\nLocation: Example town'
    addon.SelectedCraft:Refresh()
    assert(addon.Directory.frame.ProfessionsTab.RecipeSource.Text:GetText():find('Example town',1,true))
    assert(addon.SelectedCraft.entries[1].required==3)
    local row=addon.SelectedCraft.rows[1]
    assert(row.Icon and row.Label:GetText():find('24 / 3',1,true))
    local link
    GameTooltip.SetHyperlink=function(_,value) link=value end
    row.scripts.OnEnter(row); assert(link=='item:7')
    AuctionFrame=CreateFrame(); AuctionFrame:Show(); BrowseName=CreateFrame()
    row.scripts.OnClick(row); assert(BrowseName:GetText()=='Herb')
''',
'main_item_and_search_results_keep_native_hover': '''
    CraftRosterDB.recipes[42].itemLink='item:99'
    local link
    GameTooltip.SetHyperlink=function(_,value) link=value end
    local header=addon.Directory.frame.ProfessionsTab.CraftItemHover
    header.scripts.OnEnter(header); assert(link:find('item:99',1,true))
    CraftRosterDB.characters['Tester-Realm'].recipes[42]={}
    CraftRosterDB.favorites={[42]=true}; CraftRosterDB.settings.favoritesOnly=true
    addon.Directory:InvalidateIndex(); flushTimers(); addon.Directory:RefreshProfessions()
    for _,row in ipairs(frames) do
      if row.parent==addon.Directory.frame.ProfessionsTab.ResultsChild and row.listEntry and row.listEntry.id==42 then
        row.scripts.OnEnter(row); assert(link:find('item:99',1,true)); return
      end
    end
    error('selected search result missing')
''',
}

class SelectedCraftTests(unittest.TestCase): pass
for runtime in ('lua51','luajit21'):
    for profile in ('modern','legacy','minimal'):
        for name, code in CASES.items():
            def check(self,runtime=runtime,profile=profile,code=code):
                lua=fresh(runtime,profile); lua.execute(SETUP); lua.execute(code)
            setattr(SelectedCraftTests,f'test_{runtime}_{profile}_{name}',check)
