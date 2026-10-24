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
'hybrid_client_uses_legacy_icon_when_modern_cache_is_empty': '''
 inventoryFixture(false,true)
 local items=addon.ItemDisplay
 items.pending={}; items.loaded={}
 C_Item=C_Item or {}
 local requested=0
 C_Item.GetItemInfo=function() return 'Hybrid Herb','|Hitem:777|h[Hybrid Herb]|h',1 end
 C_Item.GetItemIconByID=function() return nil end
 GetItemInfo=function() return nil end
 GetItemIcon=function(id) if id==777 then return 'LegacyIcon777' end end
 C_Item.RequestLoadItemDataByID=function() requested=requested+1; return true end
 local name,link,icon=items:Resolve(777,'Hybrid Herb')
 assert(name=='Hybrid Herb' and link:find('item:777',1,true))
 assert(icon=='LegacyIcon777' and requested==0)
''',
'hybrid_client_uses_legacy_item_info_after_modern_failure': '''
 inventoryFixture(false,true)
 local items=addon.ItemDisplay
 items.pending={}; items.loaded={}
 C_Item=C_Item or {}
 C_Item.GetItemInfo=function() error('modern cache unavailable') end
 C_Item.GetItemIconByID=function() return nil end
 GetItemInfo=function(id)
  if id==777 then return 'Fallback Herb','|Hitem:777|h[Fallback Herb]|h',2,1,1,'Trade Goods','Herb',20,'','LegacyTexture' end
 end
 local name,link,icon,quality=items:Resolve(777,'Item 777')
 assert(name=='Fallback Herb' and icon=='LegacyTexture' and quality==2)
 assert(link:find('Fallback Herb',1,true))
''',
'known_item_without_icon_requests_one_async_refresh': '''
 inventoryFixture(false,true)
 local items=addon.ItemDisplay
 items.pending={}; items.loaded={}
 C_Item=C_Item or {}
 local ready=false
 local requests=0
 C_Item.GetItemInfo=function(id) return 'Known Herb','|Hitem:777|h[Known Herb]|h',1 end
 C_Item.GetItemIconByID=function(id) if ready then return 'Icon777' end end
 C_Item.RequestLoadItemDataByID=function(id) requests=requests+1; return true end
 local name,link,icon=items:Resolve(777,'Known Herb')
 assert(name=='Known Herb' and not icon and requests==1 and items.pending[777])
 ready=true
 dispatch('GET_ITEM_INFO_RECEIVED',777,true)
 assert(not items.pending[777] and items.loaded[777])
 local _,_,resolvedIcon=items:Resolve(777,'Known Herb')
 assert(resolvedIcon=='Icon777' and requests==1)
''',
'successful_item_load_without_icon_does_not_spin': '''
 inventoryFixture(false,true)
 local items=addon.ItemDisplay
 items.pending={}; items.loaded={}
 C_Item=C_Item or {}
 local requests=0
 C_Item.GetItemInfo=function() return 'Known Herb','|Hitem:778|h[Known Herb]|h',1 end
 C_Item.GetItemIconByID=function() return nil end
 C_Item.RequestLoadItemDataByID=function() requests=requests+1; return true end
 items:Resolve(778,'Known Herb')
 dispatch('GET_ITEM_INFO_RECEIVED',778,true)
 items:Resolve(778,'Known Herb')
 items:Resolve(778,'Known Herb')
 assert(requests==1 and items.loaded[778],'successful load with no icon must not loop')
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
'modern_auction_uses_visible_search_instead_of_stale_classic_field': '''
 inventoryFixture(false,true)
 AuctionFrame=CreateFrame(); AuctionFrame:Hide()
 BrowseName=CreateFrame(); BrowseName:SetText('stale classic search')
 AuctionHouseFrame=CreateFrame(); AuctionHouseFrame:Show()
 AuctionHouseFrame.SearchBar={SearchBox=CreateFrame()}
 assert(addon.ShoppingList:SearchAuctions({name='Herb'}))
 assert(AuctionHouseFrame.SearchBar.SearchBox:GetText()=='Herb')
 assert(BrowseName:GetText()=='stale classic search')
''',
'closed_auction_never_mutates_stale_search_fields': '''
 inventoryFixture(false,true)
 AuctionFrame=CreateFrame(); AuctionFrame:Hide()
 BrowseName=CreateFrame(); BrowseName:SetText('classic unchanged')
 AuctionHouseFrame=CreateFrame(); AuctionHouseFrame:Hide()
 AuctionHouseFrame.SearchBar={SearchBox=CreateFrame()}
 AuctionHouseFrame.SearchBar.SearchBox:SetText('modern unchanged')
 assert(not addon.ShoppingList:SearchAuctions({name='Herb'}))
 assert(BrowseName:GetText()=='classic unchanged')
 assert(AuctionHouseFrame.SearchBar.SearchBox:GetText()=='modern unchanged')
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
 assert(row.Icon:GetWidth()==28 and row:GetHeight()==32, 'compact material icon/row dimensions')
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
