"""Behavioral checks with mocked APIs; these do not replace in-game testing."""
import importlib
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]

CASES = {
    'teaching_item_binding_and_reference_rates': """
        addon.RecipeSources:SeedCatalog()
        assert(not CraftRosterDB.characters['Tester-Realm'].recipes[19054])
        CraftRosterDB.recipes[19054].itemLink='item:15047'
        local d=addon.RecipeSources:Get(19054)
        assert(d.itemID==15730 and d.link:find('item:15730',1,true))
        assert(d.binding:find('picked up',1,true) and d.binding:find('Classic reference',1,true))
        local text=addon.RecipeSources:Format(19054,d)
        assert(text:find('~4.95%',1,true) and text:find('Forever source/rate unconfirmed',1,true))
        assert(addon.RecipeSources:Format(20034):find('Mob drop: Scarlet Spellbinder',1,true))
        assert(addon.RecipeSources:Format(20034):find('~0.43%',1,true))
        C_Item={GetItemInfo=function(id)
          assert(id==15730)
          return 'Pattern: Test','item:15730',4,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,2
        end}
        d=addon.RecipeSources:Get(19054)
        assert(d.binding=='Binds when equipped' and d.quality==4)
        local unknown=addon.RecipeSources:Get(99999)
        assert(not unknown.itemID and not unknown.binding)
        assert(addon.RecipeSources:Format(99999):find('Drop chance: unknown',1,true))
    """,
    'optional_forever_database_and_safe_fallback': """
        local version='Vanilla'
        local db={IsReady=function() return true end,GetGameVersion=function() return version end,
          GetRecipeItem=function() return 98765,false end,
          GetRecipeSources=function() return {drop={{id=123,name='Example Boss'}}} end,
          IsBorrowed=function() return 'Vanilla' end}
        LibStub=setmetatable({}, {__call=function() return db end})
        assert(not addon.RecipeSources:Get(99999).itemID)
        version='Forever'
        assert(addon.RecipeSources:Get(99999).itemID==98765)
        local text=addon.RecipeSources:Format(99999)
        assert(text:find('Example Boss',1,true) and text:find('Vanilla reference',1,true))
        assert(text:find('Drop chance: unknown',1,true))
        db.GetRecipeItem=function() error('database temporarily unavailable') end
        assert(not addon.RecipeSources:Get(99999).itemID)
        db.GetRecipeItem=function() return 98765,true end
        assert(not addon.RecipeSources:Get(99999).itemID)
    """,
    'teaching_item_cache_and_native_link': """
        local loads=0
        C_Item={RequestLoadItemDataByID=function() loads=loads+1 end}
        addon.RecipeSources:Get(19054); addon.RecipeSources:Get(19054)
        assert(loads==1)
        SlashCmdList.CRAFTROSTER('')
        for _,entry in ipairs(addon.Directory.professionCache.entries) do
          if entry.id==19054 then addon.Directory.selectedRecipe=entry.recipe end
        end
        addon.Directory:RefreshDetails()
        addon.Directory:RefreshRecipeSource()
        local link, found
        GameTooltip.SetHyperlink=function(_,value) link=value end
        local source=addon.Directory.frame.ProfessionsTab.RecipeSource
        local button=addon.SelectedCraft.recipeButton
        button.scripts.OnEnter(button); assert(link:find('item:15730',1,true))
        IsShiftKeyDown=function() return true end
        ChatEdit_InsertLink=function(value) link=value; return true end
        button.scripts.OnClick(button); assert(link:find('item:15730',1,true))
        local refreshes=0
        addon.Directory.RefreshRecipeSource=function() refreshes=refreshes+1 end
        dispatch('GET_ITEM_INFO_RECEIVED',15730,true)
        assert(refreshes==1)
        addon.Directory.frame:Hide()
        dispatch('GET_ITEM_INFO_RECEIVED',15730,true)
        assert(refreshes==1)
    """,

    'fresh_and_existing_settings': '''
        assert(CraftRosterDB.settings.enabled and CraftRosterDB.settings.autoUpdateRecipes)
        assert(not addon.Directory.frame and not addon.Panel.frame)
        SlashCmdList.CRAFTROSTER(''); assert(addon.Directory.frame:IsShown())
        assert(CraftRosterDB.settings.window.width == 1000)
        assert(addon.Directory.frame.ProfessionsTab.CraftRosterTradeButton)
        SlashCmdList.CRAFTROSTER('settings'); assert(addon.Panel.frame:IsShown())
        SlashCmdList.CRAFTROSTER('reset')
        SlashCmdList.CRAFTROSTER('toggle'); assert(not CraftRosterDB.settings.enabled)
    ''',
    'debounce_or_timerless_fallback': '''
        SlashCmdList.CRAFTROSTER('')
        local search=addon.Directory.frame.ProfessionsTab.SearchBox
        search.scripts.OnTextChanged(); search.scripts.OnTextChanged()
        if C_Timer then
          assert(#timers==2 and timers[1].cancelled and timers[2].delay==0.25)
          flushTimers()
        end
    ''',
    'sync_validation_and_metadata_preservation': '''
        CraftRosterDB.characters['Crafter-Realm']={class='MAGE', recipes={}}
        dispatch('CHAT_MSG_ADDON','CRAFTROSTER','DATA:Crafter-Realm:123:Alchemy:100:150:1|42:100','GUILD','Crafter-Realm')
        local c=CraftRosterDB.characters['Crafter-Realm']
        assert(c.recipes[42] and c.class=='MAGE')
        for _,message in ipairs({'DATA:Crafter-Realm:122:|99:1','DATA:Crafter-Realm:125:broken', 'DATA:Crafter-Realm:125:|oops','DATA:Tester-Realm:125:|99:1','DATA:Crafter-Realm:99999999999999999999999:|99:1'}) do
          dispatch('CHAT_MSG_ADDON','CRAFTROSTER',message,'GUILD','Crafter-Realm')
        end
        dispatch('CHAT_MSG_ADDON','CRAFTROSTER',{},'GUILD','Crafter-Realm')
        dispatch('CHAT_MSG_ADDON','CRAFTROSTER','DATA:Other-Realm:125:|99:1','WHISPER','Other-Realm')
        assert(c.recipes[42] and not c.recipes[99] and not CraftRosterDB.characters['Other-Realm'])
    ''',
    'sync_large_payload_roundtrip': '''
        if not C_Timer or (not C_ChatInfo and not SendAddonMessage) then return end
        local recipes=CraftRosterDB.characters['Tester-Realm'].recipes
        CraftRosterDB.recipes[200]={name='Potion: Strong; | 100%',profession='Alchemy'}
        for id=1,200 do recipes[id]={learnedAt=100} end
        addon.GuildSync:SendData()
        clock=clock+11; addon.GuildSync:SendData(); assert(#sent==1)
        flushTimers()
        assert(#sent>1)
        CraftRosterDB.recipes[200]=nil
        -- Reverse order and duplicate delivery must still reconstruct one complete snapshot.
        for i=#sent,1,-1 do
          assert(#sent[i][2]<=255)
          local message=sent[i][2]:gsub('Tester%-Realm','Helper-Realm')
          dispatch('CHAT_MSG_ADDON','CRAFTROSTER',message,'GUILD','Helper-Realm')
          dispatch('CHAT_MSG_ADDON','CRAFTROSTER',message,'GUILD','Helper-Realm')
        end
        assert(CraftRosterDB.characters['Helper-Realm'].recipes[200])
        assert(CraftRosterDB.recipes[200].name=='Potion: Strong; | 100%')
    ''',
    'sync_malformed_chunks': '''
        for _,message in ipairs({'PART:1:0:2:x','PART:1:1:99999:x','PART:1:3:2:x','PART:1:1:2:x', 'PART:1:2:3:y', 'PART:2:1:1:garbage'}) do
          dispatch('CHAT_MSG_ADDON','CRAFTROSTER',message,'GUILD','Crafter-Realm')
        end
        assert(not CraftRosterDB.characters['Crafter-Realm'])
    ''',
    'disabled_blocks_background_work': '''
        CraftRosterDB.settings.enabled=false
        dispatch('NEW_RECIPE_LEARNED',99)
        dispatch('CHAT_MSG_ADDON','CRAFTROSTER','DATA:Crafter-Realm:123:|99:1','GUILD','Crafter-Realm')
        addon.GuildSync:SyncNow(); addon.GuildSync:SendData()
        assert(#sent==0 and not CraftRosterDB.recipes[99] and not CraftRosterDB.characters['Crafter-Realm'])
    ''',
    'status_sender_and_error_inputs': '''
        CraftRosterDB.requests={{id='test',recipe='Potion',target='Crafter-Realm',status='requested'}}
        dispatch('CHAT_MSG_ADDON','CRAFTROSTER','RSTAT:test:accepted','GUILD','Other-Realm')
        assert(CraftRosterDB.requests[1].status=='requested')
        dispatch('CHAT_MSG_ADDON','CRAFTROSTER','RSTAT:test:accepted','GUILD','Crafter-Realm')
        assert(CraftRosterDB.requests[1].status=='accepted')
        dispatch('CHAT_MSG_ADDON','CRAFTROSTER',false,'GUILD','Crafter-Realm')
        SlashCmdList.CRAFTROSTERSTATUS(nil)
        addon.Requests:StartMailRequest(42,nil); addon.Requests:StartTradeRequest(42,nil)
    ''',
    'request_input_validation': '''
        CraftRosterDB.recipes[42]={name='Potion',materials={{name='Herb',itemID=7,count=3}}}
        addon.Requests:StartMailRequest(42,'invalid')
        addon.Requests:StartTradeRequest(42,'')
        assert(not CraftRosterDB.requests)
        addon.Requests:StartMailRequest(42,'Crafter-Realm')
        assert(#CraftRosterDB.requests==1)
        addon.Requests:Cancel()
    ''',
    'recipe_modern_enumeration_and_cache_refresh': '''
        C_TradeSkillUI={GetTradeSkillLine=function() return {professionName='Alchemy'} end,
          GetAllRecipeIDs=function() return {42} end,
          GetRecipeInfo=function() return {learned=true,name='Potion'} end,
          GetRecipeSchematic=function() return {reagentSlotSchematics={{quantityRequired=3,reagents={{itemID=7,name='Herb'},{itemID=8,name='Alternative'}}}}} end}
        assert(addon.RecipeTracker:ImportTradeSkillRecipes()==1)
        assert(CraftRosterDB.recipes[42].profession=='Alchemy')
        assert(#CraftRosterDB.recipes[42].materials==1)
        C_TradeSkillUI.GetRecipeSchematic=function() return {reagentSlotSchematics={{quantityRequired=4,reagents={{itemID=7,name='Herb'}}}}} end
        local old=CraftRosterDB.lastRecipeUpdate; clock=clock+1
        assert(addon.RecipeTracker:ImportTradeSkillRecipes()==0)
        assert(CraftRosterDB.recipes[42].materials[1].count==4 and CraftRosterDB.lastRecipeUpdate>old)
    ''',
    'legacy_recipe_api': '''
        function GetNumTradeSkills() return 1 end
        function GetTradeSkillLine() return 'Alchemy' end
        function GetTradeSkillInfo() return 'Potion','optimal' end
        function GetTradeSkillRecipeLink() return '|cffff|Henchant:42|h[Potion]|h' end
        function GetTradeSkillNumReagents() return 1 end
        function GetTradeSkillReagentInfo() return 'Herb','icon',3,99 end
        assert(addon.RecipeTracker:ImportTradeSkillRecipes()==1)
        assert(CraftRosterDB.recipes[42].name=='Potion' and CraftRosterDB.recipes[42].materials[1].count==3)
    ''',
    'sparse_profession_api': '''
        GetNumProfessions=nil
        function GetProfessions() return nil,17 end
        function GetProfessionInfo(id) assert(id==17); return 'Alchemy',nil,100,150 end
        addon.RecipeTracker:UpdateProfessions()
        assert(CraftRosterDB.characters['Tester-Realm'].professions.Alchemy.skill==100)
    ''',
    'filtered_selection_cleared': '''
        CraftRosterDB.recipes[42]={name='Potion',profession='Alchemy'}
        CraftRosterDB.characters['Tester-Realm'].recipes[42]={}
        SlashCmdList.CRAFTROSTER('')
        addon.Directory.selectedRecipe={id=42,crafters={'Tester-Realm'}}
        addon.Directory.frame.ProfessionsTab.SearchBox:SetText('absent')
        addon.Directory:RefreshProfessions()
        assert(addon.Directory.selectedRecipe==nil)
    ''',
    'restricted_sync_retry': '''
        if not C_ChatInfo then return end
        C_ChatInfo.InChatMessagingLockdown=function() return true end
        addon.GuildSync:SendData(); assert(#sent==0)
        C_ChatInfo.InChatMessagingLockdown=function() return false end
        addon.GuildSync:SendData(); assert(#sent==1)
    ''',
}

CASES.update({
    'exact_trade_stack_quantity': """
        inventoryFixture(false,true)
        addon.Requests:StartTradeRequest(42,'Crafter-Realm')
        dispatch('TRADE_SHOW')
        assert(moved==3 and inventory[1].count==17 and not cursor)
        dispatch('TRADE_SHOW'); assert(moved==3)
    """,
    'occupied_mail_draft_is_not_modified': """
        inventoryFixture(false,true); attachments[1]=8
        addon.Requests:StartMailRequest(42,'Crafter-Realm')
        dispatch('MAIL_SHOW')
        assert(moved==0 and attachments[1]==8 and attachments[2]==nil and inventory[1].count==20)
        dispatch('MAIL_SHOW'); assert(moved==0)
    """,
    'locked_stack_skipped': """
        inventoryFixture(true,true)
        addon.Requests:StartMailRequest(42,'Crafter-Realm'); dispatch('MAIL_SHOW')
        assert(moved==3 and inventory[1].count==20 and inventory[2].count==1)
    """,
    'missing_split_does_not_move_oversized_stack': """
        inventoryFixture(false,false)
        addon.Requests:StartTradeRequest(42,'Crafter-Realm'); dispatch('TRADE_SHOW')
        assert(moved==0 and inventory[1].count==20)
    """,
    'cursor_full_or_wrong_trade_partner': """
        inventoryFixture(false,true)
        addon.Requests:StartTradeRequest(42,'Other-Realm'); dispatch('TRADE_SHOW'); assert(moved==0)
        addon.Requests:StartMailRequest(42,'Crafter-Realm'); cursor=9; dispatch('MAIL_SHOW'); assert(moved==0 and cursor==9)
    """,
    'full_attachment_slots': """
        inventoryFixture(false,true)
        for i=1,12 do attachments[i]=1 end
        addon.Requests:StartMailRequest(42,'Crafter-Realm'); dispatch('MAIL_SHOW')
        assert(moved==0 and inventory[1].count==20)
    """,
    'incoming_request_status_roundtrip': """
        dispatch('CHAT_MSG_ADDON','CRAFTROSTER','ORDER:42:request-1:Tester-Realm:Potion','GUILD','Crafter-Realm')
        assert(#CraftRosterDB.requests==1 and CraftRosterDB.requests[1].mode=='incoming')
        dispatch('CHAT_MSG_ADDON','CRAFTROSTER','ORDER:42:request-1:Tester-Realm:Potion','GUILD','Crafter-Realm')
        assert(#CraftRosterDB.requests==1)
        SlashCmdList.CRAFTROSTERSTATUS('request-1 accepted')
        assert(CraftRosterDB.requests[1].status=='accepted')
        if C_ChatInfo or SendAddonMessage then assert(sent[#sent][2]=='RSTAT:request-1:accepted') end
    """,
    'invalid_saved_materials_do_not_arm': """
        CraftRosterDB.recipes[42]={name='Potion',materials={{name='Herb',count=-3}}}
        addon.Requests:StartTradeRequest(42,'Crafter-Realm')
        assert(not CraftRosterDB.requests)
        CraftRosterDB.recipes[42].materials={{name='Herb'}}
        addon.Requests:StartMailRequest(42,'Crafter-Realm')
        assert(not CraftRosterDB.requests)
    """,
    'missing_trade_api_never_falls_back_to_mail': """
        inventoryFixture(false,true); ClickTradeButton=nil
        addon.Requests:StartTradeRequest(42,'Crafter-Realm'); dispatch('TRADE_SHOW')
        assert(moved==0 and not cursor)
    """,
    'popup_receives_recipe_data': """
        CraftRosterDB.recipes[42]={name='Potion',profession='Alchemy'}
        SlashCmdList.CRAFTROSTER('')
        addon.Directory.selectedRecipe={id=42}
        addon.Directory.frame.ProfessionsTab.CraftRosterTradeButton.scripts.OnClick()
        assert(addon.WhisperComposer.recipeID==42 and addon.WhisperComposer.frame:IsShown())
        assert(not CraftRosterDB.requests)
    """,
})

CASES.update({
    'large_directory_bounded_frames_and_scroll_reuse': """
        addon.RecipeSources.catalogLoaded=true -- isolate the synthetic scrolling fixture
        local own=CraftRosterDB.characters['Tester-Realm'].recipes
        for id=1,5000 do
          CraftRosterDB.recipes[id]={name=('Potion %05d'):format(id),profession='Alchemy'}
          own[id]={}
        end
        for index=1,20 do CraftRosterDB.characters['Crafter'..index..'-Realm']={recipes=own} end
        local before=#frames
        SlashCmdList.CRAFTROSTER('')
        assert(#addon.Directory.recipeIndex==5004)
        assert(#frames-before<125, 'offscreen recipes must not allocate unbounded UI objects')
        local tab=addon.Directory.frame.ProfessionsTab
        local poolRows=0
        for _,row in ipairs(frames) do
          if row.parent==tab.ResultsChild and row.Label then poolRows=poolRows+1 end
        end
        assert(poolRows<=math.ceil(tab.Results:GetHeight()/48)+3,'recipe rows must remain viewport-bounded')
        local count=#frames
        local cached=addon.Directory.professionCache
        for _,offset in ipairs({10000,50000,100000,190000,0}) do
          tab.Results:SetVerticalScroll(offset)
          tab.Results.scripts.OnVerticalScroll(tab.Results,offset)
        end
        assert(#frames-count<10, 'scrolling must reuse rows')
        addon.Directory:RefreshProfessions()
        assert(addon.Directory.professionCache==cached)
    """,
    'scan_burst_coalescing_and_unchanged_data': """
        local scans=0
        C_TradeSkillUI={GetAllRecipeIDs=function() scans=scans+1; return {42} end,
          GetRecipeInfo=function() return {name='Potion',learned=true} end}
        for i=1,20 do dispatch('TRADE_SKILL_LIST_UPDATE') end
        if C_Timer then assert(scans==0); flushTimers(); assert(scans==1) else assert(scans==20) end
        SlashCmdList.CRAFTROSTER('')
        local index=addon.Directory.recipeIndex
        local saved=CraftRosterDB.recipes[42]
        local stamp=CraftRosterDB.lastRecipeUpdate
        clock=clock+20
        addon.RecipeTracker:ImportTradeSkillRecipes()
        assert(CraftRosterDB.recipes[42]==saved and addon.Directory.recipeIndex==index)
        assert(CraftRosterDB.lastRecipeUpdate==stamp)
    """,
    'only_active_tab_refreshed': """
        SlashCmdList.CRAFTROSTER('')
        addon.Directory:ShowTab(2)
        local players, professions, mine=0,0,0
        addon.Directory.RefreshPlayers=function() players=players+1 end
        addon.Directory.RefreshProfessions=function() professions=professions+1 end
        addon.Directory.RefreshMyRecipes=function() mine=mine+1 end
        addon.Directory:RefreshIfVisible()
        assert(players==1 and professions==0 and mine==0)
        addon.Directory.frame:Hide(); addon.Directory:InvalidateIndex()
        assert(players==1)
    """,
    'favorites_filter_and_live_removal': """
        CraftRosterDB.recipes[42]={name='Potion',profession='Alchemy'}
        CraftRosterDB.recipes[43]={name='Elixir',profession='Alchemy'}
        CraftRosterDB.characters['Tester-Realm'].recipes={[42]={},[43]={}}
        CraftRosterDB.favorites={[42]=true}; CraftRosterDB.settings.favoritesOnly=true
        SlashCmdList.CRAFTROSTER('')
        assert(#addon.Directory.professionCache.entries==1 and addon.Directory.professionCache.entries[1].id==42)
        for _,entry in ipairs(addon.Directory.professionCache.entries) do if entry.id==42 then addon.Directory.selectedRecipe=entry.recipe end end
        addon.Directory.frame.ProfessionsTab.CraftRosterFavoriteButton.scripts.OnClick()
        assert(#addon.Directory.professionCache.entries==0 and addon.Directory.selectedRecipe==nil)
    """,
    'learned_event_records_before_sending_and_queues_throttle': """
        dispatch('NEW_RECIPE_LEARNED',42)
        if C_ChatInfo or SendAddonMessage then assert(sent[1][2]:find('42:')) end
        dispatch('NEW_RECIPE_LEARNED',43)
        if C_Timer and (C_ChatInfo or SendAddonMessage) then
          flushTimers(); assert(sent[#sent][2]:find('43:'))
        end
    """,
    'manual_scan_error_restores_state': """
        C_TradeSkillUI={GetAllRecipeIDs=function() error('scan failure') end,GetRecipeInfo=function() end}
        local ok=pcall(function() addon.RecipeTracker:UpdateKnownRecipes() end)
        assert(not ok and addon.RecipeTracker.manualUpdateInProgress==nil)
    """,
    'linked_profession_never_saved_as_player_recipe': """
        C_TradeSkillUI={IsTradeSkillLinked=function() return true end,
          GetAllRecipeIDs=function() error('must not enumerate linked recipes') end,GetRecipeInfo=function() end}
        assert(addon.RecipeTracker:ImportTradeSkillRecipes()==0)
        assert(next(CraftRosterDB.recipes)==nil)
    """,
    'optional_reagent_slots_skipped': """
        C_TradeSkillUI={GetAllRecipeIDs=function() return {42} end,
          GetRecipeInfo=function() return {learned=true,name='Potion'} end,
          GetRecipeSchematic=function() return {reagentSlotSchematics={
            {required=false,quantityRequired=1,reagents={{name='Optional',itemID=8}}},
            {quantityRequired=3,reagents={{name='Herb',itemID=7}}}}} end}
        addon.RecipeTracker:ImportTradeSkillRecipes()
        assert(#CraftRosterDB.recipes[42].materials==1 and CraftRosterDB.recipes[42].materials[1].itemID==7)
    """,
    'cross_realm_online_names_do_not_collide': """
        CraftRosterDB.characters['Bob-Other']={recipes={[42]={}}}
        CraftRosterDB.characters['Bob-Realm']={recipes={[42]={}}}
        CraftRosterDB.recipes[42]={name='Potion'}
        function GetNumGuildMembers() return 1 end
        function GetGuildRosterInfo() return 'Bob-Realm',nil,nil,nil,nil,nil,nil,nil,true end
        CraftRosterDB.settings.onlineOnly=true
        SlashCmdList.CRAFTROSTER('')
        for _,entry in ipairs(addon.Directory.professionCache.entries) do if entry.id==42 then addon.Directory.selectedRecipe=entry.recipe end end
        dispatch('GUILD_ROSTER_UPDATE')
        local child=addon.Directory.frame.ProfessionsTab.CrafterListChild
        local rows=0
        for _,frame in ipairs(frames) do
          if frame.parent==child and frame:IsShown() and frame.Label then
            rows=rows+1; assert(frame.tooltipLines[1]=='Bob-Realm')
          end
        end
        assert(rows==1)
    """,
})

CASES.update({
    'unchanged_sync_reuses_serialized_payload': """
        if not (C_ChatInfo or SendAddonMessage) then return end
        local character=CraftRosterDB.characters['Tester-Realm']
        character.recipes[42]={learnedAt=1}
        local calls=0; local format=string.format
        string.format=function(...) calls=calls+1; return format(...) end
        addon.GuildSync:SendData()
        assert(#sent==1)
        local first=calls; clock=clock+31
        addon.GuildSync:SendData()
        assert(calls==first and #sent==1, 'unchanged sends must not reserialize or transmit')
        dispatch('CHAT_MSG_ADDON','CRAFTROSTER','REQ','GUILD','Crafter-Realm')
        assert(#sent==2, 'explicit peer request must still receive cached data')
    """,
    'unchanged_peer_snapshot_keeps_directory_cache': """
        dispatch('CHAT_MSG_ADDON','CRAFTROSTER','DATA:Crafter-Realm:123:|42:1','GUILD','Crafter-Realm')
        SlashCmdList.CRAFTROSTER('')
        local index=addon.Directory.recipeIndex
        dispatch('CHAT_MSG_ADDON','CRAFTROSTER','DATA:Crafter-Realm:124:|42:1','GUILD','Crafter-Realm')
        assert(addon.Directory.recipeIndex==index)
    """,
    'remote_recipe_request_without_material_schematic': """
        CraftRosterDB.recipes[42]={name='Runecloth Bag',profession='Tailoring'}
        addon.Requests:RequestCraft(42,'Crafter-Realm')
        assert(#CraftRosterDB.requests==1 and CraftRosterDB.requests[1].mode=='craft')
        if C_ChatInfo or SendAddonMessage then assert(sent[1][2]:find('ORDER:42:')) end
    """,
    'completed_request_cannot_regress': """
        CraftRosterDB.requests={{id='test',recipe='Bag',target='Crafter-Realm',status='completed'}}
        dispatch('CHAT_MSG_ADDON','CRAFTROSTER','RSTAT:test:accepted','GUILD','Crafter-Realm')
        assert(CraftRosterDB.requests[1].status=='completed')
        SlashCmdList.CRAFTROSTERSTATUS('test accepted')
        assert(CraftRosterDB.requests[1].status=='completed')
    """,
    'directory_content_stays_inside_window': """
        local originalCreateFrame=CreateFrame
        function CreateFrame(...)
            local frame=originalCreateFrame(...)
            frame.layoutPoints={}
            function frame:SetPoint(...) table.insert(self.layoutPoints,{...}) end
            return frame
        end
        SlashCmdList.CRAFTROSTER('')
        local frame=addon.Directory.frame
        for _,button in ipairs(frame.TabButtons) do
            local point=button.layoutPoints[1]
            assert(point[1]=='BOTTOMLEFT' and point[2]==frame and point[5]>=0)
        end
        for _,name in ipairs({'ProfessionsTab','PlayersTab','MyRecipesTab'}) do
            local tab=frame[name]
            local top,bottom=tab.layoutPoints[1],tab.layoutPoints[2]
            assert(top[2]==frame and top[5]<0)
            assert(bottom[2]==frame and bottom[4]<0 and bottom[5]>=50)
            local listBottom=tab.Results.layoutPoints[2]
            assert(listBottom[#listBottom]>0, 'List extends below content')
        end
        local tab=frame.ProfessionsTab
        assert(tab.CrafterList.layoutPoints[2][3]>0)
        local online=tab.OnlineCheck.layoutPoints[1]
        assert(online[4]==420 and online[5]==-44)
    """,
    'forever_tabs_without_character_template': """
        local originalCreateFrame=CreateFrame
        function CreateFrame(kind,name,parent,template)
            assert(template~='CharacterFrameTabButtonTemplate', 'Unavailable Forever template')
            local frame=originalCreateFrame(kind,name,parent,template)
            function frame:SetEnabled(enabled) self.enabled=enabled end
            return frame
        end
        local function unsupported() error('Legacy tab API must not be used') end
        PanelTemplates_SelectTab=unsupported
        PanelTemplates_DeselectTab=unsupported
        PanelTemplates_SetTabState=unsupported
        SlashCmdList.CRAFTROSTER('')
        for index=1,3 do
            addon.Directory:ShowTab(index)
            local frame=addon.Directory.frame
            assert(frame.TabButtons[index].enabled==false)
            assert(frame.TabButtons[index%3+1].enabled==true)
            assert(frame.TabButtons[index].template=='UIPanelButtonTemplate')
            assert(frame.ProfessionsTab:IsShown()==(index==1))
            assert(frame.PlayersTab:IsShown()==(index==2))
            assert(frame.MyRecipesTab:IsShown()==(index==3))
        end
        GetBuildInfo=nil; SlashCmdList.CRAFTROSTERDIAGNOSTICS()
    """,
    'inventory_one_pass_and_duplicate_material_aggregation': """
        inventoryFixture(false,true)
        CraftRosterDB.recipes[42].materials={{name='Herb',itemID=7,count=1},{name='Herb',itemID=7,count=2}}
        local calls=0
        if C_Container then
          local old=C_Container.GetContainerItemLink
          C_Container.GetContainerItemLink=function(...) calls=calls+1; return old(...) end
        else
          local old=GetContainerItemLink
          GetContainerItemLink=function(...) calls=calls+1; return old(...) end
        end
        addon.Requests:StartMailRequest(42,'Crafter-Realm'); dispatch('MAIL_SHOW')
        assert(moved==3 and calls<=2 and attachments[1]==3)
    """,
})

CASES.update({
    'incomplete_schematic_preserves_complete_materials': """
        CraftRosterDB.recipes[42]={name='Potion',materials={{name='Herb',itemID=7,count=3}}}
        CraftRosterDB.characters['Tester-Realm'].recipes[42]={}
        local old=CraftRosterDB.recipes[42].materials
        C_TradeSkillUI={GetAllRecipeIDs=function() return {42} end,
          GetRecipeInfo=function() return {name='Potion',learned=true} end,
          GetRecipeSchematic=function() return {reagentSlotSchematics={
            {quantityRequired=3,reagents={{itemID=7,name='Herb'}}},
            {quantityRequired=1,reagents={{itemID=8}}}}} end}
        GetItemInfo=function() return nil end
        addon.RecipeTracker:ImportTradeSkillRecipes()
        assert(CraftRosterDB.recipes[42].materials==old)
    """,
    'end_of_virtual_list_click_uses_current_recipe': """
        addon.RecipeSources.catalogLoaded=true -- isolate the synthetic scrolling fixture
        for id=1,1000 do
          CraftRosterDB.recipes[id]={name=('Potion %04d'):format(id)}
          CraftRosterDB.characters['Tester-Realm'].recipes[id]={}
        end
        SlashCmdList.CRAFTROSTER('')
        local tab=addon.Directory.frame.ProfessionsTab
        tab.ResultsChild.scrollToEntry(1000)
        local found=false
        for _,row in ipairs(frames) do
          if row.parent==tab.ResultsChild and row:IsShown() and row.Label and row.Label:GetText()=='Potion 1000' then
            row.scripts.OnMouseUp(row,'LeftButton'); found=true
          end
        end
        assert(found and addon.Directory.selectedRecipe.id==1000)
    """,
})

CASES.update({
    'shopping_button_opens_independent_live_list': """
        inventoryFixture(false,true)
        CraftRosterDB.characters['Tester-Realm'].recipes[42]={}
        SlashCmdList.CRAFTROSTER('')
        for _,entry in ipairs(addon.Directory.professionCache.entries) do if entry.id==42 then addon.Directory.selectedRecipe=entry.recipe end end
        addon.Directory.frame.ProfessionsTab.CraftRosterShoppingButton.scripts.OnClick()
        local list=addon.ShoppingList
        assert(list.frame.parent==UIParent and list.frame:IsShown())
        assert(list.entries[1].owned==24 and list.entries[1].required==3)
        addon.Directory:Toggle(); assert(not addon.Directory.frame:IsShown() and list.frame:IsShown())
        inventory[1].count=1; inventory[2].count=0
        for i=1,20 do dispatch('BAG_UPDATE',0) end
        flushTimers()
        assert(list.entries[1].owned==1 and list.frame.Summary:GetText()=='0 of 1 materials ready')
        assert(list.frame.Rows[1]:GetText():find('need 2'))
    """,
    'shopping_close_stops_updates_and_command_reopens': """
        inventoryFixture(false,true); addon.ShoppingList:Open(42)
        local frame=addon.ShoppingList.frame
        dispatch('BAG_UPDATE',0)
        frame.Close.scripts.OnClick()
        assert(not frame:IsShown() and next(frame.events)==nil)
        assert(CraftRosterDB.characters['Tester-Realm'].shoppingList.visible==false)
        inventory[1].count=0; inventory[2].count=0
        flushTimers(); assert(addon.ShoppingList.entries[1].owned==24)
        SlashCmdList.CRAFTROSTER('shopping')
        assert(frame:IsShown() and addon.ShoppingList.entries[1].owned==0 and frame.events.BAG_UPDATE)
    """,
    'shopping_modern_and_legacy_count_apis_exclude_banks': """
        CraftRosterDB.recipes[42]={name='Potion',materials={{name='Herb',itemID=7,count=3}}}
        local calls=0
        local function count(id,bank,uses,reagent,account)
          assert(id==7 and bank==false and uses==false and reagent==false and account==false)
          calls=calls+1; return 2
        end
        if apiProfile=='modern' then C_Item={GetItemCount=count} else GetItemCount=count end
        addon.ShoppingList:Open(42)
        assert(calls==1 and addon.ShoppingList.entries[1].owned==2)
        calls=0
        for i=1,20 do dispatch('BAG_UPDATE',0) end
        if C_Timer then assert(calls==0); flushTimers(); assert(calls==1) else assert(calls==20) end
    """,
    'shopping_missing_recipe_materials_and_inventory_api': """
        CraftRosterDB.recipes[42]={name='Synced Potion'}
        addon.ShoppingList:Open(42)
        assert(#addon.ShoppingList.entries==0 and addon.ShoppingList.frame.Message:IsShown())
        CraftRosterDB.recipes[42].materials={{name='Herb',itemID=7,count=3}}
        addon.ShoppingList:Refresh()
        assert(addon.ShoppingList.entries[1].owned==nil)
        assert(addon.ShoppingList.frame.Summary:GetText()=='Inventory counts unavailable')
        GetItemCount=function() error('unsupported item query') end
        addon.ShoppingList:Refresh(); assert(addon.ShoppingList.entries[1].owned==nil)
    """,
    'shopping_aggregates_materials_and_stays_pinned': """
        inventoryFixture(false,true)
        CraftRosterDB.recipes[42].materials={{name='Herb',itemID=7,count=2},{name='Herb',itemID=7,count=3}}
        addon.ShoppingList:Open(42)
        assert(#addon.ShoppingList.entries==1 and addon.ShoppingList.entries[1].required==5)
        CraftRosterDB.recipes[43]={name='Other',materials={{name='Other',count=1}}}
        addon.Directory.selectedRecipe={id=43}
        addon.ShoppingList:Refresh()
        assert(addon.ShoppingList.frame.Recipe:GetText()=='Potion · 1 craft')
        CraftRosterDB.recipes[42].materials={{name='Herb',itemID=7,count=30}}
        addon.ShoppingList:ScheduleRefresh(); flushTimers()
        assert(addon.ShoppingList.entries[1].required==30)
    """,
    'shopping_many_materials_use_bounded_visible_rows': """
        local materials={}
        for id=1,100 do materials[id]={name='Material '..id,itemID=id,count=1} end
        CraftRosterDB.recipes[42]={name='Large recipe',materials=materials}
        GetItemCount=function() return 0 end
        addon.ShoppingList:Open(42)
        assert(#addon.ShoppingList.frame.Rows<=20)
        local scroll=addon.ShoppingList.frame.Scroll
        scroll:SetVerticalScroll(99*40); scroll.scripts.OnVerticalScroll()
        local found=false
        for _,row in ipairs(addon.ShoppingList.frame.Rows) do if row:IsShown() and row:GetText():find('Material 100') then found=true end end
        assert(found)
        assert(#addon.ShoppingList.frame.Rows<=20)
    """,
})

CASES.update({
    'whisper_draft_targets_crafter_and_lists_materials': """
        inventoryFixture(false,true)
        function ChatFrame_OpenChat(text,frame) local target,body=text:match('^/w (%S+) (.*)$'); draft={text=body,kind='WHISPER',target=target} end
        function SendChatMessage() error('must not send a whisper automatically') end
        if C_ChatInfo then C_ChatInfo.SendChatMessage=SendChatMessage end
        addon.Requests:WhisperPlayer(42,'Crafter-Realm')
        assert(draft.kind=='WHISPER' and draft.target=='Crafter-Realm')
        assert(draft.text:find('Could you craft Potion?',1,true) and draft.text:find('3x |cffffffff|Hitem:7:',1,true))
    """,
    'long_materials_split_into_bounded_whisper_drafts': """
        local materials={}
        for i=1,16 do materials[i]={name=string.rep('LongMaterial',6)..i,count=i} end
        CraftRosterDB.recipes[42]={name='Potion',materials=materials}
        local texts={}
        function ChatFrame_OpenChat(text,frame) assert(#text<=255); local target,body=text:match('^/w (%S+) (.*)$'); assert(target=='Crafter-Realm'); table.insert(texts,body) end
        addon.Requests:WhisperPlayer(42,'Crafter-Realm')
        while #addon.Requests.whisperDrafts>0 do SlashCmdList.CRAFTROSTERWHISPER() end
        assert(#texts>1)
        local all=table.concat(texts,' ')
        for _,material in ipairs(materials) do assert(all:find(material.name,1,true)) end
    """,
    'mail_fields_fill_without_materials_or_inventory_apis': """
        CraftRosterDB.recipes[42]={name='Runecloth Bag'}
        SendMailNameEditBox=CreateFrame(); SendMailSubjectEditBox=CreateFrame()
        addon.Requests:MailPlayer(42,'Thimble-Moon Guard')
        dispatch('MAIL_SHOW')
        assert(SendMailNameEditBox:GetText()=='Thimble-MoonGuard')
        assert(SendMailSubjectEditBox:GetText()=='Runecloth Bag craft requested')
    """,
    'mail_fields_fill_immediately_when_mailbox_open': """
        inventoryFixture(false,true)
        MailFrame=CreateFrame(); MailFrame:Show()
        SendMailNameEditBox=CreateFrame(); SendMailSubjectEditBox=CreateFrame()
        SendMailNameEditBox:SetText('Previous-Realm')
        addon.Requests:MailPlayer(42,'Crafter-Realm')
        assert(SendMailNameEditBox:GetText()=='Crafter-Realm')
        assert(SendMailSubjectEditBox:GetText()=='Potion craft requested' and moved==3)
    """,
    'selected_crafter_buttons_need_no_target_typing': """
        inventoryFixture(false,true)
        CraftRosterDB.characters['Crafter-Realm']={recipes={[42]={}}}
        SlashCmdList.CRAFTROSTER('')
        for _,entry in ipairs(addon.Directory.professionCache.entries) do if entry.id==42 then addon.Directory.selectedRecipe=entry.recipe end end
        addon.Directory:RefreshCrafters()
        local child=addon.Directory.frame.ProfessionsTab.CrafterListChild
        for _,row in ipairs(frames) do
          if row.parent==child and row:IsShown() and row.tooltipLines and row.tooltipLines[1]=='Crafter-Realm' then row.scripts.OnMouseUp(row,'LeftButton'); break end
        end
        assert(addon.Directory.selectedCrafter=='Crafter-Realm' and not CraftRosterDB.requests)
        function StaticPopup_Show() error('selected crafter should bypass target dialog') end
        function ChatFrame_OpenChat(text,frame) assert(text:find('/w Crafter-Realm ',1,true)==1); whisperOpened=true end
        local tab=addon.Directory.frame.ProfessionsTab
        tab.CraftRosterTradeButton.scripts.OnClick()
        addon.WhisperComposer.frame.Send.scripts.OnClick()
        assert(whisperOpened)
        tab.CraftRosterMailButton.scripts.OnClick()
        SendMailNameEditBox=CreateFrame(); SendMailSubjectEditBox=CreateFrame()
        dispatch('MAIL_SHOW')
        assert(SendMailNameEditBox:GetText()=='Crafter-Realm')
    """,
    'mail_destination_still_fills_with_occupied_cursor': """
        inventoryFixture(false,true); cursor=9
        SendMailNameEditBox=CreateFrame(); SendMailSubjectEditBox=CreateFrame()
        addon.Requests:MailPlayer(42,'Crafter-Realm'); dispatch('MAIL_SHOW')
        assert(SendMailNameEditBox:GetText()=='Crafter-Realm' and moved==0 and cursor==9)
    """,
})

CASES.update({
    'cancelled_trade_retries_without_completing_request': """
        inventoryFixture(false,true)
        ERR_TRADE_CANCELLED='Trade cancelled.'
        addon.Requests:StartTradeRequest(42,'Crafter-Realm'); dispatch('TRADE_SHOW')
        assert(moved==3)
        dispatch('UI_ERROR_MESSAGE',1,ERR_TRADE_CANCELLED)
        dispatch('TRADE_CLOSED')
        assert(CraftRosterDB.requests[1].materialStatus=='cancelled' and CraftRosterDB.requests[1].status=='requested')
        -- Simulate the server returning offered materials after cancellation.
        attachments={}; inventory[1].count=20; moved=0
        dispatch('TRADE_SHOW')
        assert(moved==3 and CraftRosterDB.requests[1].status=='requested')
    """,
    'trade_close_alone_unconfirmed_late_success_disarms': """
        inventoryFixture(false,true); ERR_TRADE_COMPLETE='Trade complete.'
        addon.Requests:StartTradeRequest(42,'Crafter-Realm'); dispatch('TRADE_SHOW'); dispatch('TRADE_CLOSED')
        assert(CraftRosterDB.requests[1].materialStatus=='trade_closed_unconfirmed')
        dispatch('UI_INFO_MESSAGE',1,ERR_TRADE_COMPLETE)
        assert(CraftRosterDB.requests[1].materialStatus=='trade_succeeded' and CraftRosterDB.requests[1].status=='requested')
        attachments={}; moved=0; dispatch('TRADE_SHOW'); assert(moved==0)
    """,
    'partial_inventory_trade_never_confirms_or_completes': """
        inventoryFixture(false,true); inventory[1].count=1; inventory[2].count=0
        addon.Requests:StartTradeRequest(42,'Crafter-Realm'); dispatch('TRADE_SHOW')
        assert(moved==1 and CraftRosterDB.requests[1].autoFillPartial==true)
        assert(CraftRosterDB.requests[1].status=='requested')
        ERR_TRADE_COMPLETE='Trade complete.'; dispatch('UI_INFO_MESSAGE',ERR_TRADE_COMPLETE)
        assert(CraftRosterDB.requests[1].materialStatus=='trade_succeeded' and CraftRosterDB.requests[1].status=='requested')
    """,
    'crafter_share_reduces_shopping_trade_mail_and_whisper': """
        inventoryFixture(false,true)
        addon.Directory.selectedRecipe={id=42,crafters={'Crafter-Realm'}}; addon.Directory.selectedCrafter='Crafter-Realm'
        addon.ShoppingList:Open(42)
        assert(addon.ShoppingList:SetCrafterShare(42,'Crafter-Realm',7,2))
        flushTimers()
        assert(addon.ShoppingList.entries[1].required==1 and addon.ShoppingList.entries[1].crafterProvides==2)
        function ChatFrame_OpenChat(text) draft=text end
        addon.Requests:WhisperPlayer(42,'Crafter-Realm'); dispatch('TRADE_SHOW')
        assert(moved==1 and draft:find('I bring 1; crafter provides 2',1,true))
        ERR_TRADE_CANCELLED='Trade cancelled.'
        dispatch('UI_ERROR_MESSAGE',ERR_TRADE_CANCELLED); dispatch('TRADE_CLOSED')
        addon.Requests:Cancel(); attachments={}; moved=0
        addon.Requests:MailPlayer(42,'Crafter-Realm'); dispatch('MAIL_SHOW'); assert(moved==1)
        assert(addon.ShoppingList:GetPlayerMaterials(42,'Other-Realm')[1].count==3)
        assert(not addon.ShoppingList:SetCrafterShare(42,'Crafter-Realm',7,4))
        assert(not addon.ShoppingList:SetCrafterShare(42,'Crafter-Realm',7,-1))
    """,
    'crafter_all_materials_requires_no_item_transfer': """
        inventoryFixture(false,true)
        assert(addon.ShoppingList:SetCrafterShare(42,'Crafter-Realm',7,3))
        function ChatFrame_OpenChat(text) draft=text end
        addon.Requests:WhisperPlayer(42,'Crafter-Realm'); dispatch('TRADE_SHOW')
        assert(moved==0 and draft:find('crafter provides 3',1,true))
        assert(CraftRosterDB.requests[1].status=='requested')
    """,
    'shopping_recounts_after_cancelled_trade_return': """
        inventoryFixture(false,true); addon.ShoppingList:Open(42)
        addon.Requests:StartTradeRequest(42,'Crafter-Realm'); dispatch('TRADE_SHOW'); dispatch('TRADE_CLOSED')
        inventory[1].count=20; attachments={}
        dispatch('BAG_UPDATE',0); flushTimers()
        assert(addon.ShoppingList.entries[1].owned==24)
    """,
})

CASES.update({
    'error_handler_captures_and_preserves_original_arguments': """
        function debugstack() return 'Interface/AddOns/CraftRoster/Recipes.lua:42: in function Scan' end
        local message='Interface/AddOns/CraftRoster/Recipes.lua:42: sample failure'
        assert(geterrorhandler()(message,'context')=='forwarded')
        assert(originalErrors[1][1]==message and originalErrors[1][2]=='context')
        assert(#CraftRosterDB.errorReports==1 and CraftRosterDB.errorReports[1].stack:find('Recipes.lua',1,true))
    """,
    'unrelated_and_nonstring_errors_do_not_break_handler': """
        function debugstack() return 'Interface/AddOns/CraftRoster/ErrorReporter.lua:99: wrapper' end
        geterrorhandler()('Interface/AddOns/OtherAddon/Main.lua:5: failed')
        assert(#CraftRosterDB.errorReports==0 and #originalErrors==1)
        local value=setmetatable({}, {__tostring=function() error('cannot stringify') end})
        assert(geterrorhandler()(value)=='forwarded')
        assert(originalErrors[2][1]==value and #CraftRosterDB.errorReports==0)
    """,
    'error_storm_deduplicates_and_limits_notifications': """
        local notices,stacks=0,0
        print=function() notices=notices+1 end
        debugstack=function() stacks=stacks+1; return "CraftRoster/Core.lua:7: stack" end
        for i=1,1000 do geterrorhandler()('CraftRoster/Core.lua:7: repeated failure') end
        assert(#CraftRosterDB.errorReports==1 and CraftRosterDB.errorReports[1].count==1000)
        assert(notices==1 and stacks==1)
    """,
    'error_history_and_payload_sizes_bounded': """
        function debugstack() return string.rep('x',10000) end
        for i=1,20 do geterrorhandler()('CraftRoster/Core.lua:'..i..': '..string.rep('x',10000)) end
        assert(#CraftRosterDB.errorReports==10)
        for _,entry in ipairs(CraftRosterDB.errorReports) do assert(#entry.message<=2048 and #entry.stack<=6000) end
    """,
    'bug_report_includes_metadata_and_copyable_error': """
        function GetAddOnMetadata() return '0.8.0-beta.4' end
        function GetBuildInfo() return '1.60.1','70450','today',16001 end
        function debugstack() return 'CraftRoster/Recipes.lua:42: stack' end
        geterrorhandler()('CraftRoster/Recipes.lua:42: sample failure')
        assert(not addon.Panel.frame and not addon.Directory.frame)
        SlashCmdList.CRAFTROSTER('bug')
        local popup=addon.Panel.errorFrame
        assert(popup:IsShown() and popup.ErrorBox.focused and popup.ErrorBox.highlighted)
        local text=popup.ErrorBox:GetText()
        assert(text:find('0.8.0-beta.4',1,true) and text:find('70450',1,true) and text:find('16001',1,true))
        assert(text:find('sample failure',1,true) and text:find('stack',1,true))
        assert(not addon.Directory.frame)
        popup.ErrorBox.scripts.OnEscapePressed(popup.ErrorBox)
        assert(not popup:IsShown() and not popup.ErrorBox.focused)
    """,
    'bug_report_without_errors_is_still_useful': """
        SlashCmdList.CRAFTROSTER('bug')
        assert(addon.Panel.errorFrame.ErrorBox:GetText():find('No CraftRoster Lua errors captured',1,true))
    """,
    'reset_before_first_open_clears_saved_geometry': """
        CraftRosterDB.settings.window={width=1500,height=1000,x=500,y=500}
        SlashCmdList.CRAFTROSTER('reset')
        assert(CraftRosterDB.settings.window==nil and not addon.Directory.frame)
        SlashCmdList.CRAFTROSTER('')
        assert(addon.Directory.frame:GetWidth()==1000)
    """,
    'filtering_scrolled_directory_keeps_matching_row_visible': """
        for id=1,1000 do
          CraftRosterDB.recipes[id]={name=('Potion %04d'):format(id)}
          CraftRosterDB.characters['Tester-Realm'].recipes[id]={}
        end
        SlashCmdList.CRAFTROSTER('')
        local tab=addon.Directory.frame.ProfessionsTab
        tab.Results:SetVerticalScroll(30000)
        tab.SearchBox:SetText('Potion 0001'); addon.Directory:RefreshProfessions()
        assert(tab.Results:GetVerticalScroll()==0)
        local found=false
        for _,row in ipairs(frames) do
          if row.parent==tab.ResultsChild and row:IsShown() and row.Label and row.Label:GetText()=='Potion 0001' then found=true end
        end
        assert(found)
    """,
    'shrinking_scrolled_shopping_list_remains_visible': """
        local materials={}
        for i=1,100 do materials[i]={name='Material '..i,count=1} end
        CraftRosterDB.recipes[42]={name='Potion',materials=materials}
        addon.ShoppingList:Open(42); addon.ShoppingList.frame.Scroll:SetVerticalScroll(2000)
        CraftRosterDB.recipes[42].materials={{name='Herb',count=1}}
        addon.ShoppingList:Refresh()
        assert(addon.ShoppingList.frame.Scroll:GetVerticalScroll()==0)
        assert(addon.ShoppingList.frame.Rows[1]:GetText():find('Herb',1,true))
    """,
    'native_whisper_api_addresses_edit_box_without_sending': """
        inventoryFixture(false,true)
        local edit=CreateFrame(); local attributes={}
        edit.SetAttribute=function(self,key,value) attributes[key]=value end
        function ChatFrame_SendTell(target) assert(target=='Crafter-Realm') end
        function ChatEdit_ChooseBoxForSend() return edit end
        function ChatFrame_OpenChat() error('native whisper route should be used') end
        function SendChatMessage() error('must not send automatically') end
        addon.Requests:WhisperPlayer(42,'Crafter-Realm')
        assert(attributes.chatType=='WHISPER' and attributes.tellTarget=='Crafter-Realm')
        assert(edit:GetText():find('3x |cffffffff|Hitem:7:',1,true) and edit.focused)
    """,
    'explicit_addon_send_failures_are_not_reported_as_delivered': """
        Enum={SendAddonMessageResult={Success=0,Failure=1}}
        C_ChatInfo={SendAddonMessage=function() return 1 end}
        addon.GuildSync:SendData(); assert(#sent==0)
        C_ChatInfo.SendAddonMessage=function(p,m,c) table.insert(sent,{p,m,c}); return 0 end
        addon.GuildSync:SendData(); assert(#sent==1)
        C_ChatInfo.SendAddonMessage=function() return 1 end
        local messages={}; print=function(message) table.insert(messages,message) end
        CraftRosterDB.requests={{id='test',recipe='Potion',target='Crafter-Realm',status='requested'}}
        SlashCmdList.CRAFTROSTERSTATUS('test accepted')
        assert(messages[#messages]:find('saved locally; sync unavailable',1,true))
    """,
})

CASES.update({
    'manual_refresh_requests_peers_and_announces_own_snapshot': """
        addon.GuildSync:SyncNow()
        if C_ChatInfo or SendAddonMessage then
          assert(#sent==2 and sent[1][2]=='REQ' and sent[2][2]:find('DATA:Tester%-Realm:'))
        else assert(#sent==0) end
    """,
    'interrupted_chunk_send_is_visible_and_can_retry': """
        if not C_Timer then return end
        for id=1,200 do CraftRosterDB.characters['Tester-Realm'].recipes[id]={} end
        Enum={SendAddonMessageResult={Success=0,Failure=1}}
        local calls, warnings=0,0
        C_ChatInfo={SendAddonMessage=function() calls=calls+1; return calls==1 and 0 or 1 end}
        print=function(text) if text:find('guild sync interrupted',1,true) then warnings=warnings+1 end end
        addon.GuildSync:SendData(); flushTimers(); assert(warnings==1 and calls==2)
        clock=clock+31
        C_ChatInfo.SendAddonMessage=function(p,m,c) table.insert(sent,{p,m,c}); return 0 end
        addon.GuildSync:SyncNow(); flushTimers()
        assert(#sent>2)
    """,
})

CASES.update({
    'roster_errors_fall_back_without_breaking_directory': """
        C_GuildInfo={GetGuildRoster=function() error('unsupported roster API') end,
          GuildRoster=function() error('roster unavailable') end}
        function GetNumGuildMembers() return 2 end
        function GetGuildRosterInfo(index)
          if index==1 then error('member unavailable') end
          return 'Bob-Realm',nil,nil,nil,nil,nil,nil,nil,true
        end
        CraftRosterDB.characters['Bob-Realm']={recipes={[42]={}}}
        CraftRosterDB.recipes[42]={name='Potion',profession='Alchemy'}
        SlashCmdList.CRAFTROSTER('')
        for _,entry in ipairs(addon.Directory.professionCache.entries) do if entry.id==42 then addon.Directory.selectedRecipe=entry.recipe end end
        dispatch('PLAYER_ENTERING_WORLD'); dispatch('GUILD_ROSTER_UPDATE')
        local found=false
        for _,row in ipairs(frames) do
          if row.parent==addon.Directory.frame.ProfessionsTab.CrafterListChild and row:IsShown()
            and row.tooltipLines and row.tooltipLines[1]=='Bob-Realm' then found=true end
        end
        assert(found)
    """,
    'crafter_tooltip_preserves_profession_skill_and_recipe': """
        CraftRosterDB.settings.onlineOnly=false
        CraftRosterDB.characters['Crafter-Realm']={recipes={[42]={}},professions={Alchemy={skill=100,max=150}}}
        CraftRosterDB.recipes[42]={name='Potion',profession='Alchemy'}
        SlashCmdList.CRAFTROSTER('')
        for _,entry in ipairs(addon.Directory.professionCache.entries) do if entry.id==42 then addon.Directory.selectedRecipe=entry.recipe end end
        addon.Directory:RefreshCrafters()
        local found=false
        for _,row in ipairs(frames) do
          if row.parent==addon.Directory.frame.ProfessionsTab.CrafterListChild and row:IsShown()
            and row.tooltipLines and row.tooltipLines[1]=='Crafter-Realm' then
            assert(row.tooltipLines[2]=='Alchemy: 100/150' and row.tooltipLines[3]=='Potion')
            row.scripts.OnMouseUp(row,'LeftButton'); found=true; break
          end
        end
        assert(found and addon.Directory.selectedCrafter=='Crafter-Realm')
    """,
    'five_hundred_recipe_sync_is_paced_bounded_and_deduplicated': """
        if not C_Timer or not (C_ChatInfo or SendAddonMessage) then return end
        for id=1,500 do
          CraftRosterDB.characters['Tester-Realm'].recipes[id]={learnedAt=100}
          CraftRosterDB.recipes[id]={name='Potion '..id,profession='Alchemy'}
        end
        addon.GuildSync:SendData(); assert(#sent==1)
        flushTimers(); local count=#sent; assert(count>1)
        for _,message in ipairs(sent) do assert(#message[2]<=255) end
        clock=clock+31; addon.GuildSync:SendData(); assert(#sent==count)
        for i=count,1,-1 do
          local message=sent[i][2]:gsub('Tester%-Realm','Helper-Realm')
          dispatch('CHAT_MSG_ADDON','CRAFTROSTER',message,'GUILD','Helper-Realm')
        end
        assert(CraftRosterDB.characters['Helper-Realm'].recipes[500])
        assert(CraftRosterDB.recipes[500].name=='Potion 500')
    """,
})

CASES.update({
    'mail_body_and_edits_survive_repeated_mail_events': """
        inventoryFixture(false,true)
        SendMailNameEditBox=CreateFrame(); SendMailSubjectEditBox=CreateFrame(); SendMailBodyEditBox=CreateFrame()
        addon.Requests:MailPlayer(42,'Crafter-Realm'); dispatch('MAIL_SHOW')
        local body=SendMailBodyEditBox:GetText()
        assert(body:find('Requested item: Potion',1,true))
        assert(body:find('3 x Herb',1,true))
        SendMailSubjectEditBox:SetText('My edited title'); SendMailBodyEditBox:SetText('My edited body')
        dispatch('MAIL_SHOW')
        assert(SendMailSubjectEditBox:GetText()=='My edited title' and SendMailBodyEditBox:GetText()=='My edited body')
    """,
    'shopping_click_fills_auction_and_right_click_edits_share': """
        inventoryFixture(false,true)
        addon.Directory.selectedRecipe={id=42}; addon.Directory.selectedCrafter='Crafter-Realm'
        addon.ShoppingList:Open(42)
        local row=addon.ShoppingList.frame.Rows[1]
        assert(not addon.ShoppingList:SearchAuctions(row.entry))
        AuctionFrame=CreateFrame(); AuctionFrame:Show(); BrowseName=CreateFrame()
        row.scripts.OnClick(row,'LeftButton')
        assert(BrowseName:GetText()==row.entry.name)
        local dialog
        StaticPopup_Show=function(which) dialog=which end
        row.scripts.OnClick(row,'RightButton')
        assert(dialog=='CRAFTROSTER_CRAFTER_SHARE')
    """,
})

CASES.update({
    'whispers_link_output_and_materials_without_splitting_links': """
        inventoryFixture(false,true)
        CraftRosterDB.recipes[42].itemLink='|cff1eff00|Hitem:123:0:0:0:0:0:0:0|h[Potion]|h|r'
        local drafts={}
        function ChatFrame_OpenChat(text) table.insert(drafts,text) end
        addon.Requests:PrepareWhisper(42,'Crafter-Realm')
        while #addon.Requests.whisperDrafts>0 do addon.Requests:NextWhisper() end
        local joined=table.concat(drafts,' ')
        assert(joined:find(CraftRosterDB.recipes[42].itemLink,1,true))
        assert(joined:find('|Hitem:7:',1,true) and joined:find('|h[Herb]|h|r',1,true))
        for _,text in ipairs(drafts) do
          assert(#text<=255)
          local _,opens=text:gsub('|Hitem:','')
          local _,closes=text:gsub('|h|r','')
          assert(opens==closes)
        end
    """,
})

CASES.update({
    'quantity_scales_shopping_whispers_mail_and_freezes_prepared_request': """
        inventoryFixture(false,true)
        assert(addon.ShoppingList:GetQuantity(42)==1)
        assert(addon.ShoppingList:SetQuantity(42,3))
        assert(not addon.ShoppingList:SetQuantity(42,0))
        assert(not addon.ShoppingList:SetQuantity(42,1.5))
        assert(not addon.ShoppingList:SetQuantity(42,1000))
        addon.ShoppingList:Open(42)
        assert(addon.ShoppingList.entries[1].required==9)
        assert(CraftRosterDB.recipes[42].materials[1].count==3)
        assert(addon.ShoppingList:SetCrafterShare(42,'Crafter-Realm',7,2))
        assert(addon.ShoppingList:GetPlayerMaterials(42,'Crafter-Realm')[1].count==7)
        local drafts={}
        function ChatFrame_OpenChat(text) table.insert(drafts,text) end
        addon.Requests:WhisperPlayer(42,'Crafter-Realm')
        while #addon.Requests.whisperDrafts>0 do addon.Requests:NextWhisper() end
        local text=table.concat(drafts,' ')
        assert(text:find('3 crafts of Potion',1,true) and text:find('9x ',1,true))
        assert(text:find('I bring 7; crafter provides 2',1,true))
        addon.Requests:Cancel()
        SendMailNameEditBox=CreateFrame(); SendMailSubjectEditBox=CreateFrame(); SendMailBodyEditBox=CreateFrame()
        addon.Requests:MailPlayer(42,'Crafter-Realm')
        assert(addon.ShoppingList:SetQuantity(42,5))
        dispatch('MAIL_SHOW')
        assert(SendMailSubjectEditBox:GetText()=='3 crafts of Potion craft requested')
        local body=SendMailBodyEditBox:GetText()
        assert(body:find('Number of crafts: 3',1,true) and body:find('9 x Herb',1,true))
        assert(CraftRosterDB.requests[1].quantity==3)
    """,
    'quantity_control_saves_and_restores_per_recipe': """
        inventoryFixture(false,true)
        addon.Directory:Toggle()
        addon.Directory.selectedRecipe={id=42,name='Potion',profession='Alchemy',crafters={}}
        addon.Directory:RefreshDetails()
        local field=addon.Directory.frame.ProfessionsTab.CraftRosterQuantity
        assert(field:GetText()=='1')
        field:SetText('4'); field.scripts.OnTextChanged(field,true)
        assert(addon.ShoppingList:GetQuantity(42)==4)
        field:SetText('0'); field.scripts.OnEditFocusLost(field)
        assert(field:GetText()=='4')
        CraftRosterDB.recipes[43]={name='Other'}
        assert(addon.ShoppingList:GetQuantity(43)==1)
        addon.Directory:RefreshDetails(); assert(field:GetText()=='4')
    """,
})

CASES.update({
    'auto_load_off_blocks_trade_and_mail_items_but_keeps_drafts': """
        inventoryFixture(false,true)
        local draft
        function ChatFrame_OpenChat(text) draft=text end
        addon.Requests:WhisperPlayer(42,'Crafter-Realm')
        addon.Requests:SetAutoLoadItems(false)
        dispatch('TRADE_SHOW'); assert(moved==0 and draft:find('Potion',1,true))
        ERR_TRADE_CANCELLED='Trade cancelled.'
        dispatch('UI_ERROR_MESSAGE',ERR_TRADE_CANCELLED); dispatch('TRADE_CLOSED')
        SendMailNameEditBox=CreateFrame(); SendMailSubjectEditBox=CreateFrame(); SendMailBodyEditBox=CreateFrame()
        addon.Requests:MailPlayer(42,'Crafter-Realm'); dispatch('MAIL_SHOW')
        assert(moved==0 and SendMailNameEditBox:GetText()=='Crafter-Realm')
        assert(SendMailBodyEditBox:GetText():find('3 x Herb',1,true))
        addon.Requests:SetAutoLoadItems(true); dispatch('MAIL_SHOW'); assert(moved==3)
    """,
    'auto_load_checkbox_saves_setting_and_remains_compact': """
        addon.Requests:SetAutoLoadItems(false)
        addon.Directory:Toggle()
        local box=addon.Directory.frame.ProfessionsTab.CraftRosterAutoLoad
        local checked
        box.SetChecked=function(self,value) checked=value end
        box.GetChecked=function() return checked end
        checked=true; box.scripts.OnClick(box)
        assert(CraftRosterDB.settings.autoLoadItems==true and checked==true)
        checked=false; box.scripts.OnClick(box)
        assert(CraftRosterDB.settings.autoLoadItems==false and checked==false)
    """,
})

CASES.update({
    'quantity_arrows_step_typed_values_and_clamp_to_valid_range': """
        inventoryFixture(false,true)
        addon.Directory:Toggle()
        addon.Directory.selectedRecipe={id=42,name='Potion',profession='Alchemy',crafters={}}
        addon.Directory:RefreshDetails()
        local tab=addon.Directory.frame.ProfessionsTab
        local field=tab.CraftRosterQuantity
        local function up() tab.CraftRosterQuantityUp.scripts.OnClick() end
        local function down() tab.CraftRosterQuantityDown.scripts.OnClick() end
        down(); assert(field:GetText()=='1' and addon.ShoppingList:GetQuantity(42)==1)
        up(); assert(field:GetText()=='2' and addon.ShoppingList:GetQuantity(42)==2)
        field:SetText('15'); up()
        assert(field:GetText()=='16' and addon.ShoppingList:GetQuantity(42)==16)
        down(); assert(field:GetText()=='15')
        field:SetText('999'); up(); assert(field:GetText()=='999')
        field:SetText(''); down(); assert(field:GetText()=='998')
        addon.ShoppingList:Open(42); assert(addon.ShoppingList.entries[1].required==2994)
        addon.Directory.selectedRecipe=nil
        up(); assert(field:GetText()=='998')
    """,
})

CASES.update({
    'multiple_trades_credit_only_actual_confirmed_materials': """
        inventoryFixture(false,true)
        CraftRosterDB.recipes[42].materials[1].count=30
        ERR_TRADE_COMPLETE='Trade complete.'
        addon.Requests:StartTradeRequest(42,'Crafter-Realm')
        dispatch('TRADE_SHOW'); assert(moved==24)
        dispatch('TRADE_SHOW'); assert(moved==24)
        local id=CraftRosterDB.requests[1].id
        assert(addon.Requests:GetTradeProgress(id).remaining==30)
        dispatch('TRADE_ACCEPT_UPDATE',1,1)
        dispatch('TRADE_CLOSED'); dispatch('UI_INFO_MESSAGE',ERR_TRADE_COMPLETE)
        local progress=addon.Requests:GetTradeProgress(id)
        assert(progress.remaining==6 and progress.delivered==24 and not progress.needsReview)
        dispatch('UI_INFO_MESSAGE',ERR_TRADE_COMPLETE)
        assert(addon.Requests:GetTradeProgress(id).delivered==24)
        attachments={}; inventory[1].count=20; inventory[2].count=0; moved=0
        dispatch('TRADE_SHOW'); assert(moved==6)
        dispatch('UI_INFO_MESSAGE',ERR_TRADE_COMPLETE); dispatch('TRADE_CLOSED')
        assert(addon.Requests:GetTradeProgress(id).remaining==0)
        attachments={}; moved=0; dispatch('TRADE_SHOW'); assert(moved==0)
    """,
    'trade_credit_tracks_manual_removal_and_replacement': """
        inventoryFixture(false,true); ERR_TRADE_COMPLETE='Trade complete.'
        addon.Requests:StartTradeRequest(42,'Crafter-Realm'); dispatch('TRADE_SHOW')
        attachments[1]=1
        dispatch('TRADE_PLAYER_ITEM_CHANGED',1); dispatch('TRADE_ACCEPT_UPDATE',1,1)
        dispatch('UI_INFO_MESSAGE',ERR_TRADE_COMPLETE); dispatch('TRADE_CLOSED')
        local p=addon.Requests:GetTradeProgress(CraftRosterDB.requests[1].id)
        assert(p.delivered==1 and p.remaining==2)
        attachments={}; inventory[1].count=20; moved=0
        dispatch('TRADE_SHOW'); assert(moved==2)
    """,
    'bag_full_error_and_cancel_preserve_all_requirements': """
        inventoryFixture(false,true); ERR_TRADE_CANCELLED='Trade cancelled.'
        addon.Requests:StartTradeRequest(42,'Crafter-Realm'); dispatch('TRADE_SHOW')
        local id=CraftRosterDB.requests[1].id
        dispatch('UI_ERROR_MESSAGE',99,'Target inventory is full.')
        assert(addon.Requests:GetTradeProgress(id).delivered==0)
        dispatch('UI_ERROR_MESSAGE',ERR_TRADE_CANCELLED); dispatch('TRADE_CLOSED')
        attachments={}; inventory[1].count=20; moved=0
        dispatch('TRADE_SHOW'); assert(moved==3)
        assert(addon.Requests:GetTradeProgress(id).remaining==3)
    """,
    'unconfirmed_closed_trade_blocks_replay_until_review': """
        inventoryFixture(false,true)
        addon.Requests:StartTradeRequest(42,'Crafter-Realm'); dispatch('TRADE_SHOW'); dispatch('TRADE_CLOSED')
        local id=CraftRosterDB.requests[1].id
        attachments={}; inventory[1].count=20; moved=0
        dispatch('TRADE_SHOW'); assert(moved==0 and addon.Requests:GetTradeProgress(id).needsReview)
        addon.Requests:StartTradeRequest(42,'Crafter-Realm'); assert(#CraftRosterDB.requests==1)
        StaticPopupDialogs.CRAFTROSTER_TRADE_REVIEW.OnAccept({data=id})
        addon.Requests:StartTradeRequest(42,'Crafter-Realm'); dispatch('TRADE_SHOW')
        assert(moved==3 and #CraftRosterDB.requests==1)
    """,
    'unverifiable_trade_is_paused_and_never_credited': """
        inventoryFixture(false,true); ERR_TRADE_COMPLETE='Trade complete.'
        GetTradePlayerItemLink=nil
        addon.Requests:StartTradeRequest(42,'Crafter-Realm'); dispatch('TRADE_SHOW')
        local id=CraftRosterDB.requests[1].id
        dispatch('UI_INFO_MESSAGE',ERR_TRADE_COMPLETE); dispatch('TRADE_CLOSED')
        local p=addon.Requests:GetTradeProgress(id)
        assert(p.delivered==0 and p.remaining==3 and p.needsReview)
        attachments={}; moved=0; dispatch('TRADE_SHOW'); assert(moved==0)
    """,
    'wrong_partner_and_delayed_success_do_not_advance_ledger': """
        inventoryFixture(false,true); ERR_TRADE_COMPLETE='Trade complete.'
        addon.Requests:StartTradeRequest(42,'Other-Realm'); dispatch('TRADE_SHOW')
        assert(moved==0)
        addon.Requests:Cancel()
        addon.Requests:StartTradeRequest(42,'Crafter-Realm'); dispatch('TRADE_SHOW'); dispatch('TRADE_CLOSED')
        clock=clock+3; dispatch('UI_INFO_MESSAGE',ERR_TRADE_COMPLETE)
        local p=addon.Requests:GetTradeProgress(CraftRosterDB.requests[1].id)
        assert(p.delivered==0 and p.needsReview)
    """,
})

CASES.update({
    'seven_material_types_continue_after_six_slot_trade': """
        local bags,offers,hand={}, {},nil
        local materials={}
        for i=1,7 do bags[i]=1; materials[i]={name='Mat '..i,itemID=100+i,count=1} end
        CraftRosterDB.recipes[42]={name='Large craft',materials=materials}
        local function slots(bag) return bag==0 and 7 or 0 end
        local function link(bag,slot) return bags[slot]>0 and ('|Hitem:'..(100+slot)..'|h[Mat '..slot..']|h') end
        local function pickup(bag,slot) hand=slot; bags[slot]=0 end
        function CursorHasItem() return hand~=nil end
        function ClickTradeButton(slot) assert(not offers[slot]); offers[slot]=hand; hand=nil end
        function GetTradePlayerItemInfo(slot) return offers[slot] and ('Mat '..offers[slot]),'icon',offers[slot] and 1 end
        function GetTradePlayerItemLink(slot) return offers[slot] and ('|Hitem:'..(100+offers[slot])..'|h[Mat '..offers[slot]..']|h') end
        if C_Container then
          C_Container.GetContainerNumSlots=slots; C_Container.GetContainerItemLink=link; C_Container.PickupContainerItem=pickup
          C_Container.GetContainerItemInfo=function(bag,slot) return {stackCount=bags[slot],isLocked=false} end
        else
          GetContainerNumSlots=slots; GetContainerItemLink=link; PickupContainerItem=pickup
          GetContainerItemInfo=function(bag,slot) return 'icon',bags[slot],false end
        end
        ERR_TRADE_COMPLETE='Trade complete.'
        addon.Requests:StartTradeRequest(42,'Crafter-Realm'); dispatch('TRADE_SHOW')
        assert(#offers==6 and bags[7]==1)
        local id=CraftRosterDB.requests[1].id
        dispatch('UI_INFO_MESSAGE',ERR_TRADE_COMPLETE); dispatch('TRADE_CLOSED')
        assert(addon.Requests:GetTradeProgress(id).remaining==1)
        offers={}; dispatch('TRADE_SHOW'); assert(#offers==1 and offers[1]==7)
        dispatch('UI_INFO_MESSAGE',ERR_TRADE_COMPLETE); dispatch('TRADE_CLOSED')
        assert(addon.Requests:GetTradeProgress(id).delivered==7)
    """,
    'delivery_ledger_resumes_without_in_memory_request_and_pauses_uncertainty': """
        inventoryFixture(false,true)
        CraftRosterDB.recipes[42].materials[1].count=30
        ERR_TRADE_COMPLETE='Trade complete.'
        addon.Requests:StartTradeRequest(42,'Crafter-Realm'); dispatch('TRADE_SHOW')
        dispatch('UI_INFO_MESSAGE',ERR_TRADE_COMPLETE); dispatch('TRADE_CLOSED')
        local id=CraftRosterDB.requests[1].id
        addon.Requests:Cancel()
        attachments={}; inventory[1].count=20; inventory[2].count=0; moved=0
        addon.Requests:StartTradeRequest(42,'Crafter-Realm'); dispatch('TRADE_SHOW')
        assert(moved==6 and #CraftRosterDB.requests==1)
        dispatch('TRADE_CLOSED'); addon.Requests:Cancel()
        attachments={}; inventory[1].count=20; moved=0
        addon.Requests:StartTradeRequest(42,'Crafter-Realm'); dispatch('TRADE_SHOW')
        assert(moved==0 and addon.Requests:GetTradeProgress(id).needsReview)
    """,
})

class AddonTests(unittest.TestCase):
    pass

for runtime in ('lua51', 'luajit21'):
    for profile in ('modern', 'legacy', 'minimal'):
        for name, code in CASES.items():
            def test(self, runtime=runtime, profile=profile, code=code, case=name):
                if (case == "sync_large_payload_roundtrip" and profile == "minimal") or (case == "restricted_sync_retry" and profile != "modern") or (case == "unchanged_sync_reuses_serialized_payload" and profile == "minimal") or (case == "interrupted_chunk_send_is_visible_and_can_retry" and profile == "minimal"):
                    self.skipTest("API deliberately absent in this profile")
                lua = importlib.import_module('lupa.' + runtime).LuaRuntime(unpack_returned_tuples=True)
                lua.execute((ROOT/'tests/wow_mock.lua').read_text())
                lua.globals().configure(profile)
                # A partial old settings table should acquire missing defaults.
                lua.execute('CraftRosterDB={settings={onlineOnly=false}}')
                addon = lua.table(); lua.globals().addon = addon
                for name in (ROOT/'CraftRoster.toc').read_text().splitlines():
                    if name.endswith('.lua'):
                        lua.compile((ROOT/name).read_text(), name=name)('CraftRoster', addon)
                lua.execute("dispatch('ADDON_LOADED','CraftRoster')")
                lua.execute(code)
            setattr(AddonTests, f'test_{runtime}_{profile}_{name}', test)

class PeerTests(unittest.TestCase):
    def test_cross_profile_sync_and_request_roundtrip(self):
        for runtime in ('lua51', 'luajit21'):
            for sender_profile, receiver_profile in (('modern', 'legacy'), ('legacy', 'modern')):
                with self.subTest(runtime=runtime, sender=sender_profile, receiver=receiver_profile):
                    def peer(profile, player):
                        lua = importlib.import_module('lupa.' + runtime).LuaRuntime(unpack_returned_tuples=True)
                        lua.execute((ROOT/'tests/wow_mock.lua').read_text())
                        lua.globals().configure(profile)
                        lua.globals().player = player
                        lua.execute("function UnitName(unit) return player end")
                        addon = lua.table(); lua.globals().addon = addon
                        for name in (ROOT/'CraftRoster.toc').read_text().splitlines():
                            if name.endswith('.lua'):
                                lua.compile((ROOT/name).read_text(), name=name)('CraftRoster', addon)
                        lua.execute("dispatch('ADDON_LOADED','CraftRoster')")
                        return lua
                    sender, receiver = peer(sender_profile, 'Tester'), peer(receiver_profile, 'Crafter')
                    def deliver(source, destination, character):
                        messages = source.globals().sent
                        for i in range(1, len(messages)+1):
                            msg = messages[i]
                            destination.globals().dispatch('CHAT_MSG_ADDON', msg[1], msg[2], msg[3], character)
                        source.execute('sent={}')
                    sender.execute("""
                        for id=1,200 do
                          CraftRosterDB.characters['Tester-Realm'].recipes[id]={learnedAt=100}
                          CraftRosterDB.recipes[id]={name='Potion '..id,profession='Alchemy'}
                        end
                        CraftRosterDB.recipes[42].materials={{name='Herb',itemID=7,count=3}}
                        addon.GuildSync:SendData(); flushTimers()
                    """)
                    deliver(sender, receiver, 'Tester-Realm')
                    receiver.execute("""
                        assert(CraftRosterDB.characters['Tester-Realm'].recipes[200])
                        assert(CraftRosterDB.recipes[200].name=='Potion 200')
                    """)
                    sender.execute("addon.Requests:StartTradeRequest(42,'Crafter-Realm')")
                    deliver(sender, receiver, 'Tester-Realm')
                    receiver.execute("""
                        assert(#CraftRosterDB.requests==1)
                        SlashCmdList.CRAFTROSTERSTATUS(CraftRosterDB.requests[1].id..' accepted')
                    """)
                    deliver(receiver, sender, 'Crafter-Realm')
                    sender.execute("assert(CraftRosterDB.requests[1].status=='accepted')")

class ShoppingPersistenceTests(unittest.TestCase):
    def test_saved_panel_restores_in_fresh_runtime(self):
        for runtime in ('lua51', 'luajit21'):
            for profile in ('modern', 'legacy', 'minimal'):
                with self.subTest(runtime=runtime, profile=profile):
                    def fresh(saved=None):
                        lua = importlib.import_module('lupa.'+runtime).LuaRuntime(unpack_returned_tuples=True)
                        lua.execute((ROOT/'tests/wow_mock.lua').read_text())
                        lua.globals().configure(profile)
                        if saved:
                            lua.globals().savedShopping = lua.table_from(saved, recursive=True)
                            lua.execute("CraftRosterDB={characters={['Tester-Realm']={shoppingList=savedShopping}},recipes={[42]={name='Potion',materials={{name='Herb',count=3}}}}}")
                        addon=lua.table(); lua.globals().addon=addon
                        for name in (ROOT/'CraftRoster.toc').read_text().splitlines():
                            if name.endswith('.lua'):
                                lua.compile((ROOT/name).read_text(),name=name)('CraftRoster',addon)
                        lua.execute("dispatch('ADDON_LOADED','CraftRoster')")
                        return lua
                    first=fresh()
                    first.execute("""
                        CraftRosterDB.recipes[42]={name='Potion',materials={{name='Herb',count=3}}}
                        addon.ShoppingList:Open(42)
                        addon.ShoppingList:SetCrafterShare(42,'Crafter-Realm','Herb',2)
                        addon.ShoppingList.frame.GetPoint=function() return 'TOPRIGHT',nil,'TOPRIGHT',-24,-36 end
                        addon.ShoppingList.frame.scripts.OnDragStop()
                    """)
                    state=first.globals().CraftRosterDB.characters['Tester-Realm'].shoppingList
                    def plain(value):
                        return {k:plain(v) for k,v in value.items()} if hasattr(value,'items') else value
                    saved={key:plain(state[key]) for key in ('recipeID','visible','point','x','y','crafter','contributions')}
                    second=fresh(saved)
                    second.execute("assert(addon.ShoppingList.frame:IsShown() and not addon.Directory.frame and addon.ShoppingList.entries[1].required==1)")
                    restored=second.globals().CraftRosterDB.characters['Tester-Realm'].shoppingList
                    self.assertEqual((restored.point,restored.x,restored.y),('TOPRIGHT',-24,-36))
                    saved['visible']=False
                    closed=fresh(saved)
                    closed.execute("assert(not addon.ShoppingList.frame)")

class ErrorPersistenceTests(unittest.TestCase):
    def test_startup_errors_merge_with_saved_history_in_fresh_runtime(self):
        for runtime in ('lua51','luajit21'):
            with self.subTest(runtime=runtime):
                lua=importlib.import_module('lupa.'+runtime).LuaRuntime(unpack_returned_tuples=True)
                lua.execute((ROOT/'tests/wow_mock.lua').read_text())
                lua.globals().configure('modern')
                addon=lua.table(); lua.globals().addon=addon
                lua.compile((ROOT/'ErrorReporter.lua').read_text())('CraftRoster',addon)
                lua.execute("geterrorhandler()('CraftRoster/Core.lua:1: startup failure')")
                lua.execute("CraftRosterDB={errorReports={{message='CraftRoster/Recipes.lua:2: saved failure',stack='saved stack',count=3}}}")
                for name in (ROOT/'CraftRoster.toc').read_text().splitlines():
                    if name.endswith('.lua') and name!='ErrorReporter.lua':
                        lua.compile((ROOT/name).read_text(),name=name)('CraftRoster',addon)
                lua.execute("""
                    dispatch('ADDON_LOADED','CraftRoster')
                    assert(#CraftRosterDB.errorReports==2)
                    local report=addon.ErrorReporter:GetReport()
                    assert(report:find('startup failure',1,true) and report:find('saved failure',1,true))
                    assert(report:find('occurrences: 3',1,true))
                """)

class ForeverManifestTests(unittest.TestCase):
    def test_manifest_matches_reported_forever_client(self):
        lines=(ROOT/'CraftRoster.toc').read_text().splitlines()
        metadata=dict(line[3:].split(': ',1) for line in lines if line.startswith('## '))
        self.assertEqual(metadata['Interface'],'16001', 'Forever 1.60.1 build 70450 rejects the previous 110200 declaration')
        self.assertEqual(metadata['Version'],'0.8.0-beta.15')
        for line in lines:
            if line and not line.startswith('#'):
                self.assertTrue((ROOT/line).is_file(), 'Missing TOC module: '+line)

if __name__ == '__main__':
    unittest.main(verbosity=2)

