"""Regressions found while reviewing the candidate before real-client testing."""
import unittest
import test_recipe_sources as fixtures


class RuntimeEdgeTests(unittest.TestCase):
    def each_client(self, code):
        for runtime in ('lua51', 'luajit21'):
            for profile in ('modern', 'legacy', 'minimal'):
                with self.subTest(runtime=runtime, profile=profile):
                    fixtures.RecipeSourceTests().fresh(runtime, profile).execute(code)

    def test_transient_schematic_failure_preserves_materials_and_continues_scan(self):
        self.each_client('''
            local old={{name='Herb',itemID=7,count=3}}
            CraftRosterDB.recipes[42]={name='Potion',profession='Alchemy',materials=old}
            C_TradeSkillUI={
              GetAllRecipeIDs=function() return {42,43} end,
              GetBaseProfessionInfo=function() return {professionName='Alchemy'} end,
              GetRecipeInfo=function(id) return {learned=true,name='Potion '..id} end,
              GetRecipeSchematic=function(id)
                if id==42 then error('profession data is loading') end
                return {outputItemID=12345,reagentSlotSchematics={}}
              end
            }
            assert(addon.RecipeTracker:ImportTradeSkillRecipes()==2)
            assert(CraftRosterDB.recipes[42].materials==old)
            assert(CraftRosterDB.characters['Tester-Realm'].recipes[43])
            assert(CraftRosterDB.recipes[43].itemLink=='item:12345')
        ''')

    def test_incomplete_required_slot_never_overwrites_complete_materials(self):
        self.each_client('''
            local old={{name='Herb',itemID=7,count=3}}
            CraftRosterDB.recipes[42]={name='Potion',materials=old}
            CraftRosterDB.recipes[43]={name='Other potion',materials=old}
            C_TradeSkillUI={
              GetAllRecipeIDs=function() return {42,43} end,
              GetRecipeInfo=function(id) return {learned=id==42,name='Potion '..id} end,
              GetRecipeSchematic=function() return {reagentSlotSchematics={
                {quantityRequired=3,required=true,reagents={}}
              }} end
            }
            addon.RecipeTracker:ImportTradeSkillRecipes()
            assert(CraftRosterDB.recipes[42].materials==old)
            assert(CraftRosterDB.recipes[43].materials==old)
        ''')

    def test_hiding_offline_crafter_clears_action_target(self):
        self.each_client('''
            CraftRosterDB.settings.onlineOnly=false
            CraftRosterDB.recipes[42]={name='Potion'}
            CraftRosterDB.characters['Offline-Realm']={recipes={[42]={}}}
            SlashCmdList.CRAFTROSTER('')
            for _,entry in ipairs(addon.Directory.professionCache.entries) do
                if entry.id==42 then addon.Directory.selectedRecipe=entry.recipe end
            end
            addon.Directory.selectedCrafter='Offline-Realm'
            addon.Directory:RefreshCrafters()
            assert(addon.Directory.selectedCrafter=='Offline-Realm')
            CraftRosterDB.settings.onlineOnly=true
            addon.Directory:RefreshCrafters()
            assert(addon.Directory.selectedCrafter==nil)
            assert(not addon.Directory.frame.ProfessionsTab.RecipeSource:IsShown())
        ''')

    def test_recipe_tooltip_failure_has_a_readable_fallback(self):
        self.each_client('''
            CraftRosterDB.recipes[99]={name='Uncached potion',profession='Alchemy'}
            SlashCmdList.CRAFTROSTER('')
            for _,entry in ipairs(addon.Directory.professionCache.entries) do
                if entry.id==99 then addon.Directory.selectedRecipe=entry.recipe end
            end
            addon.Directory:RefreshCrafters()
            function GameTooltip:SetHyperlink() error('unknown link') end
            function GameTooltip:SetText(text) tooltipTitle=text end
            function GameTooltip:AddLine(text) tooltipLine=text end
            local button=addon.Directory.frame.ProfessionsTab.RecipeSource.Link
            button.scripts.OnEnter(button)
            assert(tooltipTitle=='Uncached potion')
            assert(tooltipLine:find('unavailable',1,true))
        ''')

    def test_refresh_requests_legacy_roster_and_hiding_minimap_stops_drag(self):
        self.each_client('''
            C_GuildInfo=nil; RequestGuildRoster=nil; rosterRequests=0
            function GuildRoster() rosterRequests=rosterRequests+1 end
            SlashCmdList.CRAFTROSTER('')
            addon.Directory.frame.ProfessionsTab.CraftRosterRefreshButton.scripts.OnClick()
            assert(rosterRequests==1)
            local button=CraftRosterMinimapButton
            function button:LockHighlight() end
            function button:UnlockHighlight() end
            function Minimap:GetCenter() return nil,nil end
            function Minimap:GetEffectiveScale() return 1 end
            function GetCursorPosition() return 0,0 end
            button.scripts.OnDragStart(button)
            button.scripts.OnUpdate()
            button:Hide()
            assert(button.scripts.OnUpdate==nil)
        ''')
