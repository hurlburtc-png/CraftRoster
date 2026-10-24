"""Selected-recipe hyperlinks must not open a second chat editor after an API failure."""
import unittest
from test_work_orders import fresh

SETUP = """
    inventoryFixture(false,true)
    CraftRosterDB.recipes[42].profession='Alchemy'
    addon.Directory:Toggle()
    addon.Directory.selectedRecipe={id=42,name='Potion',profession='Alchemy',crafters={}}
    addon.Directory:RefreshDetails()
    addon.Directory.GetSearchLinks=function()
        return {craft='|Hitem:99|h[Craft]|h',recipe='|Hitem:100|h[Pattern]|h'}
    end
    IsShiftKeyDown=function() return true end
"""

CASES = {
    'throwing_chat_lookup_after_failed_insert_never_opens_duplicate': """
        local attempted,opened=0,0
        ChatEdit_InsertLink=function() attempted=attempted+1;return false end
        ChatEdit_GetActiveWindow=function() error('hybrid chat lookup failed') end
        ChatFrame_OpenChat=function() opened=opened+1 end
        local tab=addon.Directory.frame.ProfessionsTab
        tab.CraftItemHover.scripts.OnClick(tab.CraftItemHover,'LeftButton')
        addon.SelectedCraft.recipeButton.scripts.OnClick(addon.SelectedCraft.recipeButton,'LeftButton')
        assert(attempted==2 and opened==0,'unknown active editor must never be replaced')
    """,
    'throwing_chat_lookup_and_insert_never_opens_duplicate': """
        local opened=0
        ChatEdit_InsertLink=function() error('chat insert failed') end
        ChatEdit_GetActiveWindow=function() error('chat lookup failed') end
        ChatFrame_OpenChat=function() opened=opened+1 end
        local tab=addon.Directory.frame.ProfessionsTab
        tab.CraftItemHover.scripts.OnClick(tab.CraftItemHover,'LeftButton')
        addon.SelectedCraft.recipeButton.scripts.OnClick(addon.SelectedCraft.recipeButton,'LeftButton')
        assert(opened==0,'two failed chat APIs must not create another editor')
    """,
    'successful_chat_insert_never_queries_or_opens_another_editor': """
        local attempted,opened,lookups=0,0,0
        ChatEdit_InsertLink=function() attempted=attempted+1;return true end
        ChatEdit_GetActiveWindow=function() lookups=lookups+1;error('unavailable') end
        ChatFrame_OpenChat=function() opened=opened+1 end
        local tab=addon.Directory.frame.ProfessionsTab
        tab.CraftItemHover.scripts.OnClick(tab.CraftItemHover,'LeftButton')
        addon.SelectedCraft.recipeButton.scripts.OnClick(addon.SelectedCraft.recipeButton,'LeftButton')
        assert(attempted==2 and lookups==0 and opened==0,'successful inserts need no fallback')
    """,
}

class SelectedRecipeChatSafetyTests(unittest.TestCase):
    pass

for runtime in ('lua51', 'luajit21'):
    for profile in ('modern', 'legacy', 'minimal'):
        for name, code in CASES.items():
            def check(self, runtime=runtime, profile=profile, code=code):
                lua=fresh(runtime,profile)
                lua.execute(SETUP)
                lua.execute(code)
            setattr(SelectedRecipeChatSafetyTests, f'test_{runtime}_{profile}_{name}', check)
