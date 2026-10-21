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
'native_pattern_text_is_copied_and_materials_remain_independent': '''
    addon.SelectedCraft.cachedLink=nil
    CraftRosterDB.recipes[42].recipeItemID=123
    local field=CreateFrame(); field:SetText('Pattern: Potion')
    local use=CreateFrame(); use:SetText('Use: Teaches you how to make Potion.')
    CraftRosterRecipePreviewScannerTextLeft1=field
    CraftRosterRecipePreviewScannerTextLeft2=use
    local scanner=addon.SelectedCraft.scanner
    scanner.SetHyperlink=function() end
    scanner.GetNumLines=function() return 2 end
    addon.SelectedCraft:Refresh()
    assert(addon.SelectedCraft.recipeBody:GetText():find('Use: Teaches you',1,true))
    assert(addon.SelectedCraft.entries[1].required==3)
    local row=addon.SelectedCraft.rows[1]
    assert(row.Label:GetText():find('|T',1,true) and row.Label:GetText():find('24 / 3',1,true))
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
