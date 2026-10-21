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
    for name in (ROOT/'CraftRoster.toc').read_text().splitlines():
        if name.endswith('.lua'):
            lua.compile((ROOT/name).read_text(), name=name)('CraftRoster', addon)
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

def work_orders(runtime):
    lua=importlib.import_module('lupa.'+runtime).LuaRuntime(unpack_returned_tuples=True)
    lua.execute((ROOT/'tests/wow_mock.lua').read_text())
    lua.globals().configure('modern')
    lua.execute((ROOT/'tests/layout_mock.lua').read_text())
    lua.execute("collectgarbage('collect'); baseMemory=collectgarbage('count')")
    addon=lua.table(); lua.globals().addon=addon
    started=time.perf_counter()
    for name in (ROOT/'CraftRoster.toc').read_text().splitlines():
        if name.endswith('.lua'): lua.compile((ROOT/name).read_text(),name=name)('CraftRoster',addon)
    lua.execute("dispatch('ADDON_LOADED','CraftRoster')")
    startup_ms=(time.perf_counter()-started)*1000
    lua.execute("collectgarbage('collect'); idleMemory=collectgarbage('count')")
    idle_kib=lua.eval('idleMemory-baseMemory')
    catalog=lua.eval("LibStub('LibProfessionDB-1.0'):Count()")
    lua.execute("""
        CraftRosterDB.recipes[42]={name='Potion',profession='Alchemy',itemLink='item:123'}
        CraftRosterDB.characters['Tester-Realm'].recipes[42]={}
        collectgarbage('collect'); beforeQueue=collectgarbage('count')
    """)
    started=time.perf_counter()
    lua.execute("for i=1,500 do addon.WorkOrders:Add('Customer'..i..'-Realm',42,10,'bench'..i,'manual') end")
    fill_ms=(time.perf_counter()-started)*1000
    lua.execute("collectgarbage('collect'); queueMemory=collectgarbage('count')")
    queue_kib=lua.eval('queueMemory-beforeQueue')
    before=len(lua.globals().frames)
    started=time.perf_counter(); lua.execute('addon.WorkOrders:Open()')
    open_ms=(time.perf_counter()-started)*1000
    open_objects=len(lua.globals().frames)-before
    visible_rows=lua.eval('#addon.WorkOrders.frame.Rows')
    before=len(lua.globals().frames)
    started=time.perf_counter()
    lua.execute("for i=1,100 do local f=addon.WorkOrders.frame; f.Scroll:SetVerticalScroll(i*550); addon.WorkOrders:DrawRows() end")
    scroll_ms=(time.perf_counter()-started)*1000
    scroll_objects=len(lua.globals().frames)-before
    started=time.perf_counter()
    lua.execute("for i=1,100 do addon.WorkOrders:Refresh() end")
    refresh_ms=(time.perf_counter()-started)*1000/100
    lua.execute("""
        periodicHandlers=0
        for _,frame in ipairs(frames) do if frame.scripts.OnUpdate then periodicHandlers=periodicHandlers+1 end end
    """)
    return dict(runtime=runtime,bundled_recipes=catalog,mock_startup_ms=round(startup_ms,2),
                mock_idle_lua_heap_kib=round(idle_kib,1),orders=500,mock_queue_added_lua_heap_kib=round(queue_kib,1),
                mock_fill_500_orders_ms=round(fill_ms,2),mock_work_orders_open_ms=round(open_ms,2),
                work_order_visible_row_objects=visible_rows,work_orders_open_added_ui_objects=open_objects,
                additional_ui_objects_after_100_order_scrolls=scroll_objects,
                mock_100_order_scrolls_ms=round(scroll_ms,2),mock_average_full_queue_refresh_ms=round(refresh_ms,3),
                onupdate_handlers=lua.globals().periodicHandlers)

if __name__ == '__main__':
    print(json.dumps({'directory_stress':[run(name) for name in ('lua51','luajit21')],
                      'work_order_stress':[work_orders(name) for name in ('lua51','luajit21')]},indent=2))
