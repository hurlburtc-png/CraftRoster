"""Small reproducible workload; timings describe mocks, not the game client."""
import importlib
import json
from pathlib import Path
import time

ROOT = Path(__file__).resolve().parents[1]

def run(runtime):
    lua = importlib.import_module('lupa.' + runtime).LuaRuntime(unpack_returned_tuples=True)
    lua.execute((ROOT/'tests/wow_mock.lua').read_text())
    lua.globals().configure('modern')
    fixture_frames = len(lua.globals().frames)
    addon = lua.table(); lua.globals().addon = addon
    for name in (ROOT/'CraftRoster/CraftRoster.toc').read_text().splitlines():
        if name.endswith('.lua'):
            lua.compile((ROOT/'CraftRoster'/name).read_text(), name=name)('CraftRoster', addon)
    lua.execute("dispatch('ADDON_LOADED','CraftRoster')")
    startup_frames = len(lua.globals().frames) - fixture_frames
    lua.execute("""
        local own=CraftRosterDB.characters['Tester-Realm'].recipes
        for id=1,5000 do
          CraftRosterDB.recipes[id]={name=('Potion %05d'):format(id),profession='Alchemy'}
          own[id]={}
        end
        for i=1,20 do CraftRosterDB.characters['Crafter'..i..'-Realm']={recipes=own} end
    """)
    before = len(lua.globals().frames)
    started = time.perf_counter()
    lua.execute("SlashCmdList.CRAFTROSTER('')")
    open_ms = (time.perf_counter() - started) * 1000
    open_frames = len(lua.globals().frames) - before
    before = len(lua.globals().frames)
    lua.execute("""
        local tab=addon.Directory.frame.ProfessionsTab
        for i=1,100 do
          tab.Results:SetVerticalScroll(i*1500)
          tab.Results.scripts.OnVerticalScroll(tab.Results,i*1500)
        end
    """)
    scroll_frames = len(lua.globals().frames) - before
    lua.execute("""
        scans=0
        C_TradeSkillUI={GetAllRecipeIDs=function() scans=scans+1; return {} end,GetRecipeInfo=function() end}
        for i=1,20 do dispatch('TRADE_SKILL_LIST_UPDATE') end
        flushTimers()
    """)
    return dict(runtime=runtime, recipes=5000, crafter_recipe_links=105000,
                startup_addon_ui_objects=startup_frames, first_open_added_ui_objects=open_frames,
                additional_ui_objects_after_100_scrolls=scroll_frames,
                scans_for_20_events=lua.globals().scans, mock_first_open_ms=round(open_ms, 2))

if __name__ == '__main__':
    print(json.dumps([run(name) for name in ('lua51', 'luajit21')], indent=2))
