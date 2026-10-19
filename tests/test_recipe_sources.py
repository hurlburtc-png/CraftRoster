"""Catalogue ownership, acquisition fallback and source-pane interactions."""
import importlib
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class RecipeSourceTests(unittest.TestCase):
    def fresh(self, runtime, profile):
        lua = importlib.import_module('lupa.' + runtime).LuaRuntime(unpack_returned_tuples=True)
        lua.execute((ROOT / 'tests/wow_mock.lua').read_text())
        lua.globals().configure(profile)
        lua.execute((ROOT / 'tests/layout_mock.lua').read_text())
        addon = lua.table()
        lua.globals().addon = addon
        for name in (ROOT / 'CraftRoster.toc').read_text().splitlines():
            if name.endswith('.lua'):
                lua.compile((ROOT / name).read_text(), name=name)('CraftRoster', addon)
        lua.execute("dispatch('ADDON_LOADED','CraftRoster')")
        return lua

    def test_unlearned_catalogue_source_and_link_do_not_claim_ownership(self):
        for runtime in ('lua51', 'luajit21'):
            for profile in ('modern', 'legacy', 'minimal'):
                with self.subTest(runtime=runtime, profile=profile):
                    lua = self.fresh(runtime, profile)
                    lua.execute('''
                        C_TradeSkillUI={
                          GetBaseProfessionInfo=function() return {professionName='Alchemy',professionID=171} end,
                          GetAllRecipeIDs=function() return {42,99,100} end,
                          IsRecipeInSkillLine=function(id, prof) assert(prof==171); return id~=100 end,
                          GetRecipeInfo=function(id) return {learned=id==42,name='Potion '..id} end,
                          GetRecipeLink=function(id) return 'spell:'..id end,
                          GetRecipeSourceText=function(id) return id==99 and 'Vendor: Test Vendor\\nZone: Test Zone' or nil end,
                          GetRecipeDescription=function(id, reagents) assert(type(reagents)=='table'); return 'A recipe description.' end,
                          GetRecipeSchematic=function() return {reagentSlotSchematics={{quantityRequired=3,reagents={{itemID=7,name='Herb'}}}}} end
                        }
                        assert(addon.RecipeTracker:ImportTradeSkillRecipes()==1)
                        local character=CraftRosterDB.characters['Tester-Realm']
                        assert(character.recipes[42] and not character.recipes[99])
                        assert(not CraftRosterDB.recipes[100])
                        assert(CraftRosterDB.recipes[99].sourceText:find('Test Vendor',1,true))
                        assert(CraftRosterDB.recipes[99].materials[1].count==3)
                        if C_ChatInfo or SendAddonMessage then
                            for _,message in ipairs(sent) do
                                assert(not message[2]:find('99:',1,true), 'Unlearned recipe leaked into guild ownership')
                            end
                        end
                        SlashCmdList.CRAFTROSTER('')
                        local directory=addon.Directory
                        local tab=directory.frame.ProfessionsTab
                        for _,entry in ipairs(directory.professionCache.entries) do
                            if entry.id==99 then directory.selectedRecipe=entry.recipe end
                        end
                        assert(directory.selectedRecipe.id==99 and #directory.selectedRecipe.crafters==0)
                        directory:RefreshDetails(); directory:RefreshCrafters()
                        assert(tab.RecipeSource:GetVerticalScroll()==0)
                        assert(tab.RecipeSource:IsShown() and not tab.CrafterList:IsShown())
                        assert(tab.RecipeSource.Text:GetText():find('Test Vendor',1,true))
                        assert(tab.RecipeSource.Text:GetText():find('A recipe description',1,true))
                        tooltipLink=nil
                        function GameTooltip:SetHyperlink(link) tooltipLink=link end
                        tab.RecipeSource.Link.scripts.OnClick(tab.RecipeSource.Link)
                        assert(tooltipLink=='spell:99')
                        function IsShiftKeyDown() return true end
                        function ChatEdit_InsertLink(link) insertedLink=link; return true end
                        tab.RecipeSource.Link.scripts.OnClick(tab.RecipeSource.Link)
                        assert(insertedLink=='spell:99')
                        local oldScroll=tab.RecipeSource:GetVerticalScroll()
                        tab.RecipeSource:SetVerticalScroll(9999)
                        directory:RefreshRecipeSource()
                        assert(tab.RecipeSource:GetVerticalScroll()<9999)
                        for _,size in ipairs({{620,420},{760,500},{1200,800}}) do
                            directory.frame:SetSize(size[1],size[2])
                            directory:RefreshRecipeSource()
                            inside(tab.RecipeSource,tab)
                            apart(tab.RecipeSource,tab.Details)
                            assert(tab.RecipeSource.Child:GetHeight()>0)
                        end
                        -- Missing/throwing optional APIs preserve earlier good data.
                        C_TradeSkillUI.GetRecipeSourceText=function() error('unavailable') end
                        C_TradeSkillUI.GetRecipeSchematic=function() return nil end
                        assert(addon.RecipeTracker:ImportTradeSkillRecipes()==0)
                        assert(CraftRosterDB.recipes[99].sourceText:find('Test Vendor',1,true))
                        CraftRosterDB.recipes[99].sourceText=nil
                        directory:RefreshRecipeSource()
                        assert(tab.RecipeSource.Text:GetText():find('Source unknown',1,true))
                        -- An offline owner is a known crafter, never an unknown recipe.
                        CraftRosterDB.characters['Offline-Realm']={recipes={[99]={}}}
                        directory:InvalidateIndex(); directory.recipeIndex=nil; directory.professionCache=nil
                        directory:RefreshProfessions()
                        assert(#directory.selectedRecipe.crafters==1)
                        assert(not tab.RecipeSource:IsShown() and tab.CrafterList:IsShown())
                    ''')
