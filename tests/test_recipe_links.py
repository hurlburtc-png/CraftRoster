"""Visible recipe/output links and geometry during native window resizing."""
import unittest
from pathlib import Path
from test_work_orders import fresh

ROOT=Path(__file__).resolve().parents[1]
SETUP='''
    GameTooltip.AddLine=function() end
    CraftRosterDB.recipes[19054]={name='Red Dragonscale Breastplate',profession='Leatherworking',recipeItemID=15730,itemLink='item:15047',materials={}}
    CraftRosterDB.characters['Tester-Realm'].recipes[19054]={}
    CraftRosterDB.favorites={[19054]=true}; CraftRosterDB.settings.favoritesOnly=true
    CraftRosterDB.settings.onlineOnly=false
    addon.Directory:Toggle()
    local child=addon.Directory.frame.ProfessionsTab.ResultsChild
    resultRow=nil
    for _,f in ipairs(frames) do if f.parent==child and f.listEntry and f.listEntry.id==19054 then resultRow=f end end
    assert(resultRow and resultRow.RecipeLink and resultRow.CraftLink)
'''
CASES={
 'item_links_replace_generic_button_labels': """
    assert(resultRow.RecipeLink:GetText():find('|Hitem:15730',1,true))
    assert(resultRow.CraftLink:GetText():find('|Hitem:15047',1,true))
    assert(resultRow.RecipeLink:GetText():find('|T',1,true) and resultRow.CraftLink:GetText():find('|T',1,true))
    assert(resultRow.RecipeLink:GetText()~='Recipe' and resultRow.CraftLink:GetText()~='Craft')
""",
'shopping_hover_uses_native_item_with_progress_and_missing_id_fallback': """
    inventoryFixture(false,true)
    addon.ShoppingList:Open(42)
    local row=addon.ShoppingList.frame.Rows[1]
    local link, fallback, lines
    GameTooltip.SetHyperlink=function(self,value) link=value end
    GameTooltip.SetText=function(self,value) fallback=value end
    GameTooltip.AddLine=function(self,value) lines=(lines or '')..value end
    row.scripts.OnEnter(row)
    assert(link=='item:'..row.entry.itemID and lines:find('Your share:',1,true))
    row.entry.itemID=nil; row.scripts.OnEnter(row)
    assert(fallback==row.entry.name)
    row.entry.itemID=7; fallback=nil
    GameTooltip.SetHyperlink=function() error('uncached') end
    row.scripts.OnEnter(row); assert(fallback==row.entry.name)
""",
'distinct_teaching_and_output_links_hover_inspect_and_chat': '''
    local tooltips,inspected={},{}
    GameTooltip.SetHyperlink=function(self,link) table.insert(tooltips,link) end
    SetItemRef=function(payload,link) table.insert(inspected,payload) end
    resultRow.RecipeLink.scripts.OnEnter(resultRow.RecipeLink)
    resultRow.CraftLink.scripts.OnEnter(resultRow.CraftLink)
    assert(tooltips[1]:find('|Hitem:15730',1,true) and tooltips[2]:find('|Hitem:15047',1,true))
    resultRow.RecipeLink.scripts.OnClick(resultRow.RecipeLink,'LeftButton')
    resultRow.CraftLink.scripts.OnClick(resultRow.CraftLink,'LeftButton')
    assert(inspected[1]:find('item:15730',1,true) and inspected[2]:find('item:15047',1,true))
    local inserted={}
    IsShiftKeyDown=function() return true end
    ChatEdit_InsertLink=function(link) table.insert(inserted,link); return true end
    SendChatMessage=function() error('links must never be sent automatically') end
    resultRow.RecipeLink.scripts.OnClick(resultRow.RecipeLink,'LeftButton')
    resultRow.CraftLink.scripts.OnClick(resultRow.CraftLink,'LeftButton')
    assert(inserted[1]:find('|Hitem:15730',1,true) and inserted[2]:find('|Hitem:15047',1,true))
''',
'right_click_copy_and_shift_click_without_active_chat': '''
    local copy,opened
    StaticPopup_Show=function(which,a,b,data) assert(which=='CRAFTROSTER_COPY_LINK'); copy=data end
    resultRow.CraftLink.scripts.OnClick(resultRow.CraftLink,'RightButton')
    assert(copy:find('|Hitem:15047',1,true))
    local edit=CreateFrame()
    StaticPopupDialogs.CRAFTROSTER_COPY_LINK.OnShow({data=copy,editBox=edit})
    assert(edit:GetText()==copy and edit.highlighted and edit.focused)
    IsShiftKeyDown=function() return true end
    ChatEdit_InsertLink=function() return false end
    ChatFrame_OpenChat=function(link) opened=link end
    resultRow.RecipeLink.scripts.OnClick(resultRow.RecipeLink,'LeftButton')
    assert(opened:find('|Hitem:15730',1,true))
''',
'unknown_outputs_use_real_spell_without_invented_item_ids': '''
    CraftRosterDB.recipes[999999]={name='Unknown enchant',profession='Enchanting'}
    local links=addon.Directory:GetSearchLinks(999999)
    assert(links.recipe:find('|Hspell:999999',1,true))
    assert(links.craft:find('|Hspell:999999',1,true) and not links.hasOutputItem)
    assert(not links.craft:find('|Hitem:999999',1,true))
''',
'no_native_inspection_or_item_cache_falls_back_to_tooltip': '''
    SetItemRef=nil; C_Item=nil; GetItemInfo=nil
    local tooltip
    GameTooltip.SetHyperlink=function(self,link) tooltip=link end
    resultRow.CraftLink.scripts.OnClick(resultRow.CraftLink,'LeftButton')
    assert(tooltip:find('|Hitem:15047',1,true))
    ChatEdit_InsertLink=function() error('chat unavailable') end
    IsShiftKeyDown=function() return true end
    local draft
    ChatFrame_OpenChat=function(link) draft=link end
    resultRow.CraftLink.scripts.OnClick(resultRow.CraftLink,'LeftButton')
    assert(draft:find('|Hitem:15047',1,true))
''',
'pooled_rows_clear_recipe_links_for_empty_and_header_rows': '''
    local tab=addon.Directory.frame.ProfessionsTab
    tab.SearchBox:SetText('does not match any recipe')
    addon.Directory:RefreshProfessions()
    for _,row in ipairs(frames) do
      if row.parent==tab.ResultsChild and row:IsShown() and row.RecipeLink then
        assert(not row.RecipeLink:IsShown() and not row.CraftLink:IsShown())
      end
    end
''',
}
class RecipeLinkTests(unittest.TestCase): pass
for runtime in ('lua51','luajit21'):
    for profile in ('modern','legacy','minimal'):
        for name,code in CASES.items():
            def check(self,runtime=runtime,profile=profile,code=code):
                lua=fresh(runtime,profile); lua.execute(SETUP); lua.execute(code)
            setattr(RecipeLinkTests,f'test_{runtime}_{profile}_{name}',check)

class ResizeSpacingTests(unittest.TestCase):
    def test_border_drag_corner_grip_and_spacing_across_sizes(self):
        for runtime in ('lua51','luajit21'):
            for profile in ('modern','legacy','minimal'):
                with self.subTest(runtime=runtime,profile=profile):
                    lua=fresh(runtime,profile)
                    lua.execute((ROOT/'tests/layout_mock.lua').read_text())
                    lua.execute(SETUP)
                    lua.execute('''
                        local frame=addon.Directory.frame
                        local tab=frame.ProfessionsTab
                        for _,size in ipairs({{620,420},{760,500},{1200,800},{1800,960}}) do
                          frame:SetSize(size[1],size[2]); tab.Details.scripts.OnSizeChanged(tab.Details)
                          addon.Directory:RefreshIfVisible()
                          inside(frame.ResizeHandle,frame)
                          for _,handle in pairs(frame.MoveHandles) do
                            inside(handle,frame); apart(handle,frame.ResizeHandle)
                            for _,button in ipairs(frame.TabButtons) do apart(handle,button) end
                            apart(handle,frame.WorkOrdersButton)
                          end
                          for _,row in ipairs(frames) do
                            if row.parent==tab.ResultsChild and row:IsShown() and row.RecipeLink and row.RecipeLink:IsShown() then
                              inside(row.RecipeLink,row); inside(row.CraftLink,row)
                              apart(row.RecipeLink,row.CraftLink); apart(row.Label,row.RecipeLink)
                              apart(row.Label,row.CraftLink); apart(row.RightLabel,row.CraftLink)
                            end
                          end
                          inside(tab.CraftRosterQuantity,tab.Details)
                          apart(tab.CraftRosterQuantity,tab.CraftRosterQuantityUp)
                          apart(tab.CraftRosterTradeButton,tab.CraftRosterMailButton)
                        end
                        local moves,sizes,stops=0,0,0
                        frame.StartMoving=function() moves=moves+1 end
                        frame.StartSizing=function(self,corner) assert(corner=='BOTTOMRIGHT'); sizes=sizes+1 end
                        frame.StopMovingOrSizing=function() stops=stops+1 end
                        frame.MoveHandles.left.scripts.OnDragStart()
                        frame.MoveHandles.left.scripts.OnDragStop()
                        frame.ResizeHandle.scripts.OnDragStart()
                        frame:SetSize(100,100); frame.ResizeHandle.scripts.OnDragStop()
                        assert(moves==1 and sizes==1 and stops==2)
                        assert(frame:GetWidth()==620 and frame:GetHeight()==420)
                        assert(CraftRosterDB.settings.window.width==620 and CraftRosterDB.settings.window.height==420)
                    ''')

if __name__=='__main__': unittest.main()
