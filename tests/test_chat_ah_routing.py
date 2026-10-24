"""Shopping-list material clicks must not escape a visible chat editor."""
import unittest
from test_work_orders import fresh

CASES = {
    "active_chat_insert_error_never_searches_ah": """
        local searches=0
        addon.ShoppingList.SearchAuctions=function() searches=searches+1; return true end
        addon.ItemDisplay.Resolve=function(_,id,name) return name,'|Hitem:'..id..'|h['..name..']|h' end
        ChatEdit_GetActiveWindow=function()
            return {Insert=function() error('chat edit box is unavailable') end}
        end
        ChatEdit_InsertLink=function() return false end
        assert(not addon.ItemDisplay:Click({name='Herb',itemID=42}))
        assert(searches==0,'failed chat insertion must not search the AH')
    """,
    "throwing_active_chat_lookup_never_opens_ah": """
        local searches=0
        addon.ShoppingList.SearchAuctions=function() searches=searches+1; return true end
        addon.ItemDisplay.Resolve=function(_,id,name) return name,'|Hitem:'..id..'|h['..name..']|h' end
        ChatEdit_GetActiveWindow=function() error('hybrid chat editor lookup failed') end
        ChatEdit_InsertLink=function() error('should not insert into unknown editor') end
        IsShiftKeyDown=function() return false end
        assert(not addon.ItemDisplay:Click({name='Herb',itemID=42}))
        IsShiftKeyDown=function() return true end
        assert(not addon.ItemDisplay:Click({name='Herb',itemID=42}))
        assert(searches==0,'unknown chat context must not become an AH search')
    """,
    "active_chat_without_insert_never_searches_ah": """
        local searches=0
        addon.ShoppingList.SearchAuctions=function() searches=searches+1; return true end
        addon.ItemDisplay.Resolve=function(_,id,name) return name,'|Hitem:'..id..'|h['..name..']|h' end
        ChatEdit_GetActiveWindow=function() return {} end
        ChatEdit_InsertLink=function() return false end
        assert(not addon.ItemDisplay:Click({name='Herb',itemID=42}))
        assert(searches==0)
    """,
    "active_chat_native_insert_succeeds_without_ah": """
        local searches,inserted=0,nil
        addon.ShoppingList.SearchAuctions=function() searches=searches+1; return true end
        addon.ItemDisplay.Resolve=function(_,id,name) return name,'|Hitem:'..id..'|h['..name..']|h' end
        ChatEdit_GetActiveWindow=function() return {Insert=function(_,link) inserted=link end} end
        ChatEdit_InsertLink=function() return false end
        assert(addon.ItemDisplay:Click({name='Herb',itemID=42}))
        assert(inserted:find('item:42',1,true) and searches==0)
    """,
    "shift_click_chat_failure_never_falls_through_to_ah": """
        local searches=0
        addon.ShoppingList.SearchAuctions=function() searches=searches+1; return true end
        addon.ItemDisplay.Resolve=function(_,id,name) return name,'|Hitem:'..id..'|h['..name..']|h' end
        ChatEdit_GetActiveWindow=function() return nil end
        ChatEdit_InsertLink=function() return false end
        IsShiftKeyDown=function() return true end
        ChatFrame_OpenChat=function() error('chat UI blocked') end
        assert(not addon.ItemDisplay:Click({name='Herb',itemID=42}))
        assert(searches==0,'failed shift-click must not search the Auction House')
        ChatFrame_OpenChat=function() return false end
        assert(not addon.ItemDisplay:Click({name='Herb',itemID=42}))
        assert(searches==0)
    """,
    "shift_click_missing_chat_api_or_item_link_never_searches_ah": """
        local searches=0
        addon.ShoppingList.SearchAuctions=function() searches=searches+1; return true end
        addon.ItemDisplay.Resolve=function(_,id,name) return name,'|Hitem:'..id..'|h['..name..']|h' end
        ChatEdit_GetActiveWindow=function() return nil end
        ChatEdit_InsertLink=nil; ChatFrame_OpenChat=nil
        IsShiftKeyDown=function() return true end
        assert(not addon.ItemDisplay:Click({name='Herb',itemID=42}))
        addon.ItemDisplay.Resolve=function(_,id,name) return name,nil end
        assert(not addon.ItemDisplay:Click({name='Herb'}))
        assert(searches==0)
    """,
    "shift_click_opens_chat_without_searching_ah": """
        local searches,opened=0,nil
        addon.ShoppingList.SearchAuctions=function() searches=searches+1; return true end
        addon.ItemDisplay.Resolve=function(_,id,name) return name,'|Hitem:'..id..'|h['..name..']|h' end
        ChatEdit_GetActiveWindow=function() return nil end
        ChatEdit_InsertLink=function() return false end
        IsShiftKeyDown=function() return true end
        ChatFrame_OpenChat=function(link) opened=link end
        assert(addon.ItemDisplay:Click({name='Herb',itemID=42}))
        assert(opened:find('item:42',1,true) and searches==0)
    """,
    "missing_chat_lookup_never_opens_duplicate_after_failed_shift_insert": """
        local searches,opened=0,0
        addon.ShoppingList.SearchAuctions=function() searches=searches+1; return true end
        addon.ItemDisplay.Resolve=function(_,id,name) return name,'|Hitem:'..id..'|h['..name..']|h' end
        ChatEdit_GetActiveWindow=nil
        ChatEdit_InsertLink=function() return false end
        ChatFrame_OpenChat=function() opened=opened+1 end
        IsShiftKeyDown=function() return true end
        assert(not addon.ItemDisplay:Click({name='Herb',itemID=42}))
        assert(searches==0 and opened==0,
            'unknown chat state must not create a duplicate editor or search the AH')
    """,
    "missing_chat_lookup_keeps_successful_native_shift_insert": """
        local inserted,opened,searches=0,0,0
        addon.ShoppingList.SearchAuctions=function() searches=searches+1; return true end
        addon.ItemDisplay.Resolve=function(_,id,name) return name,'|Hitem:'..id..'|h['..name..']|h' end
        ChatEdit_GetActiveWindow=nil
        ChatEdit_InsertLink=function() inserted=inserted+1; return true end
        ChatFrame_OpenChat=function() opened=opened+1 end
        IsShiftKeyDown=function() return true end
        assert(addon.ItemDisplay:Click({name='Herb',itemID=42}))
        assert(inserted==1 and opened==0 and searches==0)
    """,
    "no_chat_routes_to_ah": """
        local searches=0
        addon.ShoppingList.SearchAuctions=function(_,entry)
            assert(entry.name=='Herb'); searches=searches+1; return true
        end
        addon.ItemDisplay.Resolve=function(_,id,name) return name,'|Hitem:'..id..'|h['..name..']|h' end
        ChatEdit_GetActiveWindow=function() return nil end
        IsShiftKeyDown=function() return false end
        assert(addon.ItemDisplay:Click({name='Herb',itemID=42}))
        assert(searches==1)
    """,

    "uncertain_modern_auction_visibility_does_not_write_stale_legacy": """
        local writes=0
        AuctionHouseFrame=CreateFrame()
        AuctionHouseFrame.IsShown=function() error('modern AH state unavailable') end
        AuctionFrame=CreateFrame(); AuctionFrame:Show()
        BrowseName=CreateFrame()
        BrowseName.SetText=function() writes=writes+1 end
        assert(not addon.ShoppingList:SearchAuctions({name='Herb'}))
        assert(writes==0,'unknown modern AH state must not select stale legacy search')
    """,
    "modern_auction_search_visibility_error_does_not_fall_back": """
        local modernWrites,legacyWrites=0,0
        AuctionHouseFrame=CreateFrame(); AuctionHouseFrame:Show()
        local search=CreateFrame()
        search.IsShown=function() error('modern search tab not ready') end
        search.SetText=function() modernWrites=modernWrites+1 end
        AuctionHouseFrame.SearchBar={SearchBox=search}
        AuctionFrame=CreateFrame(); AuctionFrame:Show()
        BrowseName=CreateFrame()
        BrowseName.SetText=function() legacyWrites=legacyWrites+1 end
        assert(not addon.ShoppingList:SearchAuctions({name='Herb'}))
        assert(modernWrites==0 and legacyWrites==0,
            'unknown modern search visibility must not write to either box')
    """,
    "legacy_auction_search_visibility_error_fails_closed": """
        local writes=0
        AuctionHouseFrame=nil
        AuctionFrame=CreateFrame(); AuctionFrame:Show()
        BrowseName=CreateFrame()
        BrowseName.IsShown=function() error('legacy browse tab unavailable') end
        BrowseName.SetText=function() writes=writes+1 end
        assert(not addon.ShoppingList:SearchAuctions({name='Herb'}))
        assert(writes==0,'unknown legacy search visibility must not write')
    """,
    "visible_modern_auction_ignores_broken_legacy_visibility": """
        local modernWrites,legacyWrites=0,0
        AuctionHouseFrame=CreateFrame(); AuctionHouseFrame:Show()
        local search=CreateFrame(); search:Show()
        search.SetText=function(_,value) assert(value=='Herb'); modernWrites=modernWrites+1 end
        AuctionHouseFrame.SearchBar={SearchBox=search}
        AuctionFrame=CreateFrame()
        AuctionFrame.IsShown=function() error('stale legacy frame') end
        BrowseName=CreateFrame()
        BrowseName.SetText=function() legacyWrites=legacyWrites+1 end
        assert(addon.ShoppingList:SearchAuctions({name='Herb'}))
        assert(modernWrites==1 and legacyWrites==0,
            'a visible modern AH must remain usable despite stale legacy frames')
    """,
}
class ChatAuctionRoutingTests(unittest.TestCase):
    pass

for runtime in ("lua51", "luajit21"):
    for profile in ("modern", "legacy", "minimal"):
        for name, code in CASES.items():
            def check(self, runtime=runtime, profile=profile, code=code):
                lua=fresh(runtime, profile)
                lua.execute(code)
            setattr(ChatAuctionRoutingTests, f"test_{runtime}_{profile}_{name}", check)
