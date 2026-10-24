"""Only explicitly opened CraftRoster mail becomes a persistent crafter work order."""
import importlib
from pathlib import Path
import unittest

ROOT=Path(__file__).resolve().parents[1]

def fresh(runtime='lua51',profile='modern'):
    lua=importlib.import_module('lupa.'+runtime).LuaRuntime(unpack_returned_tuples=True)
    lua.execute((ROOT/'tests/wow_mock.lua').read_text()); lua.globals().configure(profile)
    addon=lua.table(); lua.globals().addon=addon
    paths=[name for name in (ROOT/'CraftRoster.toc').read_text().splitlines() if name.endswith('.lua')]
    if 'MailOrders.lua' not in paths: paths.append('MailOrders.lua')
    for name in paths: lua.compile((ROOT/name).read_text(),name=name)('CraftRoster',addon)
    lua.execute("""
        dispatch('ADDON_LOADED','CraftRoster')
        CraftRosterDB.recipes[42]={name='Spidersilk Boots',profession='Tailoring',itemLink='item:4320'}
        CraftRosterDB.characters['Tester-Realm'].recipes[42]={}
        inbox={}
        reads=0
        function GetInboxHeaderInfo(index)
          local mail=inbox[index]
          if mail then return 'package','stationery',mail.sender,mail.subject end
        end
        function GetInboxText(index) reads=reads+1; return inbox[index] and inbox[index].body end
        OpenMailFrame=CreateFrame(); OpenMailFrame:Hide()
        InboxFrame=CreateFrame(); InboxFrame.openMailID=0
        function opened(index)
          InboxFrame.openMailID=index; OpenMailFrame:Show()
          if OpenMailFrame.scripts.OnShow then OpenMailFrame.scripts.OnShow(OpenMailFrame) end
        end
        function hooksecurefunc(name,post)
          local original=_G[name]
          _G[name]=function(...)
            local body=original(...); post(...); return body
          end
        end
        addon.MailOrders:InstallHooks()
        function CraftRecipe() error('reading mail must never craft') end
        function DoTradeSkill() error('reading mail must never craft') end
        function TakeInboxItem() error('reading mail must never loot') end
        function SendMail() error('reading mail must never send') end
    """)
    return lua

CASES={
'open_craft_mail_creates_single_order_with_quantity': r"""
    inbox[1]={sender='Crafter-Realm',subject='3 crafts of Spidersilk Boots craft requested',body='Hi!\nRequested item: Spidersilk Boots\nNumber of crafts: 3\nMaterials needed (total):\n12 x Medium Leather'}
    assert(#addon.WorkOrders:GetOrders()==0)
    opened(1)
    local order=addon.WorkOrders:GetOrders()[1]
    assert(order.recipeID==42 and order.quantity==3 and order.customer=='Crafter-Realm')
    assert(order.sources.mail and order.requestID==nil and order.status=='requested' and order.done==0)
    assert(#sent==0)
""",
'no_capture_from_background_scan_or_unopened_inbox_update': r"""
    inbox[1]={sender='Crafter-Realm',subject='Spidersilk Boots craft requested',body='Requested item: Spidersilk Boots'}
    GetInboxText(1); dispatch('MAIL_INBOX_UPDATE'); dispatch('MAIL_SHOW')
    assert(#addon.WorkOrders:GetOrders()==0)
    inbox[2]={sender='Other-Realm',subject='Spidersilk Boots craft requested',body='Requested item: Spidersilk Boots'}
    opened(1); GetInboxText(2)
    assert(#addon.WorkOrders:GetOrders()==1)
""",
'reopening_reading_and_reindexed_mail_deduplicate': r"""
    inbox[1]={sender='Crafter-Realm',subject='Spidersilk Boots craft requested',body='Requested item: Spidersilk Boots\nNumber of crafts: 1'}
    opened(1)
    GetInboxText(1); dispatch('MAIL_INBOX_UPDATE'); opened(1)
    assert(#addon.WorkOrders:GetOrders()==1)
    inbox[2]=inbox[1]; opened(2)
    assert(#addon.WorkOrders:GetOrders()==1)
    addon.WorkOrders:OneDone(1); opened(2)
    assert(#addon.WorkOrders:GetOrders()==0)
""",
'different_senders_and_distinct_bodies_remain_distinct': r"""
    inbox[1]={sender='Crafter-Realm',subject='Spidersilk Boots craft requested',body='Requested item: Spidersilk Boots'}
    inbox[2]={sender='Crafter-OtherRealm',subject='Spidersilk Boots craft requested',body='Requested item: Spidersilk Boots'}
    inbox[3]={sender='Crafter-Realm',subject='Spidersilk Boots craft requested',body='Requested item: Spidersilk Boots\nSecond order please.'}
    opened(1); opened(2); opened(3)
    assert(#addon.WorkOrders:GetOrders()==3)
""",
'ordinary_malformed_and_conflicting_mail_never_becomes_orders': r"""
    local bodies={
      {subject='Hello',body='Requested item: Spidersilk Boots'},
      {subject='Spidersilk Boots craft requested',body='Number of crafts: 0'},
      {subject='Spidersilk Boots craft requested',body='Number of crafts: 1.5'},
      {subject='Spidersilk Boots craft requested',body='Number of crafts: 1000'},
      {subject='Spidersilk Boots craft requested',body='Number of crafts: nope'},
      {subject='3 crafts of Spidersilk Boots craft requested',body='Number of crafts: 2'},
      {subject='Spidersilk Boots craft requested',body='Requested item: Chest Enchant'},
      {subject='Spidersilk Boots craft requested',body='Requested item: Spidersilk Boots\nRequested item: Other'},
    }
    for i,mail in ipairs(bodies) do mail.sender='Crafter-Realm'; inbox[i]=mail; opened(i) end
    assert(#addon.WorkOrders:GetOrders()==0)
""",
'unknown_and_ambiguous_recipes_require_manual_addition': r"""
    inbox[1]={sender='Crafter-Realm',subject='Unknown thing craft requested',body='Requested item: Unknown thing'}
    opened(1); assert(#addon.WorkOrders:GetOrders()==0)
    CraftRosterDB.recipes[43]={name='Spidersilk Boots',profession='Tailoring'}
    CraftRosterDB.characters['Tester-Realm'].recipes[43]={}
    inbox[2]={sender='Crafter-Realm',subject='Spidersilk Boots craft requested',body='Requested item: Spidersilk Boots'}
    opened(2); assert(#addon.WorkOrders:GetOrders()==0)
""",
'unlearned_catalog_order_can_be_recorded_but_not_crafted': r"""
    CraftRosterDB.characters['Tester-Realm'].recipes[42]=nil
    inbox[1]={sender='Crafter-Realm',subject='Spidersilk Boots craft requested',body='Requested item: Spidersilk Boots'}
    opened(1); local order=addon.WorkOrders:GetOrders()[1]
    assert(order.recipeID==42 and not addon.WorkOrders:Craft(order.id))
""",
'body_full_name_handles_generated_truncated_subject': r"""
    inbox[1]={sender='Crafter-Realm',subject='Spidersilk Boo craft requested',body='Requested item: Spidersilk Boots\nNumber of crafts: 2'}
    opened(1); assert(addon.WorkOrders:GetOrders()[1].quantity==2)
""",
'late_body_loading_captures_only_visible_current_mail': r"""
    inbox[1]={sender='Crafter-Realm',subject='Spidersilk Boots craft requested'}
    opened(1); assert(#addon.WorkOrders:GetOrders()==0)
    inbox[1].body='Requested item: Spidersilk Boots'
    dispatch('MAIL_INBOX_UPDATE'); assert(#addon.WorkOrders:GetOrders()==1)
    inbox[2]={sender='Other-Realm',subject='Spidersilk Boots craft requested',body='Requested item: Spidersilk Boots'}
    OpenMailFrame:Hide(); InboxFrame.openMailID=2
    dispatch('MAIL_INBOX_UPDATE'); assert(#addon.WorkOrders:GetOrders()==1)
""",
'existing_manual_order_and_disabled_mail_are_preserved': r"""
    addon.WorkOrders:Add('Crafter-Realm',42,1,nil,'manual')
    inbox[1]={sender='Crafter-Realm',subject='Spidersilk Boots craft requested',body='Requested item: Spidersilk Boots'}
    CraftRosterDB.settings.enabled=false; opened(1); assert(#addon.WorkOrders:GetOrders()==1)
    CraftRosterDB.settings.enabled=true; GetInboxText(1); assert(#addon.WorkOrders:GetOrders()==2)
""",
'no_secure_hook_api_still_handles_reader_show': r"""
    hooksecurefunc=nil
    OpenMailFrame=CreateFrame(); OpenMailFrame:Hide()
    addon.MailOrders:InstallHooks()
    inbox[1]={sender='Crafter-Realm',subject='Spidersilk Boots craft requested',body='Requested item: Spidersilk Boots'}
    opened(1); assert(#addon.WorkOrders:GetOrders()==1)
""",
'receipt_cap_refuses_import_without_forgetting_old_receipts': r"""
    local receipts={}
    for i=1,1000 do receipts['old'..i]={signature='old mail '..i,orderID=i} end
    CraftRosterDB.mailOrderReceipts={['tester-realm']=receipts}
    inbox[1]={sender='Crafter-Realm',subject='Spidersilk Boots craft requested',body='Requested item: Spidersilk Boots'}
    opened(1)
    assert(#addon.WorkOrders:GetOrders()==0)
    local count=0; for _ in pairs(CraftRosterDB.mailOrderReceipts['tester-realm']) do count=count+1 end
    assert(count==1000)
""",
'signature_byte_budget_blocks_new_import_without_pruning_receipts': r"""
    local old={signature=string.rep('x',1024*1024-10),orderID=999}
    CraftRosterDB.mailOrderReceipts={['tester-realm']={old=old}}
    local messages={}
    function print(message) table.insert(messages,message) end
    inbox[1]={sender='Crafter-Realm',subject='Spidersilk Boots craft requested',body='Requested item: Spidersilk Boots'}
    opened(1)
    assert(#addon.WorkOrders:GetOrders()==0)
    assert(CraftRosterDB.mailOrderReceipts['tester-realm'].old==old)
    assert(#messages==1 and messages[1]:find('storage limit',1,true) and messages[1]:find('manually',1,true))
""",
'short_receipts_import_under_byte_budget': r"""
    CraftRosterDB.mailOrderReceipts={['tester-realm']={old={signature=string.rep('x',1024),orderID=999}}}
    inbox[1]={sender='Crafter-Realm',subject='Spidersilk Boots craft requested',body='Requested item: Spidersilk Boots'}
    opened(1)
    assert(#addon.WorkOrders:GetOrders()==1)
""",
'mail_import_feedback_is_visible_for_unrecognized_recipe': r"""
    local messages={}
    function print(message) table.insert(messages,message) end
    inbox[1]={sender='Crafter-Realm',subject='Unrecognized craft requested',body='Requested item: Unrecognized'}
    opened(1)
    assert(#messages==1 and messages[1]:find('manually',1,true))
    opened(1); assert(#messages==1)
""",
'visible_reader_uses_valid_open_mail_index_when_inbox_index_is_invalid': r"""
    OpenMailFrame:Show()
    for i,bad in ipairs({0,-1,'stale',1.5}) do
        inbox[i]={sender='Crafter'..i..'-Realm',subject='Spidersilk Boots craft requested',
            body='Requested item: Spidersilk Boots'}
        InboxFrame.openMailID=bad
        OpenMailFrame.openMailID=i
        addon.MailOrders:CaptureOpened()
        assert(#addon.WorkOrders:GetOrders()==i,
            'visible reader ID must be used when inbox index is invalid')
    end
    OpenMailFrame:Hide()
    InboxFrame.openMailID=0
    OpenMailFrame.openMailID=5
    inbox[5]={sender='Crafter5-Realm',subject='Spidersilk Boots craft requested',
        body='Requested item: Spidersilk Boots'}
    addon.MailOrders:CaptureOpened()
    assert(#addon.WorkOrders:GetOrders()==4,
        'hidden reader must never import mail')
""",
'opened_reader_fallback_index_and_bare_sender': r"""
    InboxFrame=nil; OpenMailFrame.openMailID=1
    inbox[1]={sender='Crafter',subject='Spidersilk Boots craft requested',body='Requested item: Spidersilk Boots'}
    OpenMailFrame:Show(); addon.MailOrders:CaptureOpened()
    assert(#addon.WorkOrders:GetOrders('Crafter-Realm')==1)
""",
}

class MailOrderTests(unittest.TestCase): pass
for runtime in ('lua51','luajit21'):
    for profile in ('modern','legacy','minimal'):
        for name,code in CASES.items():
            def check(self,runtime=runtime,profile=profile,code=code): fresh(runtime,profile).execute(code)
            setattr(MailOrderTests,f'test_{runtime}_{profile}_{name}',check)

class MailOrderPersistenceTests(unittest.TestCase):
    def test_receipts_survive_fresh_runtime_without_duplicate_orders(self):
        for runtime in ('lua51','luajit21'):
            first=fresh(runtime)
            first.execute("inbox[1]={sender='Crafter-Realm',subject='Spidersilk Boots craft requested',body='Requested item: Spidersilk Boots'}; opened(1)")
            def plain(value):
                return {plain(k):plain(v) for k,v in value.items()} if hasattr(value,'items') else value
            receipts=plain(first.globals().CraftRosterDB.mailOrderReceipts)
            second=fresh(runtime)
            def table(value): return second.table_from({k:table(v) for k,v in value.items()}) if isinstance(value,dict) else value
            second.globals().CraftRosterDB.mailOrderReceipts=table(receipts)
            second.execute("inbox[1]={sender='Crafter-Realm',subject='Spidersilk Boots craft requested',body='Requested item: Spidersilk Boots'}; opened(1); assert(#addon.WorkOrders:GetOrders()==0)")

if __name__=='__main__': unittest.main()
