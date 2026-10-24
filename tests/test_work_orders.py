"""Persistent crafter queues and user-click-only craft actions on supported clients."""
import importlib
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]

def fresh(runtime='lua51',profile='modern',saved=None):
    lua=importlib.import_module('lupa.'+runtime).LuaRuntime(unpack_returned_tuples=True)
    lua.execute((ROOT/'tests/wow_mock.lua').read_text())
    lua.globals().configure(profile)
    addon=lua.table(); lua.globals().addon=addon
    if saved is not None: lua.globals().CraftRosterDB=saved
    for name in (ROOT/'CraftRoster.toc').read_text().splitlines():
        if name.endswith('.lua'): lua.compile((ROOT/name).read_text(),name=name)('CraftRoster',addon)
    lua.execute("dispatch('ADDON_LOADED','CraftRoster')")
    return lua

CASES={
'conflicting_request_id_cannot_overwrite_a_different_craft': '''
    CraftRosterDB.recipes[42]={name='Boots',profession='Tailoring'}
    CraftRosterDB.recipes[43]={name='Gloves',profession='Tailoring'}
    local original=addon.WorkOrders:Add('Crafter-Realm',42,2,'reused','addon')
    assert(original and #addon.WorkOrders:GetOrders()==1)
    local warning
    print=function(message) warning=message end
    assert(not addon.WorkOrders:Add('Crafter-Realm',43,2,'reused','addon'))
    assert(not addon.WorkOrders:Add('Crafter-Realm',42,3,'reused','addon'))
    assert(#addon.WorkOrders:GetOrders()==1)
    assert(original.recipeID==42 and original.quantity==2 and original.requestID=='reused')
    assert(warning and warning:find('Conflicting request ID',1,true))
    assert(addon.WorkOrders:Add('Crafter-Realm',42,2,'reused','addon')==original)
    assert(#addon.WorkOrders:GetOrders()==1)
    assert(addon.WorkOrders:Add('Other-Realm',43,2,'reused','addon'))
    assert(#addon.WorkOrders:GetOrders()==2)
''',
'nil_request_id_does_not_match_manual_or_whisper_order': '''
    CraftRosterDB.recipes[42]={name='Boots',profession='Tailoring'}
    local order=addon.WorkOrders:Add('Crafter-Realm',42,1,nil,'manual')
    assert(order and order.requestID==nil)
    assert(not addon.WorkOrders:FindRequest(nil,'Crafter-Realm'))
    assert(not addon.WorkOrders:FindRequest('','Crafter-Realm'))
    assert(not addon.WorkOrders:UpdateRequestStatus(nil,'Crafter-Realm','completed'))
    assert(order.status=='requested')
''',
'queue_receives_multiple_customers_and_trade_filters': '''
    CraftRosterDB.recipes[42]={name='Boots',profession='Tailoring',itemLink='item:4320'}
    CraftRosterDB.recipes[43]={name='Enchant Chest',profession='Enchanting'}
    CraftRosterDB.characters['Tester-Realm'].recipes={[42]={},[43]={}}
    dispatch('CHAT_MSG_ADDON','CRAFTROSTER','ORDER:42:one:Tester-Realm:3 crafts of Boots','GUILD','Crafter-Realm')
    dispatch('CHAT_MSG_ADDON','CRAFTROSTER','ORDER:43:two:Tester-Realm:Enchant Chest','GUILD','Crafter-Realm')
    dispatch('CHAT_MSG_ADDON','CRAFTROSTER','ORDER:42:three:Tester-Realm:Boots','GUILD','Other-Realm')
    local all=addon.WorkOrders:GetOrders()
    assert(#all==3 and all[1].quantity==3)
    dispatch('TRADE_SHOW')
    assert(addon.WorkOrders.frame:IsShown() and #addon.WorkOrders.visibleOrders==2)
    assert(addon.WorkOrders.customerFilter=='Crafter-Realm')
    dispatch('TRADE_CLOSED'); assert(#addon.WorkOrders:GetOrders()==3)
''',
'two_same_recipe_whispers_cannot_claim_an_arbitrary_addon_identity': '''
    CraftRosterDB.recipes[42]={name='Boots',profession='Tailoring',itemLink='item:4320'}
    CraftRosterDB.characters['Tester-Realm'].recipes[42]={}
    local message='CraftRoster: Could you craft Boots? Materials: []'
    dispatch('CHAT_MSG_WHISPER',message,'Crafter-Realm')
    dispatch('CHAT_MSG_WHISPER',message,'Crafter-Realm')
    assert(#addon.WorkOrders:GetOrders()==2)
    dispatch('CHAT_MSG_ADDON','CRAFTROSTER','ORDER:42:ambiguous:Tester-Realm:Boots','GUILD','Crafter-Realm')
    local orders=addon.WorkOrders:GetOrders()
    assert(#orders==3,'distinct whispers must not silently collapse')
    assert(orders[1].requestID==nil and orders[2].requestID==nil)
    assert(orders[3].requestID=='ambiguous' and orders[3].status=='needs_review')
    assert(not addon.WorkOrders:ConfirmDone(orders[3].id,1))
''',
'two_same_recipe_addon_requests_cannot_claim_an_arbitrary_whisper': '''
    CraftRosterDB.recipes[42]={name='Boots',profession='Tailoring',itemLink='item:4320'}
    CraftRosterDB.characters['Tester-Realm'].recipes[42]={}
    dispatch('CHAT_MSG_ADDON','CRAFTROSTER','ORDER:42:one:Tester-Realm:Boots','GUILD','Crafter-Realm')
    dispatch('CHAT_MSG_ADDON','CRAFTROSTER','ORDER:42:two:Tester-Realm:Boots','GUILD','Crafter-Realm')
    assert(#addon.WorkOrders:GetOrders()==2)
    dispatch('CHAT_MSG_WHISPER','CraftRoster: Could you craft Boots? Materials: []','Crafter-Realm')
    local orders=addon.WorkOrders:GetOrders()
    assert(#orders==3,'whisper cannot attach to a random addon order')
    assert(orders[1].requestID=='one' and orders[2].requestID=='two')
    assert(orders[3].status=='needs_review' and orders[3].requestID==nil)
''',
'whisper_and_addon_request_merge_without_losing_distinct_orders': '''
    CraftRosterDB.recipes[42]={name='Boots',profession='Tailoring',itemLink='item:4320'}
    CraftRosterDB.characters['Tester-Realm'].recipes[42]={}
    local message='CraftRoster: Could you craft 2 crafts of |cff00ff00|Hitem:4320:0:0:0:0:0:0:0|h[Boots]|h|r? Materials: []'
    dispatch('CHAT_MSG_WHISPER',message,'Crafter-Realm')
    assert(#addon.WorkOrders:GetOrders()==1)
    dispatch('CHAT_MSG_ADDON','CRAFTROSTER','ORDER:42:one:Tester-Realm:2 crafts of Boots','GUILD','Crafter-Realm')
    dispatch('CHAT_MSG_ADDON','CRAFTROSTER','ORDER:42:one:Tester-Realm:2 crafts of Boots','GUILD','Crafter-Realm')
    assert(#addon.WorkOrders:GetOrders()==1)
    assert(addon.WorkOrders:GetOrders()[1].requestID=='one')
    dispatch('CHAT_MSG_ADDON','CRAFTROSTER','ORDER:42:two:Tester-Realm:2 crafts of Boots','GUILD','Crafter-Realm')
    assert(#addon.WorkOrders:GetOrders()==2)
    dispatch('CHAT_MSG_WHISPER','CraftRoster materials (continued): []','Crafter-Realm')
    dispatch('CHAT_MSG_WHISPER','Hi how are you?','Crafter-Realm')
    assert(#addon.WorkOrders:GetOrders()==2)
''',
'non_chronological_enchant_buttons_do_not_auto_cast_or_complete': '''
    CraftRosterDB.recipes[42]={name='Enchant Chest',profession='Enchanting'}
    CraftRosterDB.recipes[43]={name='Enchant Gloves',profession='Enchanting'}
    CraftRosterDB.characters['Tester-Realm'].recipes={[42]={},[43]={}}
    local chest=addon.WorkOrders:Add('Crafter-Realm',42,1,nil,'manual')
    local gloves=addon.WorkOrders:Add('Crafter-Realm',43,1,nil,'manual')
    local casts={}
    C_TradeSkillUI={GetRecipeInfo=function(id) return {learned=true} end,CraftEnchant=function(id,n) table.insert(casts,{id,n}) end}
    dispatch('TRADE_SHOW'); assert(#casts==0)
    local rows=addon.WorkOrders.frame.Rows
    assert(rows[1].order==chest and rows[2].order==gloves)
    rows[2].Craft.scripts.OnClick(); assert(#casts==1 and casts[1][1]==43 and casts[1][2]==1)
    rows[1].Craft.scripts.OnClick(); assert(#casts==2 and casts[2][1]==42)
    assert(chest.status=='requested' and gloves.status=='requested')
    rows[2].Done.scripts.OnClick()
    assert(gloves.status=='completed' and chest.status=='requested')
''',
'craft_click_opens_profession_then_uses_correct_id_once': '''
    CraftRosterDB.recipes[42]={name='Boots',profession='Tailoring',itemLink='item:4320'}
    CraftRosterDB.characters['Tester-Realm'].recipes[42]={}
    local order=addon.WorkOrders:Add('Crafter-Realm',42,3,nil,'manual')
    local ready=false; local opened,crafted=0,0
    C_TradeSkillUI={IsTradeSkillReady=function() return ready end,OpenTradeSkill=function(id) assert(id==197); opened=opened+1; return true end,
      GetBaseProfessionInfo=function() return {professionID=197} end,
      GetRecipeInfo=function(id) assert(id==42); return {learned=true} end,
      CraftRecipe=function(id,n) assert(id==42 and n==1); crafted=crafted+1 end}
    assert(not addon.WorkOrders:Craft(order.id) and opened==1 and crafted==0)
    ready=true; assert(addon.WorkOrders:Craft(order.id) and crafted==1)
    assert(order.done==0 and order.status=='requested')
''',
'legacy_recipe_indices_are_refound_after_sorting': '''
    CraftRosterDB.recipes[42]={name='Boots',profession='Tailoring',itemLink='item:4320'}
    CraftRosterDB.characters['Tester-Realm'].recipes[42]={}
    local order=addon.WorkOrders:Add('Crafter-Realm',42,1,nil,'manual')
    C_TradeSkillUI=nil
    local index=2; local called
    GetNumTradeSkills=function() return 3 end
    GetTradeSkillRecipeLink=function(i) return 'enchant:'..(i==index and 42 or 999) end
    DoTradeSkill=function(i,n) assert(n==1); called=i end
    assert(addon.WorkOrders:Craft(order.id) and called==2)
    index=1; clock=clock+1; addon.WorkOrders:Craft(order.id); assert(called==1)
''',
'unknown_wrong_customer_combat_and_targeting_block_actions': '''
    CraftRosterDB.recipes[42]={name='Boots',profession='Tailoring',itemLink='item:4320'}
    local order=addon.WorkOrders:Add('Other-Realm',42,1,nil,'manual')
    local crafted=0
    C_TradeSkillUI={GetRecipeInfo=function() return {learned=true} end,CraftRecipe=function() crafted=crafted+1 end}
    assert(not addon.WorkOrders:Craft(order.id))
    CraftRosterDB.characters['Tester-Realm'].recipes[42]={}
    dispatch('TRADE_SHOW'); assert(not addon.WorkOrders:Craft(order.id))
    dispatch('TRADE_CLOSED')
    InCombatLockdown=function() return true end; assert(not addon.WorkOrders:Craft(order.id))
    InCombatLockdown=function() return false end
    SpellIsTargeting=function() return true end; assert(not addon.WorkOrders:Craft(order.id))
    SpellIsTargeting=function() return false end
    addon.WorkOrders.selected={[order.id]=false}; assert(not addon.WorkOrders:Craft(order.id))
    assert(crafted==0)
''',
'ordinary_chat_can_be_added_manually_and_status_is_explicit': '''
    CraftRosterDB.recipes[42]={name='Boots',profession='Tailoring',itemLink='item:4320'}
    CraftRosterDB.characters['Tester-Realm'].recipes[42]={}
    addon.Directory:Toggle(); addon.Directory.selectedRecipe={id=42,name='Boots'}
    addon.ShoppingList:SetQuantity(42,2)
    local dialog=StaticPopupDialogs.CRAFTROSTER_ADD_ORDER
    dialog.OnAccept({data={recipeID=42,quantity=2},editBox={GetText=function() return 'Crafter-Realm' end}})
    local order=addon.WorkOrders:GetOrders()[1]
    assert(order.quantity==2)
    addon.WorkOrders:OneDone(order.id); assert(order.done==1 and order.status=='accepted')
    addon.WorkOrders:OneDone(order.id); assert(order.status=='completed' and #addon.WorkOrders:GetOrders()==0)
''',
'outstanding_orders_survive_history_trimming_and_status_updates': '''
    CraftRosterDB.recipes[42]={name='Boots',profession='Tailoring'}
    for i=1,55 do
      dispatch('CHAT_MSG_ADDON','CRAFTROSTER','ORDER:42:req'..i..':Tester-Realm:Boots','GUILD','Crafter-Realm')
    end
    assert(#CraftRosterDB.requests==50 and #addon.WorkOrders:GetOrders()==55)
    local order=addon.WorkOrders:GetOrders()[55]
    assert(addon.WorkOrders:SetStatus(order.id,'accepted'))
    assert(CraftRosterDB.requests[1].status=='accepted')
    assert(addon.WorkOrders:SetStatus(order.id,'declined'))
    assert(CraftRosterDB.requests[1].status=='declined' and #addon.WorkOrders:GetOrders()==54)
''',
'orders_validate_inputs_and_never_silently_drop_active_queue': '''
    assert(not addon.WorkOrders:Add('Crafter-Realm',42,0))
    assert(not addon.WorkOrders:Add('Crafter-Realm',42,1.5))
    assert(not addon.WorkOrders:Add('Crafter-Realm',42,1000))
    assert(not addon.WorkOrders:Add('Tester-Realm',42,1))
    assert(not addon.WorkOrders:Add('|Hitem:7',42,1))
    for i=1,500 do assert(addon.WorkOrders:Add('Crafter-Realm',42,1,'req'..i,'manual')) end
    assert(not addon.WorkOrders:Add('Crafter-Realm',42,1,'overflow','manual'))
    assert(#addon.WorkOrders:GetOrders()==500)
    addon.WorkOrders:SetStatus(1,'completed')
    assert(addon.WorkOrders:Add('Crafter-Realm',42,1,'next','manual'))
    assert(#addon.WorkOrders:GetOrders()==500)
''',
}

CASES.update({
'manual_order_accepts_spaced_realms_and_reports_invalid_names': '''
    CraftRosterDB.recipes[42]={name='Boots',profession='Tailoring'}
    local order=addon.WorkOrders:Add(' Crafter-Moon Guard ',42,1,nil,'manual')
    assert(order and order.customer=='Crafter-MoonGuard')
    assert(#addon.WorkOrders:GetOrders('Crafter-Moon Guard')==1)
    local message
    print=function(text) message=text end
    assert(not addon.WorkOrders:Add('Invalid Name-Realm',42,1,nil,'manual'))
    assert(message and message:find('valid customer name',1,true))
''',
'disabled_addon_does_not_auto_open_and_explains_craft_block': '''
    CraftRosterDB.recipes[42]={name='Boots',profession='Tailoring',itemLink='item:4320'}
    CraftRosterDB.characters['Tester-Realm'].recipes[42]={}
    local order=addon.WorkOrders:Add('Crafter-Realm',42,2,nil,'manual')
    CraftRosterDB.settings.enabled=false
    dispatch('TRADE_SHOW'); assert(not addon.WorkOrders.frame)
    addon.WorkOrders:Open()
    local row=addon.WorkOrders.frame.Rows[1]
    assert(row.Craft:GetText()=='Addon disabled')
    local message; print=function(text) message=text end
    assert(not addon.WorkOrders:Craft(order.id))
    assert(message:find('disabled',1,true))
''',
'new_trade_partner_without_orders_clears_old_customer_rows': '''
    local partner='Crafter'
    UnitName=function(unit) return unit=='NPC' and partner or 'Tester' end
    CraftRosterDB.recipes[42]={name='Boots',profession='Tailoring'}
    addon.WorkOrders:Add('Crafter-Realm',42,1,nil,'manual')
    dispatch('TRADE_SHOW'); assert(#addon.WorkOrders.visibleOrders==1)
    dispatch('TRADE_CLOSED')
    assert(addon.WorkOrders.frame.Status:GetText():find('Orders for Crafter',1,true))
    partner='Other'; dispatch('TRADE_SHOW')
    assert(addon.WorkOrders.customerFilter=='Other-Realm' and #addon.WorkOrders.visibleOrders==0)
    assert(not addon.WorkOrders.frame.Rows[1]:IsShown())
    addon.WorkOrders.frame:Hide(); addon.WorkOrders:Open()
    assert(#addon.WorkOrders.visibleOrders==0)
''',
'first_partial_done_syncs_acceptance_to_request_history': '''
    CraftRosterDB.recipes[42]={name='Boots',profession='Tailoring'}
    dispatch('CHAT_MSG_ADDON','CRAFTROSTER','ORDER:42:one:Tester-Realm:2 crafts of Boots','GUILD','Crafter-Realm')
    local order=addon.WorkOrders:GetOrders()[1]
    addon.WorkOrders:OneDone(order.id)
    assert(order.done==1 and order.status=='accepted')
    assert(CraftRosterDB.requests[1].status=='accepted')
''',
'bulk_craft_buttons_pass_counts_and_cap_to_order_remainder': '''
    CraftRosterDB.recipes[42]={name='Boots',profession='Tailoring',itemLink='item:4320'}
    CraftRosterDB.characters['Tester-Realm'].recipes[42]={}
    local order=addon.WorkOrders:Add('Crafter-Realm',42,10,nil,'manual')
    local counts={}
    C_TradeSkillUI={GetRecipeInfo=function() return {learned=true} end,
      CraftRecipe=function(id,n) assert(id==42); table.insert(counts,n) end}
    addon.WorkOrders:Open()
    local row=addon.WorkOrders.frame.Rows[1]
    assert(row.Batch:GetText()=='1')
    row.Craft.scripts.OnClick(); assert(counts[1]==1)
    clock=clock+1; row.Batch:SetText('4'); row.Batch.scripts.OnTextChanged(row.Batch,true)
    row.BatchCraft.scripts.OnClick(); assert(counts[2]==4)
    order.done=3; clock=clock+1
    row.CraftAll.scripts.OnClick(); assert(counts[3]==7)
    assert(order.done==3 and order.status=='requested')
    for _,n in ipairs({0,-1,1.5,8,'bad',false}) do
      clock=clock+1; assert(not addon.WorkOrders:Craft(order.id,n))
    end
    assert(#counts==3)
''',
'legacy_bulk_uses_native_count_and_does_not_mark_completed': '''
    CraftRosterDB.recipes[42]={name='Boots',profession='Tailoring',itemLink='item:4320'}
    CraftRosterDB.characters['Tester-Realm'].recipes[42]={}
    local order=addon.WorkOrders:Add('Crafter-Realm',42,6,nil,'manual')
    C_TradeSkillUI=nil
    GetNumTradeSkills=function() return 1 end
    GetTradeSkillRecipeLink=function() return 'enchant:42' end
    local number
    DoTradeSkill=function(index,n) assert(index==1); number=n end
    assert(addon.WorkOrders:Craft(order.id,4) and number==4)
    assert(order.done==0 and order.status=='requested')
''',
'enchants_retain_single_application_and_hide_bulk_controls': '''
    CraftRosterDB.recipes[42]={name='Enchant Gloves',profession='Enchanting',professionID=333}
    CraftRosterDB.characters['Tester-Realm'].recipes[42]={}
    local order=addon.WorkOrders:Add('Crafter-Realm',42,3,nil,'manual')
    local calls=0
    C_TradeSkillUI={GetRecipeInfo=function() return {learned=true} end,
      CraftEnchant=function(id,n) assert(n==1); calls=calls+1 end}
    addon.WorkOrders:Open()
    local row=addon.WorkOrders.frame.Rows[1]
    assert(row.Craft:GetText()=='Enchant' and not row.Batch:IsShown() and not row.CraftAll:IsShown())
    assert(not addon.WorkOrders:Craft(order.id,2))
    assert(not addon.WorkOrders:Craft(order.id,'all'))
    assert(calls==0 and addon.WorkOrders:Craft(order.id) and calls==1)
''',
'batch_values_survive_refresh_and_remain_per_order': '''
    CraftRosterDB.recipes[42]={name='Boots',profession='Tailoring',itemLink='item:4320'}
    CraftRosterDB.characters['Tester-Realm'].recipes[42]={}
    local one=addon.WorkOrders:Add('Crafter-Realm',42,9,nil,'manual')
    local two=addon.WorkOrders:Add('Other-Realm',42,5,nil,'manual')
    addon.WorkOrders:Open()
    local rows=addon.WorkOrders.frame.Rows
    rows[1].Batch:SetText('4'); rows[1].Batch.scripts.OnTextChanged(rows[1].Batch,true)
    rows[2].Batch:SetText('2'); rows[2].Batch.scripts.OnTextChanged(rows[2].Batch,true)
    addon.WorkOrders:Refresh()
    assert(rows[1].Batch:GetText()=='4' and rows[2].Batch:GetText()=='2')
    addon.WorkOrders:SetStatus(one.id,'completed')
    assert(rows[1].order==two and rows[1].Batch:GetText()=='2')
''',
'repeated_click_same_order_is_debounced_without_blocking_other_orders': '''
    CraftRosterDB.recipes[42]={name='Boots',profession='Tailoring',itemLink='item:4320'}
    CraftRosterDB.characters['Tester-Realm'].recipes[42]={}
    local one=addon.WorkOrders:Add('Crafter-Realm',42,5,nil,'manual')
    local two=addon.WorkOrders:Add('Crafter-Realm',42,5,nil,'manual')
    local calls=0
    C_TradeSkillUI={GetRecipeInfo=function() return {learned=true} end,CraftRecipe=function() calls=calls+1 end}
    assert(addon.WorkOrders:Craft(one.id,3))
    assert(not addon.WorkOrders:Craft(one.id,3))
    assert(addon.WorkOrders:Craft(two.id,1) and calls==2)
    clock=clock+1; assert(addon.WorkOrders:Craft(one.id,1) and calls==3)
''',
})

CASES.update({
'account_overview_tags_other_characters_without_mutating_saved_orders': '''
    CraftRosterDB.recipes[42]={name='Boots',profession='Tailoring',itemLink='item:4320'}
    CraftRosterDB.characters['Tester-Realm'].recipes[42]={}
    local mine=addon.WorkOrders:Add('Crafter-Realm',42,2,nil,'manual')
    local foreign={id=mine.id,customer='Crafter-Realm',recipeID=42,quantity=3,done=1,status='accepted',at=time()}
    CraftRosterDB.workOrders['alt-realm']={sequence=1,orders={foreign}}
    assert(#addon.WorkOrders:GetOrders()==1)
    local all=addon.WorkOrders:GetOrders(nil,true)
    assert(#all==2 and not foreign.ownerCharacter and not foreign.readOnly)
    local view
    for _,order in ipairs(all) do if order.readOnly then view=order end end
    assert(view and view.ownerCharacter=='alt-realm' and view.customer=='Crafter-Realm' and view.done==1)
    assert(#addon.WorkOrders:GetOrders('Other-Realm',true)==0)
''',
'account_overview_disables_foreign_actions_even_when_ids_collide': '''
    CraftRosterDB.recipes[42]={name='Boots',profession='Tailoring',itemLink='item:4320'}
    CraftRosterDB.characters['Tester-Realm'].recipes[42]={}
    local mine=addon.WorkOrders:Add('Crafter-Realm',42,2,nil,'manual')
    local foreign={id=mine.id,customer='Crafter-Realm',recipeID=42,quantity=3,done=1,status='accepted',at=time()}
    CraftRosterDB.workOrders['alt-realm']={sequence=1,orders={foreign}}
    local casts=0
    C_TradeSkillUI={GetRecipeInfo=function() return {learned=true} end,CraftRecipe=function() casts=casts+1 end}
    addon.WorkOrders:Open()
    addon.WorkOrders.frame.CharacterFilter.scripts.OnClick()
    assert(addon.WorkOrders.allCharacters and #addon.WorkOrders.visibleOrders==2)
    local row
    for _,r in ipairs(addon.WorkOrders.frame.Rows) do if r.order.readOnly then row=r end end
    assert(row and row.Craft:GetText()=='Other character' and not row.Batch:IsShown())
    row.Craft.scripts.OnClick(); row.BatchCraft.scripts.OnClick(); row.CraftAll.scripts.OnClick()
    row.Done.scripts.OnClick(); row.Accept.scripts.OnClick(); row.Decline.scripts.OnClick()
    assert(casts==0 and mine.done==0 and foreign.done==1 and foreign.status=='accepted')
    addon.WorkOrders:Open(); assert(not addon.WorkOrders.allCharacters and #addon.WorkOrders.visibleOrders==1)
''',
'current_character_orders_remain_separate_when_character_changes': '''
    CraftRosterDB.recipes[42]={name='Boots',profession='Tailoring'}
    addon.WorkOrders:Add('Crafter-Realm',42,2,nil,'manual')
    UnitName=function() return 'Alt' end
    assert(#addon.WorkOrders:GetOrders()==0)
    addon.WorkOrders:Add('Other-Realm',42,4,nil,'manual')
    local current=addon.WorkOrders:GetOrders()
    assert(#current==1 and current[1].customer=='Other-Realm')
    local all=addon.WorkOrders:GetOrders(nil,true)
    assert(#all==2)
    local original
    for _,order in ipairs(all) do if order.ownerCharacter=='tester-realm' then original=order end end
    assert(original and original.quantity==2 and original.readOnly)
''',
'bulk_row_controls_fit_and_do_not_overlap': '''
    CraftRosterDB.recipes[42]={name='Boots',profession='Tailoring',itemLink='item:4320'}
    CraftRosterDB.characters['Tester-Realm'].recipes[42]={}
    addon.WorkOrders:Add('Crafter-Realm',42,10,nil,'manual')
    addon.WorkOrders:Open()
    local row=addon.WorkOrders.frame.Rows[1]
    for _,button in ipairs({row.Craft,row.Batch,row.BatchCraft,row.CraftAll,row.Accept,row.Decline,row.Done}) do inside(button,row) end
    apart(row.Craft,row.BatchCraft); apart(row.Craft,row.CraftAll)
    apart(row.Batch,row.BatchCraft); apart(row.BatchCraft,row.CraftAll)
    apart(row.BatchCraft,row.Accept); apart(row.CraftAll,row.Done)
    inside(addon.WorkOrders.frame.CharacterFilter,addon.WorkOrders.frame)
''',
})

CASES.update({
'bulk_results_are_explicit_partial_editable_and_cancel_safe': '''
    CraftRosterDB.recipes[42]={name='Boots',profession='Tailoring',itemLink='item:4320'}
    CraftRosterDB.characters['Tester-Realm'].recipes[42]={}
    local order=addon.WorkOrders:Add('Crafter-Realm',42,30,nil,'manual')
    local requested
    C_TradeSkillUI={GetRecipeInfo=function() return {learned=true} end,CraftRecipe=function(id,n) requested=n end}
    addon.WorkOrders:Open(); assert(addon.WorkOrders:Craft(order.id,'all') and requested==30)
    assert(order.done==0 and order.status=='requested' and order.lastBatchCount==30)
    assert(addon.WorkOrders.frame.Rows[1].Done:GetText()=='Confirm batch')
    local popup,data
    StaticPopup_Show=function(which,one,two,payload) popup=which; data=payload end
    addon.WorkOrders.frame.Rows[1].Done.scripts.OnClick()
    assert(popup=='CRAFTROSTER_CONFIRM_BATCH' and data.id==order.id and data.count==30)
    -- Cancelling the dialog invokes no OnAccept and must leave all thirty outstanding.
    assert(order.done==0)
    StaticPopupDialogs.CRAFTROSTER_CONFIRM_BATCH.OnAccept({data=data,editBox={GetText=function() return '12' end}})
    assert(order.done==12 and order.quantity-order.done==18 and order.status=='accepted')
    assert(not order.lastBatchCount)
    clock=clock+1; assert(addon.WorkOrders:Craft(order.id,'all') and requested==18)
    assert(order.done==12)
''',
'bulk_result_confirmation_rejects_invalid_or_in_flight_results': '''
    CraftRosterDB.recipes[42]={name='Boots',profession='Tailoring'}
    local order=addon.WorkOrders:Add('Crafter-Realm',42,30,nil,'manual')
    for _,n in ipairs({0,-1,1.5,31,'wrong',false}) do assert(not addon.WorkOrders:ConfirmDone(order.id,n)) end
    assert(order.done==0)
    UnitCastingInfo=function() return 'Working' end
    assert(not addon.WorkOrders:ConfirmDone(order.id,12) and order.done==0)
    UnitCastingInfo=function() return nil end
    UnitChannelInfo=function() return 'Working' end
    assert(not addon.WorkOrders:ConfirmDone(order.id,12) and order.done==0)
    UnitChannelInfo=function() return nil end
    assert(addon.WorkOrders:ConfirmDone(order.id,12) and order.done==12)
    assert(not addon.WorkOrders:ConfirmDone(order.id,19))
    assert(addon.WorkOrders:ConfirmDone(order.id,18) and order.status=='completed')
    assert(not addon.WorkOrders:ConfirmDone(order.id,1))
''',
'delayed_whisper_merges_with_its_active_addon_order': '''
    CraftRosterDB.recipes[42]={name='Boots',profession='Tailoring',itemLink='item:4320'}
    CraftRosterDB.characters['Tester-Realm'].recipes[42]={}
    dispatch('CHAT_MSG_ADDON','CRAFTROSTER','ORDER:42:late:Tester-Realm:Boots','GUILD','Crafter-Realm')
    clock=clock+120
    dispatch('CHAT_MSG_WHISPER','CraftRoster: Could you craft Boots? Materials: []','Crafter-Realm')
    assert(#addon.WorkOrders:GetOrders()==1 and addon.WorkOrders:GetOrders()[1].requestID=='late')
''',
})

CASES.update({
'accepted_whisper_order_syncs_when_late_addon_identity_attaches': '''
    CraftRosterDB.recipes[42]={name='Boots',profession='Tailoring',itemLink='item:4320'}
    CraftRosterDB.characters['Tester-Realm'].recipes[42]={}
    dispatch('CHAT_MSG_WHISPER','CraftRoster: Could you craft 2 crafts of Boots? Materials: []','Crafter-Realm')
    local order=addon.WorkOrders:GetOrders()[1]
    addon.WorkOrders:OneDone(order.id)
    assert(order.status=='accepted' and order.done==1)
    clock=clock+120
    dispatch('CHAT_MSG_ADDON','CRAFTROSTER','ORDER:42:lateaccepted:Tester-Realm:2 crafts of Boots','GUILD','Crafter-Realm')
    assert(#addon.WorkOrders:GetOrders()==1 and order.requestID=='lateaccepted')
    assert(CraftRosterDB.requests[1].status=='accepted')
''',
'recently_closed_cross_source_order_requires_review_before_new_craft': '''
    CraftRosterDB.recipes[42]={name='Boots',profession='Tailoring',itemLink='item:4320'}
    CraftRosterDB.characters['Tester-Realm'].recipes[42]={}
    dispatch('CHAT_MSG_WHISPER','CraftRoster: Could you craft Boots? Materials: []','Crafter-Realm')
    addon.WorkOrders:OneDone(addon.WorkOrders:GetOrders()[1].id)
    dispatch('CHAT_MSG_ADDON','CRAFTROSTER','ORDER:42:closedlate:Tester-Realm:Boots','GUILD','Crafter-Realm')
    local order=addon.WorkOrders:GetOrders()[1]
    assert(order and order.status=='needs_review')
    local calls=0
    C_TradeSkillUI={GetRecipeInfo=function() return {learned=true} end,CraftRecipe=function() calls=calls+1 end}
    assert(not addon.WorkOrders:Craft(order.id) and not addon.WorkOrders:ConfirmDone(order.id,1))
    assert(calls==0 and addon.WorkOrders:SetStatus(order.id,'accepted'))
    assert(addon.WorkOrders:Craft(order.id) and calls==1)
''',
})

CASES.update({
'mail_and_manual_order_statuses_do_not_emit_guild_status_messages': """
    CraftRosterDB.recipes[42]={name='Boots',profession='Tailoring'}
    local order=addon.WorkOrders:Add('Crafter-Realm',42,1,'mail-key','mail')
    local calls=0
    addon.Requests.SetIncomingStatus=function() calls=calls+1 end
    addon.WorkOrders:OneDone(order.id)
    assert(order.status=='completed' and calls==0)
""",
})

class WorkOrderTests(unittest.TestCase): pass
for runtime in ('lua51','luajit21'):
    for profile in ('modern','legacy','minimal'):
        for name,code in CASES.items():
            def check(self,runtime=runtime,profile=profile,code=code):
                lua=fresh(runtime,profile)
                if 'inside(button,row)' in code: lua.execute((ROOT/'tests/layout_mock.lua').read_text())
                lua.execute(code)
            setattr(WorkOrderTests,f'test_{runtime}_{profile}_{name}',check)

class WorkOrderPersistenceTests(unittest.TestCase):
    def test_fresh_runtime_restores_orders_without_casting(self):
        for runtime in ('lua51','luajit21'):
            first=fresh(runtime)
            first.execute("addon.WorkOrders:Add('Crafter-Realm',42,2,nil,'manual'); addon.WorkOrders:OneDone(1)")
            def plain(v):
                return {plain(k):plain(value) for k,value in v.items()} if hasattr(v,'items') else v
            state=plain(first.globals().CraftRosterDB.workOrders)
            second=importlib.import_module('lupa.'+runtime).LuaRuntime(unpack_returned_tuples=True)
            def table(v): return second.table_from({k:table(value) for k,value in v.items()}) if isinstance(v,dict) else v
            saved=table({'workOrders':state})
            # Rebuild in this runtime so Lua objects are not shared across engines.
            second.execute((ROOT/'tests/wow_mock.lua').read_text()); second.globals().configure('modern')
            addon=second.table(); second.globals().addon=addon; second.globals().CraftRosterDB=saved
            for name in (ROOT/'CraftRoster.toc').read_text().splitlines():
                if name.endswith('.lua'): second.compile((ROOT/name).read_text(),name=name)('CraftRoster',addon)
            second.execute("dispatch('ADDON_LOADED','CraftRoster'); local list=addon.WorkOrders:GetOrders(); assert(#list==1 and list[1].done==1 and list[1].quantity==2)")

if __name__=='__main__': unittest.main()
