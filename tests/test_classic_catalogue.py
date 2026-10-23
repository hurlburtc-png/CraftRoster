"""Catalogue-wide Classic source joins and their default in-game presentation."""
from pathlib import Path
import json
import unittest
from test_work_orders import fresh

ROOT=Path(__file__).resolve().parents[1]
CASES={
'instance_and_boss_drops_show_instance_without_coordinate_noise': '''
 local c=addon.ClassicSources
 local text=c:Format(17635,13519,{},false)
 assert(text:find('General Drakkisath',1,true) and text:find('Upper Blackrock Spire (instance)',1,true))
 assert(not text:find('coordinates:',1,true) and not text:find('Coordinates:',1,true))
 CraftRosterDB.recipes[13898]={name='Fiery Weapon',profession='Enchanting',recipeItemID=11207}
 text=addon.RecipeSources:Summary(13898)
 assert(text:find('Pyromancer Loregrain',1,true) and text:find('Blackrock Depths',1,true))
 assert(not text:find('coordinates',1,true))
 local open={kind='mob',zone='Western Plaguelands'}
 assert(not c:IsInstanced(open))
 assert(c:IsInstanced({kind='mob',zone='Scholomance Chamber Of Summoning'}))
 assert(not c:IsInstanced({kind='vendor',zone='Blackrock Depths'}),'drop-only coordinate exception')
''',
'trainer_has_full_title_coordinates_skill_and_only_player_faction': '''
 UnitFactionGroup=function() return 'Alliance' end
 CraftRosterDB.recipes[2385]={name='Brown Linen Vest',profession='Tailoring'}
 local s=addon.RecipeSources:Summary(2385)
 assert(s:find('Trainer:',1,true) and s:find('Tailor>',1,true))
 assert(s:find('Classic location:',1,true) and s:find('Classic coordinates:',1,true))
 assert(s:find('Classic training skill: Tailoring 10',1,true))
 local full=addon.RecipeSources:Format(2385)
 assert(full:find('Georgio Bolero <Artisan Tailor>',1,true))
 assert(not full:find('Magar',1,true) and not full:find('listings withheld',1,true))
 UnitFactionGroup=function() return 'Horde' end
 full=addon.RecipeSources:Format(2385)
 assert(full:find('Magar <Expert Tailor>',1,true) and not full:find('Georgio Bolero',1,true))
''',
'classic_default_precedes_stale_text_and_name_only_library_data': '''
 UnitFactionGroup=function() return 'Alliance' end
 CraftRosterDB.recipes[3454]={name='Frost Oil',profession='Alchemy',sourceText='Vendor: 99999'}
 local s=addon.RecipeSources:Format(3454)
 assert(s:find("Bro'kin",1,true) and s:find('38.24, 38.87',1,true))
 assert(not s:find('name unavailable',1,true) and not s:find('Vendor sources:',1,true))
 local brief=addon.RecipeSources:Summary(3454)
 assert(brief:find("Bro'kin",1,true) and brief:find('Classic coordinates:',1,true))
''',
'new_enchanting_scroll_does_not_hide_exact_classic_trainer_reference': '''
 UnitFactionGroup=function() return 'Alliance' end
 CraftRosterDB.recipes[7420]={name='Enchant Chest - Minor Health',profession='Enchanting',recipeItemID=273459}
 local record=addon.ClassicSources:Get(7420,273459)
 assert(record and record.sources[1].kind=='trainer')
 local s=addon.RecipeSources:Format(7420)
 assert(s:find('Trainer:',1,true) and s:find('Classic coordinates:',1,true))
 assert(not addon.ClassicSources:Get(7420,99999),'saved teaching-item identity must still match')
''',
'every_generated_edge_resolves_to_a_named_geographic_record': '''
 local d=addon.ClassicSourceData; local count=0
 for spell,record in pairs(d.recipes) do
  count=count+1;assert(record.spellID==spell and #record.sources>0)
  for _,edge in ipairs(record.sources) do
   local npc=d.npcs[edge.npcID]
   assert(npc and type(npc.name)=='string' and #npc.name>0 and type(npc.zone)=='string')
   if npc.x~=nil then assert(npc.x>=0 and npc.x<=100 and npc.y>=0 and npc.y<=100) end
   if edge.kind=='trainer' then
    assert(type(npc.title)=='string' and edge.requiredSkill>=0 and edge.profession)
    assert(npc.faction=='Alliance' or npc.faction=='Horde' or npc.faction=='Neutral')
   end
  end
 end
 assert(count>=1000,'catalogue expansion must not regress to a few curated examples')
''',
}
class CatalogueTests(unittest.TestCase):
 def test_coverage_report_accounts_for_every_catalogue_recipe(self):
  report=json.loads((ROOT/'data/classic-source-coverage.json').read_text())
  self.assertEqual(len(report['recipes']),report['summary']['catalogue'])
  self.assertEqual(len({r['spellID'] for r in report['recipes']}),len(report['recipes']))
  self.assertEqual(sum(report['summary']['byStatus'].values()),len(report['recipes']))
  self.assertGreaterEqual(report['summary']['covered'],1000)

for runtime in ('lua51','luajit21'):
 for profile in ('modern','legacy','minimal'):
  for name,code in CASES.items():
   def check(self,runtime=runtime,profile=profile,code=code):
    lua=fresh(runtime,profile);lua.execute(code)
   setattr(CatalogueTests,f'test_{runtime}_{profile}_{name}',check)
