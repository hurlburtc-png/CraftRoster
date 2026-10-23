"""Exact-ID location records; unsafe or incompatible points never create markers."""
import unittest
from test_work_orders import fresh

FIXTURE = '''
local point={kind='vendor',npcID=123,name='Test Vendor',zone='Test Zone',x=25,y=75,
 status='confirmed',url='https://example.org/forever/123',revision='fixture',checked='2026-10-22',uiMapID=999}
addon.RecipeLocations.bySpell[42]={point}
CraftRosterDB.recipes[42]={name='Test craft',profession='Alchemy'}
C_Map={GetMapInfo=function(id) assert(id==999); return {name='Test Zone'} end}
'''
CASES = {
'trainers_show_recipe_skill_and_only_player_or_neutral_faction': FIXTURE+'''
 local root=addon.RecipeLocations.bySpell[42][1]
 root.kind='trainer'; root.profession='Alchemy'; root.requiredSkill=175; root.faction='Alliance'; root.name='Friendly Teacher'
 local function copy(name,faction)
  local r={}; for k,v in pairs(root) do r[k]=v end; r.name=name; r.faction=faction; return r
 end
 local neutral=copy('Neutral Teacher','Neutral')
 local enemy=copy('Enemy Teacher','Horde')
 local unknown=copy('Unknown Teacher',nil)
 addon.RecipeLocations.bySpell[42]={root,neutral,enemy,unknown}
 UnitFactionGroup=function() return 'Alliance','localized alliance' end
 local records=addon.RecipeLocations:Get(42)
 assert(#records==2 and records[1].name=='Friendly Teacher' and records[2].name=='Neutral Teacher')
 assert(addon.RecipeLocations:Label(records[1]):find('Requires Alchemy 175',1,true))
 UnitFactionGroup=function() return 'Horde' end
 assert(not addon.RecipeLocations:CopyText(records[1]),'faction rechecked at action time')
 records=addon.RecipeLocations:Get(42)
 assert(#records==2 and records[2].name=='Enemy Teacher')
 UnitFactionGroup=nil
 records=addon.RecipeLocations:Get(42); assert(#records==1 and records[1].name=='Neutral Teacher')
''',
'unknown_trainer_faction_skill_and_opaque_text_do_not_leak_names': FIXTURE+'''
 UnitFactionGroup=function() return 'Alliance' end
 local root=addon.RecipeLocations.bySpell[42][1]
 root.kind='trainer'; root.profession='Alchemy'; root.faction='Alliance'; root.requiredSkill=nil; root.name='Unverified Teacher'
 CraftRosterDB.recipes[42].sourceText='Enemy Teacher in Other City'
 local db=LibStub('LibProfessionDB-1.0')
 db.GetRecipeSources=function() return {trainer={{id=123,name='Unverified Teacher'},total=99}} end
 assert(#addon.RecipeLocations:Get(42)==0)
 local text=addon.RecipeSources:Format(42)
 assert(text:find('Trainer listings withheld',1,true))
 assert(not text:find('Enemy Teacher',1,true) and not text:find('Unverified Teacher',1,true))
 assert(not text:find('Trainer sources: 99',1,true))
 root.requiredSkill=175
 text=addon.RecipeSources:Format(42)
 assert(text:find('Trainer: Unverified Teacher',1,true) and text:find('Requires Alchemy 175',1,true))
 root.faction=nil; assert(#addon.RecipeLocations:Get(42)==0)
 root.faction='Alliance'; root.requiredSkill='175'; assert(#addon.RecipeLocations:Get(42)==0)
 root.requiredSkill=175; root.status='reference'; assert(#addon.RecipeLocations:Get(42)==0)
''',
'exact_ids_and_no_name_inference': '''
 local records=addon.RecipeLocations:Get(1255143)
 assert(#records==1 and records[1].npcID==258306 and not records[1].confirmed)
 assert(not addon.RecipeLocations:CopyText(records[1]))
 assert(not addon.RecipeLocations:Navigate(records[1]))
 CraftRosterDB.recipes[9999]={name='Moonglow Boots',sourceText='Ironforge 39.3, 33.7',sourceLocations={{status='confirmed'}}}
 assert(#addon.RecipeLocations:Get(9999)==0)
 records[1].status='confirmed'
 assert(not addon.RecipeLocations:Get(1255143)[1].confirmed,'returned records cannot approve bundled data')
''',
'modern_tomtom_uses_target_zone_and_normalized_coordinates': FIXTURE+'''
 local calls=0
 TomTom={AddWaypoint=function(self,id,x,y,options)
  assert(id==999 and x==0.25 and y==0.75 and not options.persistent)
  assert(options.title:find('Test Vendor',1,true)); calls=calls+1; return 'uid'
 end}
 local record=addon.RecipeLocations:Get(42)[1]
 assert(addon.RecipeLocations:CopyText(record)=='/way #999 25 75 Test Vendor')
 assert(addon.RecipeLocations:Navigate(record) and calls==1)
''',
'legacy_tomtom_resolves_its_own_indices': FIXTURE+'''
 C_Map=nil
 TomTom={GetZoneInfo=function(self,name) assert(name=='Test Zone'); return 2,7 end,
 AddMFWaypoint=function(self,c,z,x,y,options) assert(c==2 and z==7 and x==0.25 and y==0.75); return {} end}
 assert(addon.RecipeLocations:Navigate(addon.RecipeLocations:Get(42)[1]))
 TomTom.GetZoneInfo=function() return nil end
 assert(not addon.RecipeLocations:Navigate(addon.RecipeLocations:Get(42)[1]))
''',
'native_waypoint_capability_and_errors_are_guarded': FIXTURE+'''
 local calls=0
 UiMapPoint={CreateFromCoordinates=function(id,x,y) return {id=id,x=x,y=y} end}
 C_Map.SetUserWaypoint=function(p) assert(p.id==999 and p.x==0.25 and p.y==0.75); calls=calls+1 end
 local record=addon.RecipeLocations:Get(42)[1]
 assert(addon.RecipeLocations:Navigate(record) and calls==1)
 C_Map.CanSetUserWaypointOnMap=function() return false end
 assert(not addon.RecipeLocations:Navigate(record) and calls==1)
 C_Map.CanSetUserWaypointOnMap=nil
 C_Map.SetUserWaypoint=function() error('unsupported') end
 assert(not addon.RecipeLocations:Navigate(record))
''',
'malformed_and_missing_evidence_never_navigate': FIXTURE+'''
 local records=addon.RecipeLocations.bySpell[42]
 for _,bad in ipairs({-1,101,0/0,math.huge,'25'}) do
  records[1].x=bad; assert(#addon.RecipeLocations:Get(42)==0)
 end
 records[1].x=25; records[1].checked=nil
 assert(not addon.RecipeLocations:Get(42)[1].confirmed)
 records[1].checked='2026-10-22'; records[1].status='reference'
 assert(not addon.RecipeLocations:Backend(records[1]))
''',
'precision_is_preserved_and_optional_map_errors_are_safe': FIXTURE+'''
 local record=addon.RecipeLocations:Get(42)[1]
 record.x=25.1234; record.y=75.5678
 assert(addon.RecipeLocations:CopyText(record):find('25.1234 75.5678',1,true))
 C_Map.GetMapInfo=function() error('not available') end
 TomTom={AddWaypoint=function() error('must not call') end}
 assert(not addon.RecipeLocations:Navigate(record))
 C_Map.GetMapInfo=function() return {name='Test Zone'} end
 TomTom.AddWaypoint=function() error('addon error') end
 assert(not addon.RecipeLocations:Navigate(record))
''',
'multiple_locations_and_mob_area_keep_their_own_coordinates': FIXTURE+'''
 local second={kind='mob',npcID=124,name='Test Mob',zone='Other Zone',x=40,y=50,area=true,
 status='confirmed',url='https://example.org/124',revision='fixture',checked='2026-10-22'}
 table.insert(addon.RecipeLocations.bySpell[42],second)
 local records=addon.RecipeLocations:Get(42)
 assert(#records==2 and addon.RecipeLocations:Label(records[2]):find('spawn area',1,true))
 assert(addon.RecipeLocations:CopyText(records[2])=='Other Zone: 40, 50 — Test Mob')
 assert(not addon.RecipeLocations:Backend(records[2]))
''',
'ui_buttons_follow_selected_recipe_and_hide_old_rows': FIXTURE+'''
 addon.Directory:Toggle()
 addon.Directory.selectedRecipe={id=42,name='Test craft',profession='Alchemy',crafters={}}
 addon.SelectedCraft:Refresh()
 assert(#addon.SelectedCraft.locationRows==0,'collapsed source must not create location buttons')
 addon.SelectedCraft.sourcesExpanded=true
 addon.SelectedCraft:Refresh()
 local row=addon.SelectedCraft.locationRows[1]
 assert(row:IsShown() and row.record.npcID==123 and row.Copy:IsEnabled() and not row.Map:IsEnabled())
 local value
 StaticPopup_Show=function(which,_,__,data) assert(which=='CRAFTROSTER_COPY_LOCATION'); value=data end
 row.Copy.scripts.OnClick(); assert(value:find('/way #999',1,true))
 addon.Directory.selectedRecipe={id=1255143,name='Moonglow Boots',profession='Leatherworking',crafters={}}
 addon.SelectedCraft:Refresh()
 assert(not row:IsShown(),'new recipe defaults to collapsed location details')
 addon.SelectedCraft.sourcesExpanded=true
 addon.SelectedCraft:Refresh()
 assert(not row:IsShown(),'unverified acquisition must not display disabled navigation controls')
 assert(#addon.RecipeLocations:Get(1255143)>0,'unverified source details remain available in text')
 assert(value:find('/way #999',1,true),'switching recipes must not generate a new waypoint')
 addon.Directory.selectedRecipe={id=99999,name='Unknown',profession='Alchemy',crafters={}}
 addon.SelectedCraft:Refresh(); assert(not row:IsShown())
''',
}
class LocationTests(unittest.TestCase): pass
for runtime in ('lua51','luajit21'):
 for profile in ('modern','legacy','minimal'):
  for name,code in CASES.items():
   def check(self,runtime=runtime,profile=profile,code=code):
    lua=fresh(runtime,profile);lua.execute(code)
   setattr(LocationTests,f'test_{runtime}_{profile}_{name}',check)
