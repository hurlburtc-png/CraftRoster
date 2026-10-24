"""Regression cases from the independent trade/material-delivery review.

These deliberately model failure/event ordering that the happy-path bag mock
cannot infer. They remain mock tests, not a claim about Forever event timing.
"""
import unittest

from test_work_orders import fresh

CASES = {
    'hybrid_container_errors_fall_back_to_legacy_bag_reads': '''
        inventoryFixture(false,true)
        local slots=C_Container and C_Container.GetContainerNumSlots or GetContainerNumSlots
        local link=C_Container and C_Container.GetContainerItemLink or GetContainerItemLink
        GetContainerNumSlots=slots; GetContainerItemLink=link
        C_Container=C_Container or {}
        C_Container.GetContainerNumSlots=function() error('modern slots unavailable') end
        C_Container.GetContainerItemLink=function() error('modern link unavailable') end
        addon.Requests:StartTradeRequest(42,'Crafter-Realm')
        dispatch('TRADE_SHOW')
        assert(moved==3 and attachments[1]==3,
            'legacy bag functions should safely supply the intended reagent')
    ''',
    'hybrid_container_missing_results_fall_back_to_legacy': '''
        inventoryFixture(false,true)
        local slots=C_Container and C_Container.GetContainerNumSlots or GetContainerNumSlots
        local link=C_Container and C_Container.GetContainerItemLink or GetContainerItemLink
        GetContainerNumSlots=slots; GetContainerItemLink=link
        C_Container=C_Container or {}
        C_Container.GetContainerNumSlots=function() return nil end
        C_Container.GetContainerItemLink=function() return nil end
        addon.Requests:StartTradeRequest(42,'Crafter-Realm')
        dispatch('TRADE_SHOW')
        assert(moved==3 and attachments[1]==3,
            'nil modern bag data must not hide available legacy item data')
    ''',
    'broken_both_container_apis_skip_automatic_transfer': '''
        inventoryFixture(false,true)
        C_Container=C_Container or {}
        C_Container.GetContainerNumSlots=function() error('modern slots broken') end
        GetContainerNumSlots=function() error('legacy slots broken') end
        addon.Requests:StartTradeRequest(42,'Crafter-Realm')
        local id=CraftRosterDB.requests[1].id
        dispatch('TRADE_SHOW')
        assert(moved==0 and not next(attachments),
            'unreadable bags must not attach an arbitrary item')
        assert(addon.Requests:GetTradeProgress(id).remaining==3,
            'failed bag read must preserve undelivered material ledger')
    ''',
    'valid_empty_modern_bag_does_not_reopen_stale_legacy_slots': '''
        inventoryFixture(false,true)
        GetContainerNumSlots=function() return 2 end
        C_Container=C_Container or {}
        C_Container.GetContainerNumSlots=function() return 0 end
        addon.Requests:StartTradeRequest(42,'Crafter-Realm')
        dispatch('TRADE_SHOW')
        assert(moved==0 and not next(attachments),
            'a valid modern zero-slot result must not be overridden by stale legacy slots')
    ''',
    'outstanding_delivery_ledger_survives_short_history_trimming': '''
        inventoryFixture(false,true)
        CraftRosterDB.recipes[42].materials[1].count=30
        ERR_TRADE_COMPLETE='Trade complete.'
        addon.Requests:StartTradeRequest(42,'Crafter-Realm')
        local requestID=CraftRosterDB.requests[1].id
        dispatch('TRADE_SHOW')
        dispatch('TRADE_ACCEPT_UPDATE',1,1)
        dispatch('UI_INFO_MESSAGE',ERR_TRADE_COMPLETE)
        dispatch('TRADE_CLOSED')
        assert(addon.Requests:GetTradeProgress(requestID).remaining==6)
        for i=1,55 do
          dispatch('CHAT_MSG_ADDON','CRAFTROSTER',
            'ORDER:42:review-history-'..i..':Tester-Realm:Potion','GUILD','Other-Realm')
        end
        local progress=addon.Requests:GetTradeProgress(requestID)
        assert(progress and progress.delivered==24 and progress.remaining==6,
          'short request-history pruning must preserve an outstanding delivery ledger')
        attachments={}; inventory[1].count=100; inventory[2].count=0; moved=0
        addon.Requests:StartTradeRequest(42,'Crafter-Realm')
        dispatch('TRADE_SHOW')
        assert(moved==6,'resuming after history pruning must not offer all30 again')
    ''',
    'new_wrong_partner_trade_success_cannot_resolve_old_window': '''
        inventoryFixture(false,true)
        ERR_TRADE_COMPLETE='Trade complete.'
        addon.Requests:StartTradeRequest(42,'Crafter-Realm')
        local requestID=CraftRosterDB.requests[1].id
        dispatch('TRADE_SHOW'); dispatch('TRADE_CLOSED')
        assert(addon.Requests:GetTradeProgress(requestID).needsReview)
        function UnitName(unit) return unit=='NPC' and 'Other' or 'Tester' end
        attachments={}; moved=0
        dispatch('TRADE_SHOW')
        dispatch('UI_INFO_MESSAGE',ERR_TRADE_COMPLETE)
        local progress=addon.Requests:GetTradeProgress(requestID)
        assert(progress.delivered==0 and progress.remaining==3 and progress.needsReview,
          'a new unrelated window cannot supply the old window terminal result')
        assert(moved==0)
    ''',
    'new_wrong_partner_cancel_cannot_clear_old_uncertainty': '''
        inventoryFixture(false,true)
        ERR_TRADE_CANCELLED='Trade cancelled.'
        addon.Requests:StartTradeRequest(42,'Crafter-Realm')
        local requestID=CraftRosterDB.requests[1].id
        dispatch('TRADE_SHOW'); dispatch('TRADE_CLOSED')
        function UnitName(unit) return unit=='NPC' and 'Other' or 'Tester' end
        attachments={}; moved=0
        dispatch('TRADE_SHOW')
        dispatch('UI_ERROR_MESSAGE',ERR_TRADE_CANCELLED)
        dispatch('TRADE_REQUEST_CANCEL')
        dispatch('TRADE_CLOSED')
        local progress=addon.Requests:GetTradeProgress(requestID)
        assert(progress.delivered==0 and progress.needsReview,
          'an unrelated cancellation must not turn an unresolved delivery into retryable')
    ''',
    'accepted_offer_survives_empty_terminal_slots': '''
        inventoryFixture(false,true)
        ERR_TRADE_COMPLETE='Trade complete.'
        addon.Requests:StartTradeRequest(42,'Crafter-Realm')
        local requestID=CraftRosterDB.requests[1].id
        dispatch('TRADE_SHOW'); dispatch('TRADE_ACCEPT_UPDATE',1,1)
        -- Model native slot cleanup occurring before its success notification.
        attachments={}
        dispatch('UI_INFO_MESSAGE',ERR_TRADE_COMPLETE); dispatch('TRADE_CLOSED')
        local progress=addon.Requests:GetTradeProgress(requestID)
        assert(progress.delivered==3 and progress.remaining==0 and not progress.needsReview,
          'terminal-time slot cleanup must not replace the accepted offer with zero')
        moved=0; dispatch('TRADE_SHOW'); assert(moved==0)
    ''',
    'post_acceptance_item_ambiguity_never_enables_full_replay': '''
        inventoryFixture(false,true)
        ERR_TRADE_COMPLETE='Trade complete.'
        addon.Requests:StartTradeRequest(42,'Crafter-Realm')
        local requestID=CraftRosterDB.requests[1].id
        dispatch('TRADE_SHOW'); dispatch('TRADE_ACCEPT_UPDATE',1,1)
        -- This could be teardown or an edit. A missing new acceptance is ambiguous.
        attachments={}; dispatch('TRADE_PLAYER_ITEM_CHANGED',1)
        dispatch('UI_INFO_MESSAGE',ERR_TRADE_COMPLETE); dispatch('TRADE_CLOSED')
        local progress=addon.Requests:GetTradeProgress(requestID)
        assert(progress.remaining==0 or progress.needsReview,
          'ambiguous item events must not leave a successful trade retryable at full quantity')
        moved=0; dispatch('TRADE_SHOW'); assert(moved==0)
    ''',
    'same_quantity_whisper_resume_reopens_draft_without_resetting_ledger': '''
        inventoryFixture(false,true)
        local drafts={}
        function ChatFrame_OpenChat(text) table.insert(drafts,text) end
        addon.Requests:StartTradeRequest(42,'Crafter-Realm')
        local requestID=CraftRosterDB.requests[1].id
        assert(#drafts==1)
        addon.Requests:StartTradeRequest(42,'Crafter-Realm')
        assert(#drafts==2,'clicking Whisper again must recreate the same-quantity draft')
        assert(#CraftRosterDB.requests==1 and CraftRosterDB.requests[1].id==requestID,
          'resuming the same request must not create a second order')
        assert(addon.Requests:GetTradeProgress(requestID).remaining==3)
    ''',
    'changed_quantity_requires_explicit_choice_and_new_order_uses_new_quantity': '''
        inventoryFixture(false,true)
        local drafts={}
        function ChatFrame_OpenChat(text) table.insert(drafts,text) end
        addon.Requests:StartTradeRequest(42,'Crafter-Realm')
        local originalID=CraftRosterDB.requests[1].id
        addon.ShoppingList:SetQuantity(42,3)
        local shown,data
        StaticPopup_Show=function(which,_,__,value) shown=which; data=value end
        addon.Requests:StartTradeRequest(42,'Crafter-Realm')
        assert(shown=='CRAFTROSTER_RESUME_TRADE',
          'a changed quantity must not silently reuse the old material requirement')
        assert(#drafts==1 and addon.Requests:GetTradeProgress(originalID).remaining==3)
        StaticPopupDialogs.CRAFTROSTER_RESUME_TRADE.OnAlt({data=data})
        assert(#drafts==2 and drafts[2]:find('3 crafts of Potion',1,true))
        assert(CraftRosterDB.requests[1].id~=originalID and CraftRosterDB.requests[1].quantity==3)
        dispatch('TRADE_SHOW'); assert(moved==9)
    ''',
    'matching_preaddressed_mail_can_still_prepare': '''
        inventoryFixture(false,true)
        MailFrame=CreateFrame(); MailFrame:Show()
        SendMailNameEditBox=CreateFrame(); SendMailSubjectEditBox=CreateFrame(); SendMailBodyEditBox=CreateFrame()
        SendMailNameEditBox:SetText('Crafter-Realm')
        addon.Requests:MailPlayer(42,'Crafter-Realm')
        assert(SendMailNameEditBox:GetText()=='Crafter-Realm')
        assert(SendMailSubjectEditBox:GetText()=='Potion craft requested' and moved==3,
          'an already-correct recipient must not block normal mail preparation')
    ''',
    'recipient_only_mail_draft_is_not_readdressed': '''
        inventoryFixture(false,true)
        MailFrame=CreateFrame(); MailFrame:Show()
        SendMailNameEditBox=CreateFrame(); SendMailSubjectEditBox=CreateFrame(); SendMailBodyEditBox=CreateFrame()
        SendMailNameEditBox:SetText('Previous-Realm')
        addon.Requests:MailPlayer(42,'Crafter-Realm')
        dispatch('MAIL_SHOW')
        assert(moved==0 and SendMailNameEditBox:GetText()=='Previous-Realm',
          'recipient-only draft must not be redirected or loaded')
        assert(SendMailSubjectEditBox:GetText()=='' and SendMailBodyEditBox:GetText()=='',
          'recipient-only draft fields must remain untouched')
    ''',
    'changed_mail_recipient_blocks_subsequent_auto_load': '''
        inventoryFixture(false,true)
        MailFrame=CreateFrame(); MailFrame:Show()
        SendMailNameEditBox=CreateFrame(); SendMailSubjectEditBox=CreateFrame(); SendMailBodyEditBox=CreateFrame()
        CraftRosterDB.settings.autoLoadItems=false
        addon.Requests:MailPlayer(42,'Crafter-Realm')
        assert(SendMailNameEditBox:GetText()=='Crafter-Realm')
        local subject=SendMailSubjectEditBox:GetText()
        local body=SendMailBodyEditBox:GetText()
        CraftRosterDB.settings.autoLoadItems=true
        SendMailNameEditBox:SetText('Different-Realm')
        dispatch('MAIL_SHOW')
        assert(moved==0 and SendMailNameEditBox:GetText()=='Different-Realm',
          'recipient change after draft preparation must block attachments')
        assert(SendMailSubjectEditBox:GetText()==subject and SendMailBodyEditBox:GetText()==body)
        SendMailNameEditBox:SetText('')
        dispatch('MAIL_SHOW')
        assert(moved==0, 'cleared recipient must also block attachments')
    ''',
    'occupied_mail_compose_is_not_readdressed_or_overfilled': '''
        inventoryFixture(false,true)
        attachments[1]=3
        MailFrame=CreateFrame(); MailFrame:Show()
        SendMailNameEditBox=CreateFrame(); SendMailSubjectEditBox=CreateFrame(); SendMailBodyEditBox=CreateFrame()
        SendMailNameEditBox:SetText('Previous-Realm')
        SendMailSubjectEditBox:SetText('Existing subject')
        SendMailBodyEditBox:SetText('Existing body')
        addon.Requests:MailPlayer(42,'Crafter-Realm')
        dispatch('MAIL_SHOW')
        assert(moved==0 and attachments[1]==3 and attachments[2]==nil,
          'existing matching attachments must not be duplicated')
        assert(SendMailNameEditBox:GetText()=='Previous-Realm',
          'do not redirect existing attachments to a different crafter')
        assert(SendMailSubjectEditBox:GetText()=='Existing subject')
        assert(SendMailBodyEditBox:GetText()=='Existing body')
    ''',
}

# Mail inspection must fail closed when hybrid client APIs throw. Retry the
# same pending draft after the API recovers; never mutate a pre-existing draft.
for api in ('GetSendMailMoney', 'GetSendMailCOD', 'GetSendMailItem'):
    CASES[f'mail_inspection_{api}_error_is_retryable'] = f"""
        inventoryFixture(false,true)
        MailFrame=CreateFrame(); MailFrame:Show()
        SendMailNameEditBox=CreateFrame(); SendMailSubjectEditBox=CreateFrame(); SendMailBodyEditBox=CreateFrame()
        local original={api}
        {api}=function() error('hybrid mail API temporarily unavailable') end
        addon.Requests:MailPlayer(42,'Crafter-Realm')
        assert(moved==0 and SendMailNameEditBox:GetText()=='' and
            SendMailSubjectEditBox:GetText()=='' and SendMailBodyEditBox:GetText()=='',
            'unknown mail state must not change the outgoing draft')
        {api}=original
        dispatch('MAIL_SHOW')
        assert(moved==3 and SendMailNameEditBox:GetText()=='Crafter-Realm' and
            SendMailSubjectEditBox:GetText()=='Potion craft requested',
            'recovered mail inspection should prepare the same pending request')
    """

for field in ('SendMailNameEditBox', 'SendMailSubjectEditBox', 'SendMailBodyEditBox'):
    CASES[f'mail_inspection_{field}_error_is_retryable'] = f"""
        inventoryFixture(false,true)
        MailFrame=CreateFrame(); MailFrame:Show()
        SendMailNameEditBox=CreateFrame(); SendMailSubjectEditBox=CreateFrame(); SendMailBodyEditBox=CreateFrame()
        local original={field}.GetText
        {field}.GetText=function() error('mail edit box not ready') end
        addon.Requests:MailPlayer(42,'Crafter-Realm')
        assert(moved==0 and rawget(SendMailNameEditBox,'text')==nil and
            rawget(SendMailSubjectEditBox,'text')==nil and rawget(SendMailBodyEditBox,'text')==nil,
            'unreadable draft fields must not authorize attachment or overwrite')
        {field}.GetText=original
        dispatch('MAIL_SHOW')
        assert(moved==3 and SendMailNameEditBox:GetText()=='Crafter-Realm' and
            SendMailSubjectEditBox:GetText()=='Potion craft requested')
    """

for final_status in ('completed','declined','cancelled'):
    CASES[f'final_request_{final_status}_does_not_resume_old_delivery'] = f'''
        inventoryFixture(false,true)
        local drafts=0
        function ChatFrame_OpenChat(text) drafts=drafts+1 end
        addon.Requests:StartTradeRequest(42,'Crafter-Realm')
        local originalID=CraftRosterDB.requests[1].id
        CraftRosterDB.requests[1].status='{final_status}'
        addon.Requests:StartTradeRequest(42,'Crafter-Realm')
        assert(drafts==2 and #CraftRosterDB.requests==2,
          'a terminal request is history, not a silently resumed outstanding order')
        assert(CraftRosterDB.requests[1].id~=originalID)
    '''

for money_api in ('GetSendMailMoney','GetSendMailCOD'):
    CASES[f'compose_{money_api}_is_not_readdressed'] = f"""
        inventoryFixture(false,true)
        MailFrame=CreateFrame(); MailFrame:Show()
        SendMailNameEditBox=CreateFrame(); SendMailSubjectEditBox=CreateFrame(); SendMailBodyEditBox=CreateFrame()
        SendMailNameEditBox:SetText('Previous-Realm')
        SendMailSubjectEditBox:SetText('Existing money draft')
        SendMailBodyEditBox:SetText('Existing body')
        {money_api}=function() return 10000 end
        addon.Requests:MailPlayer(42,'Crafter-Realm'); dispatch('MAIL_SHOW')
        assert(moved==0 and SendMailNameEditBox:GetText()=='Previous-Realm',
          'existing outgoing money or COD must not be transferred into a new craft draft')
        assert(SendMailSubjectEditBox:GetText()=='Existing money draft')
        assert(SendMailBodyEditBox:GetText()=='Existing body')
    """

for stale_state in ('completed','abandoned'):
    change = "CraftRosterDB.requests[1].status='completed'" if stale_state=='completed' else 'CraftRosterDB.requests[1].tradeAbandoned=true'
    CASES[f'quantity_popup_cannot_resume_later_{stale_state}_record'] = f"""
        inventoryFixture(false,true)
        local drafts=0
        function ChatFrame_OpenChat(text) drafts=drafts+1 end
        addon.Requests:StartTradeRequest(42,'Crafter-Realm')
        addon.ShoppingList:SetQuantity(42,3)
        local shown,data
        StaticPopup_Show=function(which,_,__,value) shown=which; data=value end
        addon.Requests:StartTradeRequest(42,'Crafter-Realm')
        assert(shown=='CRAFTROSTER_RESUME_TRADE')
        {change}
        StaticPopupDialogs.CRAFTROSTER_RESUME_TRADE.OnAccept({{data=data}})
        assert(drafts==1 and addon.ShoppingList:GetQuantity(42)==3,
          'a stale popup must revalidate whether its old request can still be resumed')
    """


for terminal_status in ('completed','declined','cancelled'):
    CASES[f'terminal_{terminal_status}_partial_trade_does_not_block_new_mail'] = f"""
        inventoryFixture(false,true)
        CraftRosterDB.recipes[42].materials[1].count=30
        ERR_TRADE_COMPLETE='Trade complete.'
        addon.Requests:StartTradeRequest(42,'Crafter-Realm')
        dispatch('TRADE_SHOW'); dispatch('TRADE_ACCEPT_UPDATE',1,1)
        dispatch('UI_INFO_MESSAGE',ERR_TRADE_COMPLETE); dispatch('TRADE_CLOSED')
        local id=CraftRosterDB.requests[1].id
        assert(addon.Requests:GetTradeProgress(id).remaining==6)
        CraftRosterDB.requests[1].status='{terminal_status}'
        assert(addon.Requests:CanPrepareMail(42,'Crafter-Realm'),
          'a terminal old order must not permanently block a separate new mail order')
    """



# Completed, declined and cancelled deliveries belong to previous jobs.
# Their material ledgers must not discount a new identical craft request.
for terminal_status in ('completed','declined','cancelled'):
    CASES[f'closed_{terminal_status}_trade_does_not_discount_new_shopping_list'] = f"""
        inventoryFixture(false,true)
        addon.Requests:StartTradeRequest(42,'Crafter-Realm')
        local previous=CraftRosterDB.requests[1]
        assert(previous and previous.materialLedger and previous.materialLedger[1].count==3)
        previous.materialLedger[1].remaining=0
        previous.status='{terminal_status}'
        local oldCredit=addon.Requests:GetDeliveredMaterials(42,'Crafter-Realm',1)
        assert(not next(oldCredit),'closed trades must not credit an unrelated new order')
        local entries=addon.ShoppingList:GetMaterialStatus(42,'Crafter-Realm')
        assert(entries and entries[1].delivered==0 and entries[1].required==3,
          'shopping list must show all three materials for a new craft')
        addon.Requests:StartTradeRequest(42,'Crafter-Realm')
        local current=CraftRosterDB.requests[1]
        assert(current~=previous and current.materialLedger[1].remaining==3,
          'starting a new order must retain its full material requirement')
        current.materialLedger[1].remaining=2
        local credit=addon.Requests:GetDeliveredMaterials(42,'Crafter-Realm',1)
        assert(credit[7]==1,'verified progress on the active order must still count')
        entries=addon.ShoppingList:GetMaterialStatus(42,'Crafter-Realm')
        assert(entries[1].delivered==1 and entries[1].required==2,
          'only the active order should reduce outstanding materials')
    """


class TradeReviewTests(unittest.TestCase):
    pass

for runtime in ('lua51','luajit21'):
    for profile in ('modern','legacy','minimal'):
        for name,code in CASES.items():
            def check(self,runtime=runtime,profile=profile,code=code):
                fresh(runtime,profile).execute(code)
            setattr(TradeReviewTests,f'test_{runtime}_{profile}_{name}',check)

if __name__=='__main__':
    unittest.main()
