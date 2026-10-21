"""Regression coverage for the in-game beta 9 feedback."""
import importlib
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[1]

class FeedbackTests(unittest.TestCase):
    def test_catalogue_dropdown_report_buttons_and_popup_drag(self):
        for runtime in ('lua51', 'luajit21'):
            lua = importlib.import_module('lupa.' + runtime).LuaRuntime(unpack_returned_tuples=True)
            lua.execute((ROOT/'tests/wow_mock.lua').read_text())
            lua.execute("configure('modern'); dropdownEntries={}; function UIDropDownMenu_CreateInfo() return {} end; function UIDropDownMenu_AddButton(info) table.insert(dropdownEntries, info) end; function UIDropDownMenu_Initialize(frame, fn) fn(frame,1) end")
            addon = lua.table(); lua.globals().addon = addon
            for name in (ROOT/'CraftRoster.toc').read_text().splitlines():
                if name.endswith('.lua'):
                    lua.compile((ROOT/name).read_text(), name=name)('CraftRoster', addon)
            lua.execute("dispatch('ADDON_LOADED','CraftRoster')")
            lua.execute('''
                addon.RecipeSources:SeedCatalog()
                local count=0
                for id in pairs(CraftRosterDB.recipes) do
                    count=count+1
                    assert(not CraftRosterDB.characters['Tester-Realm'].recipes[id])
                end
                assert(count==2510, count)
                addon.Directory:Initialize()
                assert(dropdownEntries[1].text=='All')
                assert(dropdownEntries[2].disabled and dropdownEntries[2].text==' ')
                assert(dropdownEntries[3].text=='Alchemy')
                addon.Panel:Initialize()
                for _,frame in ipairs({addon.Directory.frame, addon.Panel.frame}) do
                    assert(frame.BugReportButton:GetText()=='Bug Report')
                    frame.BugReportButton.scripts.OnClick()
                    assert(addon.Panel.errorFrame:IsShown())
                end
                local dialog=StaticPopupDialogs.CRAFTROSTER_TRADE_MATS
                local popup=CreateFrame('Frame')
                local starts, stops=0,0
                popup.StartMoving=function() starts=starts+1 end
                popup.StopMovingOrSizing=function() stops=stops+1 end
                dialog.OnShow(popup)
                local handle=popup.CraftRosterDragHandle
                handle.scripts.OnDragStart(handle)
                handle.scripts.OnDragStop(handle)
                dialog.OnHide(popup)
                assert(starts==1 and stops==2 and not handle:IsShown())
                local warnings=0
                print=function() warnings=warnings+1 end
                C_ChatInfo.AreOutgoingAddonChatMessagesRestricted=function() return true end
                addon.GuildSync:RequestSync(); addon.GuildSync:SendData(true)
                assert(warnings==1 and #sent==0)
            ''')
