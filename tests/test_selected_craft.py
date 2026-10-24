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
'shift_click_recipe_links_keep_active_chat_context_on_failure': '''
    addon.Directory.GetSearchLinks=function()
        return {craft='|Hitem:99|h[Craft]|h',recipe='|Hitem:100|h[Pattern]|h'}
    end
    IsShiftKeyDown=function() return true end
    local attempts,opened=0,0
    ChatEdit_GetActiveWindow=function() return CreateFrame() end
    ChatEdit_InsertLink=function() attempts=attempts+1;error('hybrid chat insert failed') end
    ChatFrame_OpenChat=function() opened=opened+1 end
    local tab=addon.Directory.frame.ProfessionsTab
    tab.CraftItemHover.scripts.OnClick(tab.CraftItemHover,'LeftButton')
    addon.SelectedCraft.recipeButton.scripts.OnClick(addon.SelectedCraft.recipeButton,'LeftButton')
    assert(attempts==2,'both recipe link buttons should attempt the active editor')
    assert(opened==0,'never replace an active chat editor after a failed insert')
''',
'shift_click_recipe_links_guard_failed_open_chat': '''
    addon.Directory.GetSearchLinks=function()
        return {craft='|Hitem:99|h[Craft]|h',recipe='|Hitem:100|h[Pattern]|h'}
    end
    IsShiftKeyDown=function() return true end
    ChatEdit_InsertLink=function() return false end
    ChatEdit_GetActiveWindow=function() return nil end
    local opened=0
    ChatFrame_OpenChat=function() opened=opened+1;error('chat UI unavailable') end
    local tab=addon.Directory.frame.ProfessionsTab
    tab.CraftItemHover.scripts.OnClick(tab.CraftItemHover,'LeftButton')
    addon.SelectedCraft.recipeButton.scripts.OnClick(addon.SelectedCraft.recipeButton,'LeftButton')
    assert(opened==2,'fallback should try to open chat without throwing')
''',
'long_source_summary_is_bounded_but_full_details_remain_available': '''
    local view=addon.SelectedCraft
    local source=view.tab.RecipeSource
    local summary=addon.RecipeSources.Summary
    local full=addon.RecipeSources.Format
    local text=('Named vendor in a recorded location, Classic reference.\\\\n'):rep(20)
    addon.RecipeSources.Summary=function() return text end
    addon.RecipeSources.Format=function() return text end
    source.Text.GetStringHeight=function() return 400 end
    view.sourcesExpanded=false;view:Refresh()
    local compact=view.sourceHeight
    assert(source.Text:GetHeight()==72 and view.sourceSummaryClipped)
    assert(view.sourceSummaryText==text,'keep complete summary for hover')
    local captured
    GameTooltip.AddLine=function(_,value) if value==text then captured=value end end
    view.sourceToggle.scripts.OnEnter(view.sourceToggle)
    assert(captured==text,'hover must expose text omitted by compact preview')
    view.sourceToggle.scripts.OnClick()
    assert(view.sourcesExpanded and source.Text:GetHeight()==400)
    assert(not view.sourceSummaryClipped and view.sourceHeight>compact)
    view.sourceToggle.scripts.OnClick()
    assert(not view.sourcesExpanded and source.Text:GetHeight()==72)
    assert(view.sourceHeight==compact)
    addon.RecipeSources.Summary=summary;addon.RecipeSources.Format=full
''',

'primary_action_stays_beside_quantity_with_long_material_lists': '''
    local view=addon.SelectedCraft
    local tab=addon.Directory.frame.ProfessionsTab
    local original=addon.ShoppingList.GetMaterialStatus
    addon.ShoppingList.GetMaterialStatus=function()
        local entries={}
        for i=1,10 do
            entries[i]={name='Material '..i,itemID=7,icon='icon',
                owned=1,required=2,recipeRequired=2,delivered=0,crafterProvides=0}
        end
        return entries
    end
    local lastPoint
    view.craftButton.SetPoint=function(_,...) lastPoint={...} end
    for _,width in ipairs({436,360,359,600,436}) do
        tab.SelectedCraftScroll:SetWidth(width); view:Refresh()
        assert(view.actionInHeader==(width>=360))
        if width>=360 then
            assert(lastPoint[5]==-68)
            assert(view.craftButton:GetWidth()>=148)
            assert(width-12-view.craftButton:GetWidth()>=200,
                'craft action must leave quantity arrows unobscured')
        else
            assert(lastPoint[5]<-164)
        end
        assert(view.craftButton:GetHeight()==30)
    end
    addon.ShoppingList.GetMaterialStatus=original
''',

'readable_columns_at_default_width_and_stack_only_when_narrow': '''
    local view=addon.SelectedCraft
    local scroll=addon.Directory.frame.ProfessionsTab.SelectedCraftScroll
    for _,width in ipairs({436,400,399,600,436}) do
        scroll:SetWidth(width)
        view:Refresh()
        assert(view.stacked==(width<400))
        if width>=400 then
            assert(view.column>=182)
            assert(view.rows[1]:GetWidth()==view.column)
        else
            assert(view.column==width-24)
        end
    end
''',

'material_counts_and_names_remain_single_line_across_panel_widths': '''
    local view=addon.SelectedCraft
    local scroll=addon.Directory.frame.ProfessionsTab.SelectedCraftScroll
    local original=addon.ShoppingList.GetMaterialStatus
    addon.ShoppingList.GetMaterialStatus=function()
        local entries={}
        for i=1,10 do
            entries[i]={name='Extra Long Material Name '..i,itemID=7,icon='icon',
                owned=1,required=20,recipeRequired=20,delivered=0,crafterProvides=0}
        end
        return entries
    end
    for _,width in ipairs({320,399,400,436,600}) do
        scroll:SetWidth(width);view:Refresh()
        for i=1,10 do
            local row=view.rows[i]
            assert(row:IsShown() and row:GetHeight()==32)
            assert(row.Icon:GetWidth()==28 and row.Count:GetHeight()==28)
            assert(row.Count:GetText():find('1 / 20',1,true))
            assert(row.Label:GetText():find('Extra Long Material Name',1,true))
        end
    end
    addon.ShoppingList.GetMaterialStatus=original
''',
'quantity_keeps_native_arrows_across_theme_changes_and_accepts_typing': '''
    local tab=addon.Directory.frame.ProfessionsTab
    for _,arrow in ipairs({tab.CraftRosterQuantityUp,tab.CraftRosterQuantityDown}) do
        assert(arrow:GetText()=='' and arrow:GetHeight()==14)
        arrow.SetNormalTexture=function() error('themes must not overwrite native arrows') end
    end
    for _,palette in ipairs(addon.Theme.palettes) do addon.Theme:SetPalette(palette.key) end
    addon.SelectedCraft:Refresh()
    local field=tab.CraftRosterQuantity
    field:SetText('25'); field.scripts.OnTextChanged(field,true)
    field.scripts.OnEnterPressed(field)
    assert(field:GetText()=='25' and addon.ShoppingList:GetQuantity(42)==25)
    tab.CraftRosterQuantityDown.scripts.OnClick()
    assert(field:GetText()=='24' and addon.ShoppingList:GetQuantity(42)==24)
''',
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
    assert(addon.Directory.frame.ProfessionsTab.CraftRosterQuantityUp:GetHeight()==14)
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
'unverified_acquisition_has_no_disabled_navigation_rows': '''
    CraftRosterDB.recipes[1255143]={name='Moonglow Boots',profession='Leatherworking'}
    addon.Directory.selectedRecipe={id=1255143,name='Moonglow Boots',profession='Leatherworking',crafters={}}
    addon.SelectedCraft:Refresh()
    local source=addon.Directory.frame.ProfessionsTab.RecipeSource
    local toggle=addon.SelectedCraft.sourceToggle
    toggle.scripts.OnClick()
    assert(addon.SelectedCraft.sourcesExpanded)
    assert(source.Text:GetText():find('Granny Finespindle',1,true))
    assert(not addon.SelectedCraft.locationRows[1] or not addon.SelectedCraft.locationRows[1]:IsShown(),
      'unverified source must not create empty navigation rows')
    -- A confirmed record still gets usable copy/map controls.
    addon.RecipeLocations.bySpell[1255143]={
      {kind='vendor',npcID=123,name='Confirmed Vendor',zone='Test Zone',x=25,y=75,
       status='confirmed',url='https://example.org/forever/123',revision='fixture',checked='2026-10-23'}
    }
    addon.SelectedCraft:Refresh()
    local row=addon.SelectedCraft.locationRows[1]
    assert(row and row:IsShown() and row.Copy:IsEnabled())
    assert(row.Copy:GetText()=='Copy coords')
    addon.RecipeLocations.bySpell[1255143]={
      {kind='vendor',npcID=123,name='Unverified Vendor',zone='Test Zone',x=25,y=75,status='reference'}
    }
    addon.SelectedCraft:Refresh()
    assert(not row:IsShown(),'stale confirmed navigation must hide when source becomes unverified')
''',
'moonglow_boots_acquisition_uses_forever_vendor_not_old_quest': '''
    CraftRosterDB.recipes[1255143]={name='Moonglow Boots',profession='Leatherworking'}
    addon.Directory.selectedRecipe={id=1255143,name='Moonglow Boots',profession='Leatherworking',crafters={}}
    addon.SelectedCraft:Refresh()
    local text=addon.Directory.frame.ProfessionsTab.RecipeSource.Text:GetText()
    assert(text:find('Granny Finespindle',1,true) and text:find('Ironforge',1,true))
    assert(not text:find('39.3, 33.7',1,true),'unverified coordinates must not appear in the recipe pane')
    assert(text:find('Alliance',1,true) and text:find('ATT Forever reference',1,true))
    assert(not text:find('Source unknown',1,true) and not text:find('Quest:',1,true))
    local old=addon.RecipeSources:Format(8322)
    assert(not old:find('Granny Finespindle',1,true),'different recipes must not inherit acquisition by name')
''',
'hybrid_inventory_scans_bags_once_when_count_apis_fail': '''
    C_Item=C_Item or {}
    C_Item.GetItemCount=function() error('modern API unavailable') end
    GetItemCount=nil
    C_Container=nil
    NUM_BAG_SLOTS=1
    local scans=0
    GetContainerNumSlots=function() scans=scans+1; return 0 end
    GetContainerItemLink=function() return nil end
    GetContainerItemInfo=function() return nil,0 end
    local entries,ready,unavailable=addon.ShoppingList:GetMaterialStatus(42)
    assert(entries and entries[1].owned==0)
    assert(ready==0 and not unavailable)
    assert(scans==2,'only scan bags 0 and 1 once')
''',
'hybrid_inventory_uses_legacy_count_when_modern_api_errors': '''
    C_Item=C_Item or {}
    C_Item.GetItemCount=function() error('modern count API unavailable') end
    GetItemCount=function(id)
        if id==7 then return 9 end
        return 0
    end
    local entries,ready,unavailable=addon.ShoppingList:GetMaterialStatus(42)
    assert(entries and entries[1].owned==9 and entries[1].required==3)
    assert(ready==#entries and not unavailable)
    addon.SelectedCraft:Refresh()
    assert(addon.SelectedCraft.entries[1].owned==9)
''',
'hybrid_inventory_uses_legacy_count_when_modern_returns_nil': '''
    C_Item=C_Item or {}
    C_Item.GetItemCount=function() return nil end
    GetItemCount=function(id)
        if id==7 then return 6 end
        return 0
    end
    local entries,ready,unavailable=addon.ShoppingList:GetMaterialStatus(42)
    assert(entries and entries[1].owned==6 and entries[1].required==3)
    assert(ready==#entries and not unavailable)
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
    assert(row.Icon and row.Count:GetText():find('24 / 3',1,true))
    assert(row.Label:GetText():find('Herb',1,true))
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
