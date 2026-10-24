"""Regressions from independent reviews across feature boundaries."""
import unittest
from test_work_orders import fresh

CASES={
 'accepted_trade_success_after_cancellation_stays_cancelled': """
    inventoryFixture(false,true)
    addon.Requests:StartTradeRequest(42,'Crafter-Realm')
    local record=CraftRosterDB.requests[1]
    dispatch('TRADE_SHOW'); dispatch('TRADE_ACCEPT_UPDATE',1,1)
    addon.Requests:CancelCurrentRequests(42,'Crafter-Realm')
    ERR_TRADE_COMPLETE='Trade complete.'
    dispatch('UI_INFO_MESSAGE',ERR_TRADE_COMPLETE); dispatch('TRADE_CLOSED')
    assert(record.status=='cancelled' and addon.Requests:GetTradeProgress(record.id).delivered==3)
    moved=0; attachments={}; dispatch('TRADE_SHOW'); assert(moved==0)
""",
 'cancel_request_is_scoped_and_stops_loading': """
    inventoryFixture(false,true)
    addon.Requests:StartTradeRequest(42,'Crafter-Realm')
    local record=CraftRosterDB.requests[1]
    table.insert(CraftRosterDB.requests,{id='other',recipeID=43,target='Crafter-Realm',mode='craft',status='requested'})
    table.insert(CraftRosterDB.requests,{id='alt',recipeID=42,target='Crafter-Realm',mode='craft',status='requested',ownerCharacter='alt-realm'})
    assert(addon.Requests:CancelCurrentRequests(42,'Crafter-Realm')==1)
    assert(record.status=='cancelled' and record.tradeAbandoned)
    assert(CraftRosterDB.requests[2].status=='requested' and CraftRosterDB.requests[3].status=='requested')
    if #sent>0 then assert(sent[#sent][2]=='RSTAT:'..record.id..':cancelled') end
    dispatch('TRADE_SHOW'); assert(moved==0)
    assert(addon.Requests:CancelCurrentRequests(42,'Crafter-Realm')==0)
    dispatch('CHAT_MSG_ADDON','CRAFTROSTER','RSTAT:'..record.id..':accepted','GUILD','Crafter-Realm')
    assert(record.status=='cancelled')
""",
 'cancelled_mail_does_not_load_at_next_mailbox': """
    inventoryFixture(false,true)
    addon.Requests:MailPlayer(42,'Crafter-Realm')
    assert(addon.Requests:CancelCurrentRequests(42,'Crafter-Realm')==1)
    dispatch('MAIL_SHOW'); assert(moved==0)
""",
'cancelled_remote_order_disappears_even_after_history_trim': """
    CraftRosterDB.recipes[42]={name='Potion',profession='Alchemy'}
    dispatch('CHAT_MSG_ADDON','CRAFTROSTER','ORDER:42:one:Tester-Realm:Potion','GUILD','Crafter-Realm')
    CraftRosterDB.requests={}
    dispatch('CHAT_MSG_ADDON','CRAFTROSTER','RSTAT:one:cancelled','GUILD','Other-Realm')
    assert(#addon.WorkOrders:GetOrders()==1)
    dispatch('CHAT_MSG_ADDON','CRAFTROSTER','RSTAT:one:cancelled','GUILD','Crafter-Realm')
    assert(#addon.WorkOrders:GetOrders()==0)
    dispatch('CHAT_MSG_ADDON','CRAFTROSTER','RSTAT:one:accepted','GUILD','Crafter-Realm')
    assert(addon.WorkOrders:FindRequest('one','Crafter-Realm').status=='cancelled')
""",
'shopping_subtracts_confirmed_deliveries_only': '''
    inventoryFixture(false,true); CraftRosterDB.recipes[42].materials[1].count=30
    addon.Directory.selectedRecipe={id=42}; addon.Directory.selectedCrafter='Crafter-Realm'
    addon.ShoppingList:Open(42)
    addon.Requests:StartTradeRequest(42,'Crafter-Realm'); dispatch('TRADE_SHOW')
    addon.ShoppingList:Refresh(); assert(addon.ShoppingList.entries[1].required==30)
    ERR_TRADE_COMPLETE='Trade complete.'
    dispatch('TRADE_ACCEPT_UPDATE',1,1); dispatch('UI_INFO_MESSAGE',ERR_TRADE_COMPLETE); dispatch('TRADE_CLOSED')
    flushTimers()
    local entry=addon.ShoppingList.entries[1]
    assert(entry.delivered==24 and entry.required==6)
    attachments={}; inventory[1].count=6; inventory[2].count=0
    dispatch('TRADE_SHOW'); dispatch('UI_INFO_MESSAGE',ERR_TRADE_COMPLETE); dispatch('TRADE_CLOSED'); flushTimers()
    entry=addon.ShoppingList.entries[1]; assert(entry.delivered==30 and entry.required==0)
''',
'remote_status_updates_both_history_and_work_queue': '''
    CraftRosterDB.recipes[42]={name='Potion',profession='Alchemy'}
    dispatch('CHAT_MSG_ADDON','CRAFTROSTER','ORDER:42:one:Tester-Realm:Potion','GUILD','Crafter-Realm')
    dispatch('CHAT_MSG_ADDON','CRAFTROSTER','RSTAT:one:declined','GUILD','Other-Realm')
    assert(#addon.WorkOrders:GetOrders()==1)
    dispatch('CHAT_MSG_ADDON','CRAFTROSTER','RSTAT:one:declined','GUILD','Crafter-Realm')
    assert(CraftRosterDB.requests[1].status=='declined' and #addon.WorkOrders:GetOrders()==0)
''',
'status_for_trimmed_incoming_order_updates_persistent_queue': '''
    CraftRosterDB.recipes[42]={name='Potion',profession='Alchemy'}
    for i=1,55 do dispatch('CHAT_MSG_ADDON','CRAFTROSTER','ORDER:42:req'..i..':Tester-Realm:Potion','GUILD','Crafter-Realm') end
    assert(#CraftRosterDB.requests==50 and #addon.WorkOrders:GetOrders()==55)
    dispatch('CHAT_MSG_ADDON','CRAFTROSTER','RSTAT:req1:completed','GUILD','Crafter-Realm')
    assert(#addon.WorkOrders:GetOrders()==54 and addon.WorkOrders:FindRequest('req1','Crafter-Realm').status=='completed')
''',
'mail_cannot_bypass_partial_or_unknown_material_delivery': '''
    inventoryFixture(false,true); CraftRosterDB.recipes[42].materials[1].count=30
    addon.Requests:StartTradeRequest(42,'Crafter-Realm'); dispatch('TRADE_SHOW')
    ERR_TRADE_COMPLETE='Trade complete.'
    dispatch('UI_INFO_MESSAGE',ERR_TRADE_COMPLETE); dispatch('TRADE_CLOSED')
    attachments={}; inventory[1].count=30; moved=0
    SendMailNameEditBox=CreateFrame(); SendMailNameEditBox:SetText('Keep-Realm')
    addon.Requests:MailPlayer(42,'Crafter-Realm'); dispatch('MAIL_SHOW')
    assert(moved==0 and SendMailNameEditBox:GetText()=='Keep-Realm')
''',
'catalog_and_modern_scans_retain_numeric_profession_identity': '''
    C_TradeSkillUI={
      GetAllRecipeIDs=function() return {42} end,
      GetBaseProfessionInfo=function() return {professionID=333,professionName='Enchanteur'} end,
      GetRecipeInfo=function() return {name='Enchantement',learned=true} end,
      GetRecipeSchematic=function() return {reagentSlotSchematics={}} end
    }
    addon.RecipeTracker:ImportTradeSkillRecipes()
    assert(CraftRosterDB.recipes[42].professionID==333)
    local order=addon.WorkOrders:Add('Crafter-Realm',42,1,nil,'manual')
    assert(addon.WorkOrders:IsEnchant(order))
''',
'mail_money_cod_and_existing_text_are_preserved': """
    inventoryFixture(false,true)
    SendMailNameEditBox=CreateFrame(); SendMailNameEditBox:SetText('Previous-Realm')
    SendMailSubjectEditBox=CreateFrame(); SendMailBodyEditBox=CreateFrame()
    GetSendMailMoney=function() return 10000 end
    addon.Requests:MailPlayer(42,'Crafter-Realm'); dispatch('MAIL_SHOW')
    assert(moved==0 and SendMailNameEditBox:GetText()=='Previous-Realm')
    GetSendMailMoney=function() return 0 end; GetSendMailCOD=function() return 500 end
    dispatch('MAIL_SHOW'); assert(moved==0 and SendMailNameEditBox:GetText()=='Previous-Realm')
    GetSendMailCOD=function() return 0 end; SendMailBodyEditBox:SetText('Keep my draft')
    dispatch('MAIL_SHOW'); assert(moved==0 and SendMailBodyEditBox:GetText()=='Keep my draft')
""",
'declining_outgoing_order_disarms_automatic_loading': """
    inventoryFixture(false,true)
    addon.Requests:StartTradeRequest(42,'Crafter-Realm')
    local id=CraftRosterDB.requests[1].id
    dispatch('CHAT_MSG_ADDON','CRAFTROSTER','RSTAT:'..id..':declined','GUILD','Crafter-Realm')
    dispatch('TRADE_SHOW'); assert(moved==0)
""",
'quantity_dialog_cannot_resume_a_changed_order': """
    inventoryFixture(false,true)
    addon.Requests:StartTradeRequest(42,'Crafter-Realm')
    local record=CraftRosterDB.requests[1]
    local data={requestID=record.id,recipeID=42,target='Crafter-Realm',quantity=3}
    record.status='declined'
    StaticPopupDialogs.CRAFTROSTER_RESUME_TRADE.OnAccept({data=data})
    StaticPopupDialogs.CRAFTROSTER_RESUME_TRADE.OnAlt({data=data})
    assert(#CraftRosterDB.requests==1 and not record.tradeAbandoned)
""",

'outgoing_material_transfers_do_not_resume_on_another_character': """
    inventoryFixture(false,true)
    addon.Requests:StartTradeRequest(42,'Crafter-Realm'); addon.Requests:Cancel()
    local old=UnitName
    UnitName=function(unit) return unit=='player' and 'Alt' or old(unit) end
    CraftRosterDB.characters['Alt-Realm']={recipes={}}
    addon.Requests:StartTradeRequest(42,'Crafter-Realm')
    assert(#CraftRosterDB.requests==2 and CraftRosterDB.requests[1].ownerCharacter=='alt-realm')
    dispatch('TRADE_SHOW'); assert(moved==3)
""",
'outstanding_transfer_limit_preserves_prior_delivery_ledgers': """
    inventoryFixture(false,true)
    for i=1,101 do
      CraftRosterDB.recipes[i]={name='Craft '..i,materials={{name='Herb',itemID=7,count=1}}}
      addon.Requests:StartTradeRequest(i,'Crafter-Realm')
    end
    assert(#CraftRosterDB.requests==100 and CraftRosterDB.requests[1].recipeID==100)
    for _,request in ipairs(CraftRosterDB.requests) do assert(request.materialLedger[1].remaining==1) end
""",
'guild_restriction_checks_fail_closed_without_losing_local_status': """
    local request={id='restricted',mode='incoming',target='Crafter-Realm',status='requested'}
    CraftRosterDB.requests=CraftRosterDB.requests or {}
    table.insert(CraftRosterDB.requests,request)
    local warned=0
    addon.WarnChatRestricted=function() warned=warned+1 end
    C_ChatInfo=C_ChatInfo or {}
    C_ChatInfo.AreOutgoingAddonChatMessagesRestricted=function() error('restriction unavailable') end
    local before=#sent
    assert(not addon.Requests:SetIncomingStatus('restricted','Crafter-Realm','accepted'))
    assert(request.status=='accepted' and #sent==before and warned==1)
    C_ChatInfo.AreOutgoingAddonChatMessagesRestricted=function() return false end
    C_ChatInfo.InChatMessagingLockdown=function() error('lockdown unavailable') end
    assert(not addon.Requests:SetIncomingStatus('restricted','Crafter-Realm','declined'))
    assert(request.status=='declined' and #sent==before and warned==2)
    C_ChatInfo.InChatMessagingLockdown=function() return false end
    C_ChatInfo.SendAddonMessage=function(prefix,message,channel)
        table.insert(sent,{prefix,message,channel}); return true
    end
    assert(addon.Requests:SetIncomingStatus('restricted','Crafter-Realm','accepted'))
    assert(#sent==before+1 and sent[#sent][2]=='RSTAT:restricted:accepted')
""",
'guild_send_and_membership_errors_do_not_duplicate_requests': """
    local request={id='transport',mode='incoming',target='Crafter-Realm',status='requested'}
    CraftRosterDB.requests=CraftRosterDB.requests or {}
    table.insert(CraftRosterDB.requests,request)
    C_ChatInfo=C_ChatInfo or {}
    local before=#sent
    IsInGuild=function() error('guild state unavailable') end
    assert(not addon.Requests:SetIncomingStatus('transport','Crafter-Realm','accepted'))
    assert(#sent==before and request.status=='accepted')
    IsInGuild=function() return true end
    C_ChatInfo.SendAddonMessage=function() error('send unavailable') end
    assert(not addon.Requests:SetIncomingStatus('transport','Crafter-Realm','declined'))
    assert(#sent==before and request.status=='declined')
    C_ChatInfo.SendAddonMessage=function(prefix,message,channel)
        table.insert(sent,{prefix,message,channel}); return true
    end
    assert(addon.Requests:SetIncomingStatus('transport','Crafter-Realm','accepted'))
    assert(#sent==before+1 and sent[#sent][2]=='RSTAT:transport:accepted')
""",
}
class ReviewIntegrationTests(unittest.TestCase): pass
for runtime in ('lua51','luajit21'):
    for profile in ('modern','legacy','minimal'):
        for name,code in CASES.items():
            def check(self,runtime=runtime,profile=profile,code=code): fresh(runtime,profile).execute(code)
            setattr(ReviewIntegrationTests,f'test_{runtime}_{profile}_{name}',check)
