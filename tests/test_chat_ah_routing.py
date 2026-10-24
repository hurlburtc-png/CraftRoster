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
