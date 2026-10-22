"""Personal bank snapshots, event coalescing and bag-only delivery readiness."""
import unittest
from test_work_orders import fresh

SETUP = '''
inventoryFixture(false,true)
inventory[1].count=2; inventory[2].count=0
bankItems={[-1]={[1]={id=7,count=4,name='Herb'}},[5]={[1]={id=7,count=3,name='Herb'}}}
bankAccessible=false; bankSlotCalls=0; bankInfoCalls=0
local api=C_Container or _G
local bagSlots=api.GetContainerNumSlots
local bagInfo=api.GetContainerItemInfo
local bagLink=api.GetContainerItemLink
api.GetContainerNumSlots=function(bag)
 if bag>=0 and bag<=4 then return bagSlots(bag) end
 bankSlotCalls=bankSlotCalls+1
 if not bankAccessible then error('closed bank must not be read') end
 return bag==-1 and 96 or (bag==5 and 4 or 0)
end
api.GetContainerItemLink=function(bag,slot)
 if bag>=0 and bag<=4 then return bagLink(bag,slot) end
 local item=bankItems[bag] and bankItems[bag][slot]
 return item and ('|Hitem:%d|h[%s]|h'):format(item.id,item.name)
end
api.GetContainerItemInfo=function(bag,slot)
 if bag>=0 and bag<=4 then return bagInfo(bag,slot) end
 bankInfoCalls=bankInfoCalls+1
 local item=bankItems[bag] and bankItems[bag][slot]
 if not item then return nil end
 if apiProfile=='modern' then return {itemID=item.id,stackCount=item.count} end
 return 'icon',item.count,false
end
function openBank() bankAccessible=true; dispatch('BANKFRAME_OPENED'); flushTimers() end
function closeBank() bankAccessible=false; dispatch('BANKFRAME_CLOSED'); flushTimers() end
addon.ShoppingList:SetQuantity(42,4)
'''

CASES = {
'unvisited_bank_is_unknown_not_zero': '''
 local entries=addon.ShoppingList:GetMaterialStatus(42)
 assert(entries[1].owned==2 and entries[1].bank==nil)
 assert(entries[1].missing==nil and entries[1].withdraw==nil)
 assert(addon.ShoppingList:BankSummary(entries[1]):find('visit bank',1,true))
 assert(bankSlotCalls==0 and bankInfoCalls==0)
''',
'bank_and_bags_are_separate_and_persist_when_closed': '''
 openBank()
 local entries,ready=addon.ShoppingList:GetMaterialStatus(42)
 local e=entries[1]
 assert(e.bank==7 and e.owned==2 and e.required==12)
 assert(e.totalOwned==9 and e.withdraw==7 and e.missing==3 and ready==0)
 assert(addon.BankMaterials:GetCount('Herb')==7)
 assert(addon.BankMaterials:GetCount(999)==0)
 local snapshot=CraftRosterDB.characters['Tester-Realm'].bankMaterials
 assert(snapshot.scannedAt==time() and snapshot.counts[7]==7)
 closeBank()
 bankSlotCalls=0
 for i=1,20 do dispatch('BAG_UPDATE',0) end
 flushTimers()
 assert(bankSlotCalls==0 and addon.BankMaterials:GetCount(7)==7)
 entries=addon.ShoppingList:GetMaterialStatus(42)
 assert(entries[1].bankScannedAt==snapshot.scannedAt)
''',
'empty_bank_is_known_and_deposit_withdraw_events_refresh': '''
 openBank()
 inventory[1].count=1; bankItems[-1][1].count=5
 dispatch('PLAYERBANKSLOTS_CHANGED',1); flushTimers()
 local e=addon.ShoppingList:GetMaterialStatus(42)[1]
 assert(e.owned==1 and e.bank==8 and e.totalOwned==9)
 inventory[1].count=6; bankItems[-1][1]=nil; bankItems[5][1]={id=7,count=3,name='Herb'}
 dispatch('BAG_UPDATE',5); flushTimers()
 e=addon.ShoppingList:GetMaterialStatus(42)[1]
 assert(e.owned==6 and e.bank==3 and e.totalOwned==9 and e.withdraw==3 and e.missing==3)
 bankItems={}; dispatch('PLAYERBANKSLOTS_CHANGED',1); flushTimers()
 assert(addon.BankMaterials:GetCount(7)==0)
''',
'immediate_close_never_double_counts_pending_mutation': '''
 if not C_Timer then return end
 openBank()
 local old=addon.BankMaterials:Snapshot()
 inventory[1].count=9; bankItems={}
 dispatch('PLAYERBANKSLOTS_CHANGED',1); dispatch('BAG_UPDATE',0)
 closeBank()
 local e=addon.ShoppingList:GetMaterialStatus(42)[1]
 assert(e.owned==9 and e.bank==nil and e.totalOwned==nil and e.missing==nil)
 assert(old.counts[7]==7 and old.dirty,'retain the last snapshot, but never spend it twice')
 assert(addon.ShoppingList:BankSummary(e):find('reopen',1,true))
 openBank()
 e=addon.ShoppingList:GetMaterialStatus(42)[1]
 assert(e.bank==0 and e.totalOwned==9 and e.missing==3)
''',
'partial_scan_keeps_previous_snapshot_unverified': '''
 addon.Directory:Toggle()
 addon.Directory.selectedRecipe={id=42,name='Potion',profession='Alchemy',crafters={}}
 addon.Directory:RefreshDetails()
 openBank()
	assert(addon.SelectedCraft.entries[1].bank==7)
 local old=addon.BankMaterials:Snapshot()
 local api=C_Container or _G
 local original=api.GetContainerItemInfo
 api.GetContainerItemInfo=function(bag,slot)
  if bag<0 or bag>4 then error('data not ready') end
  return original(bag,slot)
 end
 dispatch('PLAYERBANKSLOTS_CHANGED',1); flushTimers()
 assert(addon.BankMaterials:Snapshot()==old and old.counts[7]==7)
 assert(addon.BankMaterials:GetCount(7)==nil and old.dirty)
 assert(addon.SelectedCraft.entries[1].bank==nil,'failed scans must invalidate visible rows too')
 closeBank()
 assert(old.counts[7]==7)
''',
'scans_are_bounded_coalesced_and_ignore_carried_bag_events': '''
 openBank()
 assert(bankSlotCalls==9,'one scan on opening, no redundant delayed scan')
 bankSlotCalls=0; bankInfoCalls=0
 for i=1,20 do dispatch('BAG_UPDATE',0); dispatch('BAG_UPDATE_DELAYED') end
 flushTimers(); assert(bankSlotCalls==0)
 for i=1,20 do dispatch('PLAYERBANKSLOTS_CHANGED',1) end
 if C_Timer then assert(bankSlotCalls==0) end
 flushTimers()
 assert(bankSlotCalls==(C_Timer and 9 or 180))
 assert(bankInfoCalls==(C_Timer and 100 or 2000))
 closeBank(); bankSlotCalls=0
 dispatch('PLAYERBANKSLOTS_CHANGED',1); flushTimers()
 assert(bankSlotCalls==0)
''',
'snapshot_is_character_specific_and_bank_does_not_mark_ready': '''
 openBank()
 bankItems[-1][1].count=30; dispatch('PLAYERBANKSLOTS_CHANGED',1); flushTimers()
 local e,ready=addon.ShoppingList:GetMaterialStatus(42)
 assert(e[1].bank==33 and e[1].missing==0 and ready==0)
 closeBank()
 local oldName=UnitName
 UnitName=function() return 'Alt' end
 CraftRosterDB.characters['Alt-Realm']={recipes={}}
 assert(addon.BankMaterials:GetCount(7)==nil)
 UnitName=oldName
 assert(addon.BankMaterials:GetCount(7)==33)
 assert(moved==0 and #sent==0)
''',
'saved_snapshot_and_contributions_use_remaining_share': '''
 CraftRosterDB.characters['Tester-Realm'].bankMaterials={counts={[7]=5,Herb=5},scannedAt=12345}
 assert(addon.BankMaterials:GetCount(7)==5 and bankSlotCalls==0)
 assert(addon.ShoppingList:SetCrafterShare(42,'Crafter-Realm',7,4))
 local e=addon.ShoppingList:GetMaterialStatus(42,'Crafter-Realm')[1]
 assert(e.recipeRequired==12 and e.required==8 and e.crafterProvides==4)
 assert(e.owned==2 and e.bank==5 and e.withdraw==5 and e.missing==1)
 assert(e.bankScannedAt==12345)
''',
'main_and_shopping_refresh_without_bank_window_remaining_open': '''
 addon.Directory:Toggle()
 addon.Directory.selectedRecipe={id=42,name='Potion',profession='Alchemy',crafters={}}
 addon.Directory:RefreshDetails(); addon.ShoppingList:Open(42)
 assert(addon.SelectedCraft.entries[1].bank==nil)
 openBank(); flushTimers()
 assert(addon.SelectedCraft.entries[1].bank==7 and addon.ShoppingList.entries[1].bank==7)
 assert(addon.ShoppingList.frame.Summary:GetText()=='0 of 1 materials ready in bags')
 closeBank()
 inventory[1].count=4; dispatch('BAG_UPDATE',0); flushTimers()
 assert(addon.SelectedCraft.entries[1].owned==4 and addon.SelectedCraft.entries[1].bank==7)
 local rows=addon.ShoppingList.frame.Rows
 assert(rows[1]:GetText():find('Bank: 7',1,true))
''',
}

class BankMaterialTests(unittest.TestCase):
    pass

for runtime in ('lua51', 'luajit21'):
    for profile in ('modern', 'legacy', 'minimal'):
        for name, code in CASES.items():
            def check(self, runtime=runtime, profile=profile, code=code):
                lua = fresh(runtime, profile)
                lua.execute(SETUP)
                lua.execute(code)
            setattr(BankMaterialTests, f'test_{runtime}_{profile}_{name}', check)
