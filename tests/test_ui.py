"""Anchor geometry and click flows. Fonts and client templates still need in-game QA."""
import importlib
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class FrameLayoutTests(unittest.TestCase):
    def test_layout_and_actions_across_sizes_and_clients(self):
        for runtime in ('lua51', 'luajit21'):
            for profile in ('modern', 'legacy', 'minimal'):
                with self.subTest(runtime=runtime, profile=profile):
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
                    lua.execute('''
                        inventoryFixture(false,true)
                        CraftRosterDB.recipes[42].name=string.rep('Very long recipe title ',8)
                        CraftRosterDB.recipes[42].profession='Alchemy'
                        CraftRosterDB.characters['Crafter-Realm']={recipes={[42]={}}}
                        CraftRosterDB.settings.onlineOnly=false
                        SlashCmdList.CRAFTROSTER('')
                        local frame=addon.Directory.frame
                        local tab=frame.ProfessionsTab
                        assert(frame.clamped and frame.minWidth==620 and frame.minHeight==420)
                        for _,size in ipairs({{620,420},{760,500},{1200,800}}) do
                            frame:SetSize(size[1],size[2])
                            tab.Details.scripts.OnSizeChanged(tab.Details)
                            addon.Directory:RefreshProfessions()
                            for _,row in ipairs(frames) do
                                if row.parent==tab.ResultsChild and row:IsShown() and row.Label then
                                    apart(row.Label,row.RightLabel)
                                end
                            end
                            inside(tab,frame); inside(tab.Results,tab); inside(tab.SelectedCraftScroll,tab); inside(tab.Details,tab.SelectedCraftContent)
                            inside(tab.CrafterList,tab.SelectedCraftContent); apart(tab.Results,tab.Details)
                            apart(tab.CrafterList,tab.Details)
                            local buttons={tab.CraftRosterTradeButton,tab.CraftRosterMailButton,
                                tab.CraftRosterFavoriteButton,tab.CraftRosterShoppingButton,
                                tab.CraftRosterQuantity,tab.CraftRosterAutoLoad,
                                tab.CraftRosterQuantityUp,tab.CraftRosterQuantityDown}
                            for i,button in ipairs(buttons) do
                                inside(button,tab.Details)
                                for j=i+1,#buttons do apart(button,buttons[j]) end
                            end
                            for _,button in ipairs(frame.TabButtons) do inside(button,frame) end
                            for i,button in ipairs(frame.TabButtons) do
                                button.scripts.OnClick(button)
                                assert(addon.Directory.activeTab==i and button.enabled==false)
                            end
                            frame.TabButtons[1].scripts.OnClick()
                            for _,entry in ipairs(addon.Directory.professionCache.entries) do if entry.id==42 then addon.Directory.selectedRecipe=entry.recipe end end
                            addon.Directory:RefreshDetails()
                            inside(tab.DetailsName,tab.Details)
                            apart(tab.DetailsName,tab.DetailsProfession)
                            assert(tab.DetailsName.maxLines==2)
                        end
                        addon.Directory.selectedCrafter='Crafter-Realm'
                        tab.CraftRosterFavoriteButton.scripts.OnClick()
                        assert(CraftRosterDB.favorites[42] and tab.CraftRosterFavoriteButton:GetText()=='Unfavorite')
                        tab.CraftRosterFavoriteButton.scripts.OnClick()
                        assert(not CraftRosterDB.favorites[42] and tab.CraftRosterFavoriteButton:GetText()=='Favorite')
                        tab.CraftRosterShoppingButton.scripts.OnClick()
                        local shopping=addon.ShoppingList.frame
                        assert(shopping:IsShown() and shopping.strata==frame.strata and shopping.Recipe.maxLines==2)
                        inside(shopping.Scroll,shopping); apart(shopping.Recipe,shopping.Scroll)
                        shopping.Close.scripts.OnClick(); assert(not shopping:IsShown())
                        function ChatFrame_OpenChat(text) whisperDraft=text end
                        tab.CraftRosterTradeButton.scripts.OnClick()
                        addon.WhisperComposer.frame.Send.scripts.OnClick()
                        assert(whisperDraft:find('/w Crafter-Realm ',1,true)==1)
                        tab.CraftRosterMailButton.scripts.OnClick()
                        SendMailNameEditBox=CreateFrame(); SendMailSubjectEditBox=CreateFrame()
                        dispatch('MAIL_SHOW'); assert(SendMailNameEditBox:GetText()=='Crafter-Realm')
                        tab.CraftRosterRefreshButton.scripts.OnClick()
                        tab.SortButton.scripts.OnClick(tab.SortButton)
                        assert(CraftRosterDB.settings.sortMode=='crafters')
                        SlashCmdList.CRAFTROSTER('settings')
                        assert(addon.Panel.frame.clamped and addon.Panel.frame:GetWidth()==380)
                        local settingsButtons={}
                        for _,button in ipairs(frames) do
                            if button.parent==addon.Panel.frame and button.scripts.OnClick then
                                settingsButtons[button:GetText()]=button
                            end
                        end
                        settingsButtons['Enable / Disable'].scripts.OnClick()
                        assert(not CraftRosterDB.settings.enabled)
                        settingsButtons['Enable / Disable'].scripts.OnClick()
                        assert(CraftRosterDB.settings.enabled)
                        settingsButtons['Update My Recipes'].scripts.OnClick()
                        settingsButtons['Sync Guild Recipes'].scripts.OnClick()
                        settingsButtons['Reset Window Position'].scripts.OnClick()
                        addon.Panel.autoCheck:SetChecked(false)
                        addon.Panel.autoCheck.scripts.OnClick(addon.Panel.autoCheck)
                        assert(not CraftRosterDB.settings.autoUpdateRecipes)
                        addon.Panel.minimapCheck:SetChecked(false)
                        addon.Panel.minimapCheck.scripts.OnClick(addon.Panel.minimapCheck)
                        assert(not CraftRosterDB.settings.showMinimap and not CraftRosterMinimapButton:IsShown())
                        addon.Panel.minimapCheck:SetChecked(true)
                        addon.Panel.minimapCheck.scripts.OnClick(addon.Panel.minimapCheck)
                        assert(CraftRosterMinimapButton:IsShown())
                        addon.Panel:ShowError(); assert(addon.Panel.errorFrame:IsShown() and addon.Panel.errorFrame.clamped)
                        addon.Directory:ResetWindow(); assert(frame:GetWidth()==760 and frame:GetHeight()==500)
                    ''')


if __name__ == '__main__':
    unittest.main()

