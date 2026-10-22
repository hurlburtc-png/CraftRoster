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
        panel.resetAppearance.scripts.OnClick()
        assert(not CraftRosterDB.settings.uiScaleEnabled and CraftRosterDB.settings.uiScale==1)
        assert(addon.Theme:Palette().key=='gold')
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
    ''',
    'theme_menu_choices_apply_distinct_palettes': '''
        local menus={}
        UIDropDownMenu_Initialize=function(dropdown,callback) menus[dropdown]=callback end
        UIDropDownMenu_CreateInfo=function() return {} end
        local choices={}
        UIDropDownMenu_AddButton=function(info) choices[#choices+1]=info end
        addon.Panel:Initialize()
        menus[addon.Panel.themeDropdown](addon.Panel.themeDropdown,1)
        assert(#choices==5)
        for i,choice in ipairs(choices) do
            choice.func()
            assert(addon.Theme:Palette().key==addon.Theme.palettes[i].key)
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
