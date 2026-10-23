"""Regression coverage for native icons, delayed item data and contextual links."""
import unittest
from pathlib import Path
from test_work_orders import fresh

CASES = {
'legacy_item_info_icon_and_cache_event_refresh_both_views': '''
 inventoryFixture(false,true)
 if C_Item then C_Item.GetItemInfo=nil; C_Item.GetItemIconByID=nil; C_Item.GetItemIcon=nil end
 GetItemIcon=nil
 local cached=false
 GetItemInfo=function(id)
  if cached and id==7 then return 'Peacebloom','|Hitem:7|h[Peacebloom]|h',1,1,1,'Trade Goods','Herb',20,'','Interface\\\\Icons\\\\INV_Misc_Flower_02' end
 end
 CraftRosterDB.recipes[42].materials[1].name='Item 7'
 addon.Directory:Toggle()
 addon.Directory.selectedRecipe={id=42,name='Potion',profession='Alchemy',crafters={}}
 addon.Directory:RefreshDetails(); addon.ShoppingList:Open(42)
 assert(addon.ShoppingList.entries[1].name=='Material loading…')
 cached=true; dispatch('GET_ITEM_INFO_RECEIVED',7,true); flushTimers()
 local entry=addon.ShoppingList.entries[1]
 assert(entry.name=='Peacebloom' and entry.icon=='Interface\\\\Icons\\\\INV_Misc_Flower_02')
 assert(addon.SelectedCraft.entries[1].name=='Peacebloom')
 assert(addon.RecipeSources:GetMaterials(42)[1].name=='Peacebloom')
 assert(CraftRosterDB.recipes[42].materials[1].name=='Item 7','Do not overwrite saved scan data')
''',
'item_load_failure_retries': '''
 inventoryFixture(false,true)
 local items=addon.ItemDisplay
 items.pending={}
 C_Item=C_Item or {}
 local requests=0
 C_Item.GetItemInfo=function() return nil end
 C_Item.GetItemIconByID=function() return nil end
 C_Item.RequestLoadItemDataByID=function(id) requests=requests+1 end
 items:Resolve(777,'Item 777')
 assert(items.pending[777] and requests==1)
 dispatch('GET_ITEM_INFO_RECEIVED',777,false)
 assert(items.pending[777]==nil)
 items:Resolve(777,'Item 777')
 assert(items.pending[777] and requests==2)
 items.pending[777]=nil
 C_Item.RequestLoadItemDataByID=nil
 items:Resolve(778,'Item 778')
 assert(items.pending[778]==nil)
''',
'async_item_request_explicit_rejection_stays_retryable': '''
 inventoryFixture(false,true)
 local items=addon.ItemDisplay
 items.pending={}
 C_Item=C_Item or {}
 local requests=0
 C_Item.GetItemInfo=function() return nil end
 C_Item.GetItemIconByID=function() return nil end
 C_Item.RequestLoadItemDataByID=function(id) requests=requests+1; return false end
 items:Resolve(779,'Item 779')
 assert(items.pending[779]==nil and requests==1)
 items:Resolve(779,'Item 779')
 assert(items.pending[779]==nil and requests==2)
''',
'failed_whisper_composer_insert_does_not_fall_through_to_ah_or_chat': '''
 inventoryFixture(false,true); addon.ShoppingList:Open(42)
 local composer=addon.WhisperComposer; assert(composer:Open(42))
 composer.InsertMaterialLink=function() return false end
 AuctionFrame=CreateFrame(); AuctionFrame:Show(); BrowseName=CreateFrame(); BrowseName:SetText('unchanged')
 local inserted=false
 ChatEdit_GetActiveWindow=function() return CreateFrame() end
 ChatEdit_InsertLink=function() inserted=true; return true end
 local row=addon.ShoppingList.frame.Rows[1]; row.scripts.OnClick(row,'LeftButton')
 assert(not inserted and BrowseName:GetText()=='unchanged')
''',
'active_native_whisper_takes_priority_over_auction_search': '''
 inventoryFixture(false,true); addon.ShoppingList:Open(42)
 AuctionFrame=CreateFrame(); BrowseName=CreateFrame(); BrowseName:SetText('unchanged')
 local inserted
 ChatEdit_GetActiveWindow=function() return CreateFrame() end
 ChatEdit_InsertLink=function(link) inserted=link; return true end
 local row=addon.ShoppingList.frame.Rows[1]; row.scripts.OnClick(row,'LeftButton')
 assert(inserted:find('|Hitem:7',1,true) and BrowseName:GetText()=='unchanged')
''',
'open_composer_accepts_material_link_without_sending': '''
 inventoryFixture(false,true); addon.ShoppingList:Open(42)
 ChatEdit_GetActiveWindow=nil
 local composer=addon.WhisperComposer; assert(composer:Open(42))
 composer.frame.Edit.Insert=nil
 local before=#sent
 local row=addon.ShoppingList.frame.Rows[1]; row.scripts.OnClick(row,'LeftButton')
 assert(composer.frame.Edit:GetText():find('|Hitem:7',1,true) and #sent==before)
''',
'shift_click_opens_native_chat_and_plain_click_keeps_ah_search': '''
 inventoryFixture(false,true); addon.ShoppingList:Open(42)
 ChatEdit_GetActiveWindow=nil; ChatEdit_InsertLink=nil
 local opened; ChatFrame_OpenChat=function(link) opened=link end
 IsShiftKeyDown=function() return true end
 local row=addon.ShoppingList.frame.Rows[1]; row.scripts.OnClick(row,'LeftButton')
 assert(opened:find('|Hitem:7',1,true))
 IsShiftKeyDown=function() return false end
 AuctionFrame=CreateFrame(); BrowseName=CreateFrame()
 row.scripts.OnClick(row,'LeftButton'); assert(BrowseName:GetText()=='Herb')
''',
'unified_scroll_and_compact_material_geometry': '''
 inventoryFixture(false,true)
 addon.Directory:Toggle()
 addon.Directory.selectedRecipe={id=42,name='Potion',profession='Alchemy',crafters={}}
 addon.Directory:RefreshDetails(); addon.Directory:RefreshCrafters()
 local tab=addon.Directory.frame.ProfessionsTab
 assert(tab.CrafterList.outerScroll==tab.SelectedCraftScroll)
 assert(not tab.CrafterList.template and not tab.RecipeSource.template)
 assert(tab.RecipeSource:GetParent()==tab.Details)
 assert(tab.SelectedCraftContent:GetHeight()==tab.CrafterList.contentOffset+tab.CrafterListChild:GetHeight())
 local row=addon.SelectedCraft.rows[1]
 assert(row.Icon:GetWidth()==32 and row:GetHeight()<=50)
 local old=tab.SelectedCraftScroll:GetVerticalScroll()
 row.scripts.OnMouseWheel(row,-1)
 assert(tab.SelectedCraftScroll:GetVerticalScroll()>=old)
''',
}
class ItemDisplayTests(unittest.TestCase): pass
for runtime in ('lua51','luajit21'):
 for profile in ('modern','legacy','minimal'):
  for name,code in CASES.items():
   def check(self,runtime=runtime,profile=profile,code=code,name=name):
    lua=fresh(runtime,profile)
    if name=='unified_scroll_and_compact_material_geometry':
     lua.execute((Path(__file__).parent/'layout_mock.lua').read_text())
    lua.execute(code)
   setattr(ItemDisplayTests,f'test_{runtime}_{profile}_{name}',check)
