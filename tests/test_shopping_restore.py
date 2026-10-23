"""Saved shopping windows must not reopen removed recipe records."""
import unittest
from test_work_orders import fresh

CASES = {
    "restore_discards_removed_recipe": """
        CraftRosterDB.recipes[42]={name='Old recipe',materials={{name='Herb',count=2}}}
        addon.ShoppingList:Open(42)
        local state=CraftRosterDB.characters['Tester-Realm'].shoppingList
        assert(state.visible and state.recipeID==42)
        addon.ShoppingList:Close()
        state.visible=true; state.crafter='Crafter-Realm'
        CraftRosterDB.recipes[42]=nil
        addon.ShoppingList:Restore()
        assert(state.recipeID==nil and state.crafter==nil and not state.visible)
        assert(not addon.ShoppingList.frame:IsShown())
    """,
    "restore_keeps_valid_recipe": """
        CraftRosterDB.recipes[42]={name='Current recipe',materials={{name='Herb',count=2}}}
        addon.ShoppingList:Open(42)
        addon.ShoppingList:Close()
        local state=CraftRosterDB.characters['Tester-Realm'].shoppingList
        state.visible=true
        addon.ShoppingList:Restore()
        assert(addon.ShoppingList.frame:IsShown() and state.recipeID==42 and state.visible)
    """,
}
class ShoppingRestoreTests(unittest.TestCase):
    pass

for runtime in ("lua51", "luajit21"):
    for profile in ("modern", "legacy", "minimal"):
        for name, code in CASES.items():
            def check(self, runtime=runtime, profile=profile, code=code):
                lua=fresh(runtime, profile)
                lua.execute(code)
            setattr(ShoppingRestoreTests, f"test_{runtime}_{profile}_{name}", check)
