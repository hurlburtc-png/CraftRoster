"""Exercise appearance controls, saved preferences, and responsive geometry."""
from pathlib import Path
import unittest
from test_work_orders import fresh

CASES = {
    'scale_controls_apply_live_and_restore_defaults': '''
        inventoryFixture(false,true)
        addon.Directory:Toggle(); addon.ShoppingList:Open(42)
        addon.WhisperComposer:Initialize(); addon.WorkOrders:Initialize()
        addon.Panel:Initialize()
        local panel=addon.Panel
        panel.scaleCheck:SetChecked(true)
        panel.scaleCheck.scripts.OnClick(panel.scaleCheck)
        panel.scaleSlider.scripts.OnValueChanged(panel.scaleSlider,125)
        assert(CraftRosterDB.settings.uiScaleEnabled and CraftRosterDB.settings.uiScale==1.25)
        for _,frame in ipairs({addon.Directory.frame,addon.ShoppingList.frame,addon.WhisperComposer.frame,
            addon.WorkOrders.frame,panel.frame,panel.errorFrame}) do assert(frame:GetScale()==1.25) end
        panel.scaleCheck:SetChecked(false)
        panel.scaleCheck.scripts.OnClick(panel.scaleCheck)
        assert(addon.Directory.frame:GetScale()==1 and CraftRosterDB.settings.uiScale==1.25)
        panel.scaleSlider.scripts.OnValueChanged(panel.scaleSlider,150)
        assert(CraftRosterDB.settings.uiScale==1.25,'disabled slider must not change saved scale')
        addon.Theme:SetPalette('frost')
        addon.Theme:SetOpacity(0.55)
        panel.resetAppearance.scripts.OnClick()
        assert(not CraftRosterDB.settings.uiScaleEnabled and CraftRosterDB.settings.uiScale==1)
        assert(addon.Theme:Palette().key=='gold')
        assert(addon.Theme:Opacity()==1 and addon.Directory.frame:GetAlpha()==1)
    ''',
    'saved_preferences_apply_to_windows_created_later': '''
        CraftRosterDB.settings.theme='violet'
        CraftRosterDB.settings.uiScaleEnabled=true; CraftRosterDB.settings.uiScale=1.1
        addon.Directory:Toggle(); addon.Panel:Initialize(); addon.WhisperComposer:Initialize()
        assert(addon.Directory.frame:GetScale()==1.1 and addon.Panel.frame:GetScale()==1.1)
        local details=addon.Directory.frame.ProfessionsTab.Details
        assert(details.borderColor[1]==0.51 and addon.Theme:Palette().key=='violet')
        assert(not addon.Theme:SetPalette('invalid') and not addon.Theme:SetScale(true,0/0))
    ''',
    'themes_preserve_recipe_and_scale_fits_viewport': '''
        inventoryFixture(false,true)
        addon.Directory:Toggle()
        CraftRosterDB.characters['Tester-Realm'].recipes[42]={}
        addon.Directory:InvalidateIndex()
        addon.Directory.selectedRecipe={id=42,name='Potion',profession='Alchemy',crafters={'Tester-Realm'}}
        addon.Directory:RefreshProfessions()
        for _,palette in ipairs(addon.Theme.palettes) do
            assert(addon.Theme:SetPalette(palette.key))
            assert(addon.Directory.selectedRecipe.id==42)
            local tab=addon.Directory.frame.ProfessionsTab
            assert(tab.Details.borderColor[1]==palette.border[1])
        end
        UIParent:SetSize(1280,720)
        addon.Theme:SetScale(true,1.5)
        local frame=addon.Directory.frame
        assert(frame:GetHeight()*frame:GetScale()<=696.01)
        assert(frame:GetWidth()*frame:GetScale()<=1256.01)
        assert(CraftRosterDB.settings.uiScale==1.5,'screen fitting must preserve preference')
        UIParent:SetSize(1920,1080); dispatch('DISPLAY_SIZE_CHANGED')
        assert(frame:GetScale()==1.5,'a larger display restores the requested scale')
    ''',
    'responsive_recipe_materials_and_fixed_actions_do_not_overlap': '''
        inventoryFixture(false,true)
        addon.Directory:Toggle()
        local d=addon.Directory; local frame=d.frame; local tab=frame.ProfessionsTab
        d.selectedRecipe={id=42,name='Potion',profession='Alchemy',crafters={}}
        d:RefreshDetails(); d:RefreshCrafters()
        for _,size in ipairs({{620,420},{760,500},{1000,680},{1200,800}}) do
            frame:SetSize(size[1],size[2]); frame.scripts.OnSizeChanged(frame)
            addon.SelectedCraft:Refresh()
            local view=addon.SelectedCraft
            inside(tab.SearchBox,tab.CataloguePanel); inside(tab.Results,tab.CataloguePanel)
            apart(tab.Results,tab.SelectedCraftScroll); apart(tab.ActionBar,tab.SelectedCraftScroll)
            inside(view.recipeBody,tab.Details)
            apart(view.recipeBody,view.rows[1]); apart(view.materialTitle,view.rows[1])
            apart(tab.RecipeSource,view.rows[1]); apart(tab.RecipeSource,view.recipeBody)
            apart(view.crafterTitle,tab.Details); apart(view.crafterTitle,tab.CrafterList)
            local controls={tab.CraftRosterTradeButton,tab.CraftRosterMailButton,
                tab.CraftRosterShoppingButton,tab.CraftRosterFavoriteButton,
                tab.CraftRosterAutoLoad,tab.CraftRosterCancelRequestButton}
            for i,a in ipairs(controls) do
                inside(a,tab.ActionBar)
                for j=i+1,#controls do apart(a,controls[j]) end
            end
            local footer={frame.TabButtons[1],frame.TabButtons[2],frame.TabButtons[3],
                frame.WorkOrdersButton,frame.ShoppingButton,frame.SettingsButton}
            for i,a in ipairs(footer) do
                inside(a,frame)
                for j=i+1,#footer do apart(a,footer[j]) end
            end
        end
        addon.Panel:Initialize()
        inside(addon.Panel.scaleSlider,addon.Panel.frame)
        inside(addon.Panel.resetAppearance,addon.Panel.frame)
        apart(addon.Panel.scaleSlider,addon.Panel.resetAppearance)
        inside(addon.Panel.themePreview,addon.Panel.frame)
        for i,tile in ipairs(addon.Panel.themeButtons) do
            inside(tile,addon.Panel.frame)
            apart(tile,addon.Panel.themePreview)
            for j=i+1,#addon.Panel.themeButtons do apart(tile,addon.Panel.themeButtons[j]) end
        end
        local controls={addon.Panel.scaleSlider,addon.Panel.opacitySlider,
            addon.Panel.resetAppearance,addon.Panel.themePreview,addon.Panel.scaleCheck,
            addon.Panel.autoCheck,addon.Panel.minimapCheck,addon.Panel.autoLoadCheck}
        for _,button in ipairs(addon.Panel.generalButtons) do controls[#controls+1]=button end
        for i,control in ipairs(controls) do
            inside(control,addon.Panel.frame)
            for j=i+1,#controls do apart(control,controls[j]) end
        end
    ''',
    'opacity_controls_apply_live_keep_settings_solid_and_clamp': '''
        inventoryFixture(false,true)
        addon.Directory:Toggle(); addon.ShoppingList:Open(42)
        addon.WhisperComposer:Initialize(); addon.WorkOrders:Initialize()
        addon.Panel:Toggle()
        local panel=addon.Panel
        panel.opacitySlider.scripts.OnValueChanged(panel.opacitySlider,63)
        assert(CraftRosterDB.settings.windowOpacity==0.65)
        for _,frame in ipairs({addon.Directory.frame,addon.ShoppingList.frame,
            addon.WhisperComposer.frame,addon.WorkOrders.frame,panel.themePreview}) do
            assert(frame:GetAlpha()==0.65)
        end
        assert(panel.frame:GetAlpha()==1 and panel.errorFrame:GetAlpha()==1)
        assert(panel.opacityText:GetText()=='Window opacity: 65%')
        assert(not addon.Theme:SetOpacity(0/0) and not addon.Theme:SetOpacity('bad'))
        addon.Theme:SetOpacity(-1); assert(addon.Theme:Opacity()==0.4)
        addon.Theme:SetOpacity(4); assert(addon.Theme:Opacity()==1)
        panel.updatingAppearance=true
        panel.opacitySlider.scripts.OnValueChanged(panel.opacitySlider,40)
        panel.updatingAppearance=false
        assert(addon.Theme:Opacity()==1,'programmatic refresh must not save a new preference')
    ''',
    'saved_opacity_applies_lazily_and_invalid_values_are_safe': '''
        CraftRosterDB.settings.windowOpacity=0.55
        addon.Panel:Initialize()
        assert(addon.Panel.themePreview:GetAlpha()==0.55)
        assert(addon.Panel.opacityText:GetText()=='Window opacity: 55%')
        addon.Directory:Toggle(); addon.WorkOrders:Initialize()
        assert(addon.Directory.frame:GetAlpha()==0.55 and addon.WorkOrders.frame:GetAlpha()==0.55)
        addon.Directory.frame:Hide(); addon.Directory.frame:Show()
        assert(addon.Directory.frame:GetAlpha()==0.55)
        for _,value in ipairs({'bad',0/0}) do
            CraftRosterDB.settings.windowOpacity=value
            assert(addon.Theme:Opacity()==1)
        end
        CraftRosterDB.settings.windowOpacity=nil; assert(addon.Theme:Opacity()==1)
    ''',
    'settings_and_main_open_and_close_independently': '''
        addon.Panel:Toggle()
        local panel=addon.Panel
        assert(panel.frame:IsShown())
        panel.openMainButton.scripts.OnClick()
        local main=addon.Directory.frame
        assert(main:IsShown() and panel.frame:IsShown())
        panel.openMainButton.scripts.OnClick()
        assert(main:IsShown(),'Open main must never toggle an already visible window closed')
        panel.scaleCheck:SetChecked(true); panel.scaleCheck.scripts.OnClick(panel.scaleCheck)
        panel.scaleSlider.scripts.OnValueChanged(panel.scaleSlider,125)
        assert(main:GetScale()==1.25 and panel.frame:IsShown())
        panel.opacitySlider.scripts.OnValueChanged(panel.opacitySlider,70)
        assert(main:GetAlpha()==0.7 and panel.frame:GetAlpha()==1)
        panel:Toggle(); assert(main:IsShown() and not panel.frame:IsShown())
        main.SettingsButton.scripts.OnClick()
        assert(main:IsShown() and panel.frame:IsShown())
        main:Hide(); assert(panel.frame:IsShown())
        assert(main.ResizeHandle.scripts.OnDragStart and main.ResizeHandle.scripts.OnDragStop)
    ''',
    'autoload_preference_stays_in_sync_between_windows': '''
        addon.Panel:Initialize(); addon.Directory:Toggle()
        local checkbox=addon.Panel.autoLoadCheck
        checkbox:SetChecked(false); checkbox.scripts.OnClick(checkbox)
        assert(not CraftRosterDB.settings.autoLoadItems)
        local main=addon.Directory.frame.ProfessionsTab.CraftRosterAutoLoad
        assert(not main:GetChecked())
        addon.Requests:SetAutoLoadItems(true)
        assert(checkbox:GetChecked() and main:GetChecked())
    ''',
    'theme_tiles_apply_live_without_inventory_queries': '''
        addon.Panel:Initialize()
        assert(#addon.Panel.themeButtons==10)
        GetItemCount=function() error('theme switching must not query inventory') end
        local seen={}
        for i,tile in ipairs(addon.Panel.themeButtons) do
            assert(not seen[tile.themeKey]); seen[tile.themeKey]=true
            tile.scripts.OnClick()
            assert(addon.Theme:Palette().key==addon.Theme.palettes[i].key)
            assert(CraftRosterDB.settings.theme==tile.themeKey)
            assert(tile.Check:IsShown())
            for j,other in ipairs(addon.Panel.themeButtons) do
                assert(other.Check:IsShown()==(i==j))
            end
            local p=addon.Theme:Palette()
            assert(addon.Panel.themePreview.backdropColor[1]==p.background[1])
            assert(addon.Panel.themePreview.Selected.selected)
        end
        addon.Theme:SetPalette('gold')
        assert(not addon.Panel.themePreview.ThemeMark:IsShown())
        assert(not addon.Panel.resetAppearance.ThemeBorder:IsShown())
        assert(#sent==0)
    ''',
    'palette_accents_meet_readable_contrast': '''
        local function linear(c) if c<=0.04045 then return c/12.92 end return ((c+0.055)/1.055)^2.4 end
        local function luminance(c) return 0.2126*linear(c[1])+0.7152*linear(c[2])+0.0722*linear(c[3]) end
        for _,p in ipairs(addon.Theme.palettes) do
            local ratio=(luminance(p.accent)+0.05)/(luminance(p.background)+0.05)
            assert(ratio>=4.5,p.key..' heading contrast')
            if p.key=='contrast' then assert(ratio>=7) end
        end
    ''',
}


class AppearanceTests(unittest.TestCase):
    pass


for runtime in ('lua51', 'luajit21'):
    for profile in ('modern', 'legacy', 'minimal'):
        for name, code in CASES.items():
            def check(self, runtime=runtime, profile=profile, name=name, code=code):
                lua = fresh(runtime, profile)
                if name == 'responsive_recipe_materials_and_fixed_actions_do_not_overlap':
                    lua.execute((Path(__file__).parent / 'layout_mock.lua').read_text())
                lua.execute(code)
            setattr(AppearanceTests, f'test_{runtime}_{profile}_{name}', check)
