"""Classic evidence cannot become a confirmed Forever location or rate."""
import unittest
from test_work_orders import fresh

CASES={
'generated_source_cache_evicts_without_losing_shared_facts_or_reviewed_records': '''
 local classic=addon.ClassicSources
 local data=addon.ClassicSourceData
 local reviewed=classic.records[20034]
 data.npcs[900001]={npcID=900001,name='Cache vendor',zone='Test zone',x=1,y=2}
 for i=1,70 do
  data.recipes[900000+i]={spellID=900000+i,itemID=800000+i,sources={{kind='vendor',npcID=900001}}}
 end
 local first=classic:Get(900001,800001)
 assert(first==classic:Get(900001,800001),'hot entries should reuse their expansion')
 for i=2,70 do assert(classic:Get(900000+i,800000+i)) end
 assert(not classic.records[900001],'generated copies must not grow permanent reviewed records')
 local rebuilt=classic:Get(900001,800001)
 assert(rebuilt and rebuilt~=first and rebuilt.sources[1].name=='Cache vendor')
 assert(data.recipes[900001].sources[1].name==nil and data.npcs[900001].provider==nil)
 assert(classic.records[20034]==reviewed and classic:Get(20034,16252)==reviewed)
 assert(not classic:Get(900001,1),'wrong teaching items must still be rejected')
''',

'exact_recipe_item_pair_and_changed_forever_ids': '''
 local c=addon.ClassicSources
 assert(c:Get(20034,16252) and not c:Get(20034,99999) and not c:Get(99999,16252))
 CraftRosterDB.recipes[20034]={name='Crusader',profession='Enchanting',recipeItemID=99999}
 local data=addon.RecipeSources:Get(20034)
 assert(not data.reference and not data.name:find('Crusader',1,true))
 assert(not data.binding:find('Classic reference',1,true))
 local text=addon.RecipeSources:Format(20034)
 assert(not text:find('Classic drop estimate: ~0.43%',1,true))
 CraftRosterDB.recipes[1255143]={name='Moonglow Boots',profession='Leatherworking'}
 assert(not c:Get(1255143,252764),'new Forever craft must not inherit a same-name Classic source')
''',
'classic_sources_are_labelled_and_coordinates_need_their_own_evidence': '''
 local source=addon.ClassicSources.records[20034].sources[1]
 source.x=54.3;source.y=23.5;source.area=true;source.coordinateURL=nil
 local text=addon.ClassicSources:Format(20034,16252,{},true)
 assert(text:find('Classic coordinates: unknown',1,true))
 source.coordinateURL='https://example.org/classic/npc/4494'
 text=addon.ClassicSources:Format(20034,16252,{},true)
 assert(text:find('Classic coordinates: 54.3, 23.5 (spawn area)',1,true))
 assert(text:find('Classic reference — unconfirmed in Forever',1,true))
 assert(text:find('Classic drop estimate: ~0.43%',1,true) and text:find('Forever location and drop rate: unknown',1,true))
 assert(text:find('navigation is disabled',1,true))
 local record={era='Classic',kind='mob',npcID=4494,name=source.name,zone=source.zone,x=54.3,y=23.5,
 status='confirmed',url=source.coordinateURL,revision='fixture',checked='2026-10-22'}
 assert(not addon.RecipeLocations:Navigate(record) and not addon.RecipeLocations:CopyText(record))
''',
'forever_location_wins_but_classic_rate_is_separately_labelled': '''
 local locations={{confirmed=true,kind='mob',npcID=4494,name='Scarlet Spellbinder',zone='New Forever Zone',x=10,y=20}}
 local text=addon.ClassicSources:Format(20034,16252,locations)
 assert(text:find('Classic drop estimate: ~0.43%',1,true))
 assert(not text:find('Western Plaguelands',1,true) and not text:find('Classic coordinates',1,true))
 assert(text:find('Forever location confirmed; Forever drop rate unknown',1,true))
 CraftRosterDB.recipes[20034]={name='Crusader',profession='Enchanting',sourceText='Stale location text'}
 addon.RecipeLocations.bySpell[20034]={{kind='mob',npcID=4494,name='Scarlet Spellbinder',zone='New Forever Zone',
  x=10,y=20,status='confirmed',url='https://example.org/forever/4494',revision='r1',checked='2026-10-22'}}
 local formatted=addon.RecipeSources:Format(20034)
 assert(formatted:find('New Forever Zone',1,true) and not formatted:find('Stale location text',1,true))
 assert(not formatted:find('Western Plaguelands',1,true))
 locations[1].npcID=11111
 assert(not addon.ClassicSources:Format(20034,16252,locations),'a different NPC cannot inherit the Classic rate')
 locations[1].npcID=4494;locations[1].kind='vendor'
 assert(not addon.ClassicSources:Format(20034,16252,locations),'a vendor is not a confirmed drop source')
''',
'confirmed_forever_rate_requires_separate_evidence_and_suppresses_classic_rate': '''
 local location={confirmed=true,kind='mob',npcID=4494,dropRate={percent=2.5}}
 assert(not addon.ClassicSources:ForeverRate(location))
 assert(addon.ClassicSources:Format(20034,16252,{location}))
 location.dropRate={percent=0,era='Forever',confirmed=true,url='https://example.org/forever/4494',revision='r1',checked='2026-10-22'}
 location.dropRate.era='Classic'
 assert(not addon.ClassicSources:ForeverRate(location),'Classic rate cannot be promoted with a confirmed Forever location')
 location.dropRate.era='Forever'
 assert(addon.ClassicSources:ForeverRate(location)==0)
 assert(not addon.ClassicSources:Format(20034,16252,{location}))
 location.dropRate.percent=101;assert(not addon.ClassicSources:ForeverRate(location))
 location.dropRate.percent=0/0;assert(not addon.ClassicSources:ForeverRate(location))
''',
'unknown_rates_remain_unknown_and_malformed_coordinates_are_not_printed': '''
 local source=addon.ClassicSources.records[20034].sources[1]
 source.chance=nil;source.x=math.huge;source.y=-1;source.coordinateURL='https://example.org/classic/4494'
 local text=addon.ClassicSources:Format(20034,16252,{})
 assert(text:find('Classic drop estimate: unknown',1,true) and text:find('Classic coordinates: unknown',1,true))
 assert(not text:find('inf',1,true))
 source.chance='0.43'; text=addon.ClassicSources:Format(20034,16252,{})
 assert(text:find('Classic drop estimate: unknown',1,true))
''',
'classic_trainer_references_require_faction_and_recipe_training_skill': '''
 local trainer={kind='trainer',npcID=123,name='Alliance Teacher',zone='Classic City',faction='Alliance',profession='Alchemy',
 requiredSkill=175,url='https://example.org/classic/123'}
 addon.ClassicSources.records[42]={spellID=42,trainerOnly=true,checked='2026-10-22',sources={trainer}}
 UnitFactionGroup=function() return 'Alliance' end
 local text=addon.ClassicSources:Format(42,nil,{})
 assert(text:find('Classic training skill: Alchemy 175',1,true) and text:find('Alliance Teacher',1,true))
 UnitFactionGroup=function() return 'Horde' end
 assert(not addon.ClassicSources:Format(42,nil,{}))
 trainer.faction='Neutral';assert(addon.ClassicSources:Format(42,nil,{}))
 trainer.requiredSkill=nil;assert(not addon.ClassicSources:Format(42,nil,{}))
 assert(not addon.ClassicSources:Get(42,999),'itemless trainer record must not override an item-taught spell')
''',
'compact_sources_are_capped_and_expanded_provenance_remains_available': '''
 local source=addon.ClassicSources.records[20034].sources[1]
 local many={}
 for i=1,5 do local s={};for k,v in pairs(source) do s[k]=v end;s.name='Mob '..i;many[i]=s end
 addon.ClassicSources.records[20034].sources=many
 local text=addon.ClassicSources:Format(20034,16252,{},true)
 assert(text:find('Mob 2',1,true) and not text:find('Mob 3',1,true) and text:find('and 3 more',1,true))
 assert(not text:find('https://',1,true))
 text=addon.ClassicSources:Format(20034,16252,{},false)
 assert(text:find('Mob 5',1,true) and text:find(source.url,1,true))
''',
'curated_vendor_references_filter_faction_and_do_not_show_drop_rates': '''
 UnitFactionGroup=function() return 'Alliance' end
 local text=addon.ClassicSources:Format(7255,6053,{},false)
 assert(text:find('Xandar Goodbeard',1,true) and text:find('Kzixx',1,true) and not text:find("Hula'mahi",1,true))
 assert(text:find('82.47, 63.35',1,true) and text:find('QuestieDB Classic',1,true))
 assert(not text:find('drop rate: unknown',1,true) and not text:find('drop estimate',1,true))
 UnitFactionGroup=function() return 'Horde' end
 text=addon.ClassicSources:Format(7255,6053,{},false)
 assert(not text:find('Xandar Goodbeard',1,true) and text:find("Hula'mahi",1,true))
 assert(not addon.ClassicSources:Get(3454,252764))
''',
'malformed_optional_fields_are_safe_and_same_npc_known_rate_wins': '''
 local record=addon.ClassicSources.records[20034]
 local source=record.sources[1]
 source.requirements={};source.provider={};source.faction={};source.coordinateURL={};record.checked={}
 local text=addon.ClassicSources:Format(20034,16252,{},false)
 assert(text:find('Classic drop estimate',1,true))
 local known={kind='mob',confirmed=true,npcID=4494,dropRate={era='Forever',percent=2.5,confirmed=true,
  url='https://example.org/rate',revision='r1',checked='2026-10-22'}}
 local same={kind='mob',confirmed=true,npcID=4494}
 assert(not addon.ClassicSources:Format(20034,16252,{known,same}))
 assert(not addon.ClassicSources:Format(20034,16252,{same,known}))
 known.kind='vendor'; assert(not addon.ClassicSources:ForeverRate(known))
''',
'selected_ui_reflows_fallback_without_new_scroll_or_live_database_scans': '''
 addon.Directory:Toggle()
 addon.Directory.selectedRecipe={id=20034,name='Crusader',profession='Enchanting',crafters={}}
 addon.SelectedCraft:Refresh()
 local tab=addon.Directory.frame.ProfessionsTab
 assert(tab.RecipeSource.Text:GetText():find('Classic drop estimate',1,true))
 assert(tab.RecipeSource.Text:GetText():find('Classic reference',1,true))
 assert(#addon.RecipeLocations:Get(20034)==0,'Classic references must not become navigable location records')
 addon.SelectedCraft.sourceToggle.scripts.OnClick()
 assert(tab.RecipeSource.Text:GetText():find('https://',1,true))
''',
}
class ClassicSourceTests(unittest.TestCase):pass
for runtime in ('lua51','luajit21'):
 for profile in ('modern','legacy','minimal'):
  for name,code in CASES.items():
   def check(self,runtime=runtime,profile=profile,code=code):
    lua=fresh(runtime,profile);lua.execute(code)
   setattr(ClassicSourceTests,f'test_{runtime}_{profile}_{name}',check)
