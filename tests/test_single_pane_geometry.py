"""Mock anchor regression coverage for selected-recipe 3/6/10-material layouts.

This checks geometry and scroll bounds, not rendered fonts or Forever 1.60.1.
"""
import importlib
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class SinglePaneGeometryTests(unittest.TestCase):
    def test_material_rows_and_source_do_not_overlap(self):
        for runtime in ('lua51', 'luajit21'):
            for profile in ('modern', 'legacy', 'minimal'):
                with self.subTest(runtime=runtime, profile=profile):
                    lua = importlib.import_module('lupa.' + runtime).LuaRuntime(
                        unpack_returned_tuples=True)
                    lua.execute((ROOT / 'tests/wow_mock.lua').read_text())
                    lua.globals().configure(profile)
                    lua.execute((ROOT / 'tests/layout_mock.lua').read_text())
                    addon = lua.table()
                    lua.globals().addon = addon
                    for name in (ROOT / 'CraftRoster.toc').read_text().splitlines():
                        if name.endswith('.lua'):
                            lua.compile((ROOT / name).read_text(), name=name)(
                                'CraftRoster', addon)
                    lua.execute("dispatch('ADDON_LOADED','CraftRoster')")
                    lua.execute("""
                        inventoryFixture(false,true)
                        CraftRosterDB.recipes[42].profession='Alchemy'
                        addon.Directory:Toggle()
                        addon.Directory.selectedRecipe={
                            id=42,name='Potion',profession='Alchemy',crafters={}}
                        local view=addon.SelectedCraft
                        local tab=addon.Directory.frame.ProfessionsTab
                        local original=addon.ShoppingList.GetMaterialStatus
                        for _,width in ipairs({320,399,400,436,600}) do
                            tab.SelectedCraftScroll:SetWidth(width)
                            for _,count in ipairs({3,6,10}) do
                                addon.ShoppingList.GetMaterialStatus=function()
                                    local entries={}
                                    for i=1,count do
                                        entries[i]={name='Material '..i,itemID=7,
                                            icon='icon',owned=1,required=2,
                                            recipeRequired=2,delivered=0,crafterProvides=0}
                                    end
                                    return entries
                                end
                                view:Refresh()
                                assert(#view.entries==count)
                                inside(tab.RecipeSource,tab.Details)
                                for i=1,count do
                                    local row=view.rows[i]
                                    assert(row:IsShown() and row:GetHeight()==32)
                                    inside(row,tab.Details)
                                    apart(row,tab.RecipeSource)
                                    if i>1 then apart(view.rows[i-1],row) end
                                end
                                for i=count+1,#view.rows do
                                    assert(not view.rows[i]:IsShown())
                                end
                                inside(tab.Details,tab.SelectedCraftContent)
                                apart(tab.Details,tab.CrafterList)
                                local maxScroll=math.max(0,
                                    tab.SelectedCraftContent:GetHeight()
                                    -tab.SelectedCraftScroll:GetHeight())
                                assert(tab.SelectedCraftScroll:GetVerticalScroll()<=maxScroll)
                            end
                        end
                        addon.ShoppingList.GetMaterialStatus=original
                    """)


if __name__ == '__main__':
    unittest.main()
