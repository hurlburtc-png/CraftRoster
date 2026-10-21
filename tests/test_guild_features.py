"""Composer clicks, private/public notes, bounded schematic sync and source coverage."""
import unittest
from test_work_orders import fresh

CASES={
'composer_opens_without_sending_then_crafter_click_sends_once': '''
    inventoryFixture(false,true)
    CraftRosterDB.characters['Crafter-Realm']={recipes={[42]={}}}
    local messages={}
    SendChatMessage=function(message,kind,language,target) messages[#messages+1]={message,kind,target} end
    assert(addon.WhisperComposer:Open(42,nil))
    assert(#messages==0 and not CraftRosterDB.requests)
    assert(addon.WhisperComposer.frame.Edit:GetText():find('3x ',1,true))
    local inserted
    IsShiftKeyDown=function() return true end
    ChatEdit_InsertLink=function(link) inserted=link; return true end
    addon.WhisperComposer.frame.Preview.scripts.OnHyperlinkClick(nil,'item:7','[Herb]','LeftButton')
    assert(inserted:find('|Hitem:7|h[Herb]',1,true))
    IsShiftKeyDown=function() return false end
    addon.WhisperComposer.frame.Copy.scripts.OnClick()
    assert(addon.WhisperComposer.frame.Edit.highlighted)
    addon.WhisperComposer:Choose(42,'Crafter-Realm')
    assert(#messages==1 and messages[1][2]=='WHISPER' and messages[1][3]=='Crafter-Realm')
    assert(messages[1][1]:find('|Hitem:7',1,true))
    assert(#CraftRosterDB.requests==1)
    addon.WhisperComposer:Choose(42,'Crafter-Realm'); assert(#messages==1)
''',
'composer_retains_edits_and_unknown_targets_cannot_arm_requests': '''
    inventoryFixture(false,true)
    CraftRosterDB.characters['Crafter-Realm']={recipes={[42]={}}}
    local message
    SendChatMessage=function(value) message=value end
    addon.WhisperComposer:Open(42,nil)
    addon.WhisperComposer.frame.Edit:SetText('Please craft my potion using these materials.')
    assert(not addon.WhisperComposer:SendTo('Unknown-Realm') and not CraftRosterDB.requests)
    assert(addon.WhisperComposer:SendTo('Crafter-Realm'))
    assert(message=='Please craft my potion using these materials.')
    addon.WhisperComposer:Open(42,'Crafter-Realm')
    addon.ShoppingList:SetQuantity(42,3)
    assert(not addon.WhisperComposer:SendTo('Crafter-Realm'))
    assert(addon.WhisperComposer.quantity==3)
''',
'composer_defers_quantity_choice_and_respects_cancellation': '''
    inventoryFixture(false,true)
    CraftRosterDB.characters['Crafter-Realm']={recipes={[42]={}}}
    addon.Requests:StartTradeRequest(42,'Crafter-Realm')
    addon.ShoppingList:SetQuantity(42,2)
    local popup,messages= nil,0
    StaticPopup_Show=function(_,_,_,data) popup=data end
    SendChatMessage=function() messages=messages+1 end
    addon.WhisperComposer:Open(42,'Crafter-Realm')
    addon.WhisperComposer:SendTo('Crafter-Realm')
    assert(messages==0 and popup)
    StaticPopupDialogs.CRAFTROSTER_RESUME_TRADE.OnAccept({data=popup})
    assert(messages==0 and addon.WhisperComposer.quantity==1)
    addon.WhisperComposer:SendTo('Crafter-Realm'); assert(messages==1)
    addon.Requests:CancelCurrentRequests(42,'Crafter-Realm')
    assert(not addon.WhisperComposer.queue and not addon.WhisperComposer.pending)
''',
'composer_long_messages_require_explicit_next_click_and_failures_keep_text': r'''
    inventoryFixture(false,true)
    CraftRosterDB.characters['Crafter-Realm']={recipes={[42]={}}}
    addon.WhisperComposer:Open(42,'Crafter-Realm')
    addon.WhisperComposer.frame.Edit:SetText('First message\nSecond message')
    local messages={}
    SendChatMessage=function(text) messages[#messages+1]=text end
    addon.WhisperComposer:SendTo('Crafter-Realm')
    assert(#messages==1 and #addon.WhisperComposer.queue==1)
    addon.WhisperComposer.frame.Send.scripts.OnClick()
    assert(#messages==2 and messages[2]=='Second message')
    addon.WhisperComposer:Open(42,'Crafter-Realm')
    SendChatMessage=function() return false end
    addon.WhisperComposer:SendTo('Crafter-Realm')
    assert(#addon.WhisperComposer.queue>0)
''',
'private_notes_never_enter_public_profile_and_public_notes_clear': '''
    CraftRosterDB.characters['Crafter-Realm']={recipes={},professions={}}
    local before=#sent
    addon.MemberNotes:Save('Crafter-Realm','Private tip: never broadcast',false)
    assert(#sent==before)
    local public,private=addon.MemberNotes:Get('Crafter-Realm')
    assert(public=='' and private=='Private tip: never broadcast')
    addon.MemberNotes:Save('Tester-Realm','Available for tailoring',true)
    flushTimers()
    for i=before+1,#sent do assert(not sent[i][2]:find('Private tip',1,true)) end
    addon.MemberNotes:Save('Tester-Realm','',true)
    assert(CraftRosterDB.characters['Tester-Realm'].note=='')
    assert(not addon.MemberNotes:Save('Crafter-Realm','Cannot change their public note',true))
    assert(#addon.MemberNotes:Clean(string.rep('é',200))<=240)
''',
'source_totals_and_missing_names_do_not_hide_acquisition_data': '''
    CraftRosterDB.recipes[99999]={name='Test',profession='Tailoring',sourceText='Client source'}
    local db={IsReady=function() return true end,GetGameVersion=function() return 'Forever' end,
      GetRecipeSources=function() return {drop={{name='Example boss'},{id=42},total=900}} end,
      GetRequiredSkill=function() return 125 end, IsBorrowed=function() return 'Vanilla' end}
    LibStub=setmetatable({}, {__call=function() return db end})
    local text=addon.RecipeSources:Format(99999)
    assert(text:find('Client source',1,true) and text:find('Example boss',1,true))
    assert(text:find('sources: 900',1,true) and text:find('and 898 more',1,true))
    assert(text:find('Name unavailable',1,true) and text:find('Required skill: 125',1,true))
    assert(text:find('Forever source unconfirmed',1,true) and text:find('Drop chance: unknown',1,true))
''',
'requested_peer_schematic_round_trip_is_targeted_and_local_scan_wins': '''
    if not (C_ChatInfo or SendAddonMessage) then return end
    CraftRosterDB.recipes[42]={name='Potion',profession='Alchemy',professionID=171}
    CraftRosterDB.characters['Crafter-Realm']={professions={},recipes={[42]={materials={{name='Herb',itemID=7,count=3}},outputItemID=99}}}
    assert(addon.GuildDetails:RequestMaterials(42,'Crafter-Realm'))
    local query=sent[#sent][2]
    local old=UnitName
    UnitName=function(unit) return unit=='player' and 'Crafter' or old(unit) end
    dispatch('CHAT_MSG_ADDON','CRDETAILS',query,'GUILD','Tester-Realm')
    flushTimers()
    UnitName=old
    local packets={}
    for _,packet in ipairs(sent) do if packet[1]=='CRDETAILS' and packet[2]:sub(1,2)=='P:' then packets[#packets+1]=packet[2] end end
    for _,packet in ipairs(packets) do dispatch('CHAT_MSG_ADDON','CRDETAILS',packet,'GUILD','Crafter-Realm') end
    local materials=addon.RecipeSources:GetMaterials(42)
    assert(materials[1].itemID==7 and materials[1].count==3)
    assert(CraftRosterDB.recipes[42].peerSchematics['crafter-realm'].source=='Guild crafter scan')
    CraftRosterDB.recipes[42].materials={{name='Local herb',itemID=7,count=4}}
    assert(addon.RecipeSources:GetMaterials(42)[1].count==4)
    for _,packet in ipairs(sent) do assert(#packet[2]<=255) end
''',
'unsolicited_schematic_and_forged_profile_do_not_change_saved_data': '''
    CraftRosterDB.recipes[42]={name='Potion',profession='Alchemy'}
    dispatch('CHAT_MSG_ADDON','CRDETAILS','P:1-1:1:1:S:Tester-Realm:42:99:171:7,3,Herb','GUILD','Other-Realm')
    assert(not CraftRosterDB.recipes[42].peerSchematics)
    dispatch('CHAT_MSG_ADDON','CRDETAILS','P:1-2:1:1:N:Crafter-Realm:Forged note','GUILD','Other-Realm')
    assert(not CraftRosterDB.characters['Crafter-Realm'])
    dispatch('CHAT_MSG_ADDON','CRDETAILS','P:1-3:1:1:N:Crafter-Realm:Actual note','GUILD','Crafter-Realm')
    assert(CraftRosterDB.characters['Crafter-Realm'].note=='Actual note')
''',
}

class GuildFeatureTests(unittest.TestCase): pass
for runtime in ('lua51','luajit21'):
    for profile in ('modern','legacy','minimal'):
        for name,code in CASES.items():
            def check(self,runtime=runtime,profile=profile,code=code): fresh(runtime,profile).execute(code)
            setattr(GuildFeatureTests,f'test_{runtime}_{profile}_{name}',check)
