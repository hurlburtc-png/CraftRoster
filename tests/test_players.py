import importlib
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class PlayerRecipesTests(unittest.TestCase):
    def test_expand_collapse_and_open_recipe(self):
        for runtime in ('lua51', 'luajit21'):
            with self.subTest(runtime=runtime):
                lua = importlib.import_module('lupa.' + runtime).LuaRuntime(unpack_returned_tuples=True)
                lua.execute((ROOT / 'tests/wow_mock.lua').read_text())
                lua.globals().configure('legacy')
                lua.execute((ROOT / 'tests/layout_mock.lua').read_text())
                addon = lua.table()
                lua.globals().addon = addon
                for name in (ROOT / 'CraftRoster.toc').read_text().splitlines():
                    if name.endswith('.lua'):
                        lua.compile((ROOT / name).read_text(), name=name)('CraftRoster', addon)
                lua.execute("dispatch('ADDON_LOADED','CraftRoster')")
                lua.execute('''
                    inventoryFixture(false,true)
                    CraftRosterDB.characters['Crafter-Realm']={recipes={[42]={}}}
                    SlashCmdList.CRAFTROSTER('')
                    local d=addon.Directory
                    d:ShowTab(2)
                    local function rowFor(key,id)
                        for _,row in ipairs(frames) do
                            if row.parent==d.frame.PlayersTab.ResultsChild and row:IsShown()
                                and row.listEntry and row.listEntry.key==key and row.listEntry.id==id then return row end
                        end
                    end
                    local player=rowFor('Crafter-Realm',nil)
                    assert(player)
                    player.scripts.OnMouseUp(player,'LeftButton')
                    assert(d.expandedPlayers['Crafter-Realm'])
                    assert(rowFor(nil,42))
                    player=rowFor('Crafter-Realm',nil)
                    player.scripts.OnMouseUp(player,'LeftButton')
                    assert(not d.expandedPlayers['Crafter-Realm'])
                    assert(not rowFor(nil,42))
                    player=rowFor('Crafter-Realm',nil)
                    player.scripts.OnMouseUp(player,'LeftButton')
                    local recipe=rowFor(nil,42)
                    d.selectedProfession='Enchanting'
                    CraftRosterDB.settings.favoritesOnly=true
                    recipe.scripts.OnMouseUp(recipe,'LeftButton')
                    assert(d.activeTab==1 and d.selectedRecipe.id==42)
                    assert(d.selectedProfession=='All' and not CraftRosterDB.settings.favoritesOnly)
                ''')
