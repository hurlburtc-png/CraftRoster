"""Build offline Classic acquisition references for the entire bundled catalogue.

Inputs are pinned, downloaded source snapshots, never executed SQL. Run with
python scripts/build_classic_sources.py /path/to/snapshots
See docs/CLASSIC_SOURCE_BUILD.md for URLs, licences and interpretation limits.
"""
import argparse
import csv
import gzip
import hashlib
import json
import re
from collections import Counter, defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
QUESTIE = '1f538335cfbb240c14a97c340f48c555fdc8a52b'
CMANGOS = '77b848e78fe31bdd0c5562922be49a4e8e5e79df'
PROFESSIONS = {171:'Alchemy',164:'Blacksmithing',185:'Cooking',333:'Enchanting',
               202:'Engineering',129:'First Aid',356:'Fishing',165:'Leatherworking',
               186:'Mining',197:'Tailoring'}
INPUT_HASHES={
 'classic.sql.gz':'4f92db520868ab4e566726f68b5b2e380ae781209beaf22237b4f7f04600d0c0',
 'classicNpcDB.lua':'ee4a241db3ff89e5f0883b688b58920c1121f5617202ecba81d90b17271ccd54',
 'classicItemDB.lua':'987d037b6df94d5b0b1dc326a1670581e3abb952736a4ae055fd9f161328b71c',
 'zones.lua':'20e7af36ec38f6f1640368d1c2030315cbdd068d895578c1374591b2f5dd9216',
 'instanceIdToAreaId.lua':'b10a80e89df46683fde3d5d27cbd715d409f8e4218b1311c0081d2a180b05963'}
ROW = re.compile(r"\(((?:'(?:\\.|[^'\\])*'|[^'()])*)\)")


def table(sql, name):
    schema = re.search(r'CREATE TABLE `' + name + r'`.*?;', sql, re.S)
    columns = re.findall(r'^  `([^`]+)`', schema[0], re.M)
    result = []
    for insert in re.finditer(r'INSERT INTO `' + name + r'` VALUES (.*?);\n', sql, re.S):
        for match in ROW.finditer(insert[1]):
            values = next(csv.reader([match[1]], quotechar="'", escapechar='\\'))
            assert len(values) == len(columns), (name, len(values), len(columns))
            result.append(dict(zip(columns, values)))
    assert result, name
    return result


def lua_value(value):
    if value is None: return 'nil'
    if value is True: return 'true'
    if value is False: return 'false'
    if isinstance(value, str): return json.dumps(value, ensure_ascii=False)
    if isinstance(value, (float, int)): return str(value)
    if isinstance(value, list): return '{' + ','.join(map(lua_value, value)) + '}'
    return '{' + ','.join('['+lua_value(k)+']='+lua_value(v) for k,v in value.items()) + '}'


def build(folder):
    from lupa.lua51 import LuaRuntime
    for filename,expected in INPUT_HASHES.items():
        if hashlib.sha256((folder/filename).read_bytes()).hexdigest()!=expected:
            raise ValueError('Unreviewed source snapshot: '+filename)
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute((ROOT/'tests/wow_mock.lua').read_text())
    lua.execute("configure('modern')")
    addon = lua.table()
    # Only the existing vendored library is needed to enumerate the catalogue.
    for line in (ROOT/'CraftRoster.toc').read_text().splitlines():
        if line.startswith('vendor/') and line.endswith('.lua'):
            lua.compile((ROOT/line).read_text())('CraftRoster', addon)
    db = lua.eval("(LibStub('LibProfessionDB-1.0'))")
    catalogue = {}
    for prof, name in PROFESSIONS.items():
        for spell, data in db.GetRecipes(db, prof).items():
            item = db.GetRecipeItem(db, spell)[0]
            catalogue[spell] = {'profession':name, 'item':item,
                              'name':db.GetName(db, prof, spell),
                              'output':data['craftedItemId'],
                              'autoTaught':bool(db.IsAutoTaughtRecipe(db,spell)),
                              'hidden':bool(db.IsHiddenRecipe(db,spell))}
    def questie(filename, field):
        raw=(folder/filename).read_text()
        return lua.execute(raw.split('QuestieDB.'+field+' = [[',1)[1].rsplit(']]',1)[0])
    npcs = questie('classicNpcDB.lua', 'npcData')
    items = questie('classicItemDB.lua', 'itemData')
    zones = {int(v):k.replace('_',' ').title() for k,v in
             re.findall(r'^\s+([A-Z_0-9]+) = (\d+),', (folder/'zones.lua').read_text(), re.M)}
    zones.update({1519:'Stormwind City',1537:'Ironforge',1497:'Undercity',1637:'Orgrimmar',
                  1657:'Darnassus',1638:'Thunder Bluff',17:'The Barrens',33:'Stranglethorn Vale'})
    sql = gzip.open(folder/'classic.sql.gz','rt').read()
    zone_ids={k:int(v) for k,v in re.findall(r'^\s+([A-Z_0-9]+) = (\d+),', (folder/'zones.lua').read_text(), re.M)}
    instance_zones={int(k):zone_ids[v] for k,v in re.findall(r'\[(\d+)\] = ZoneDB.zoneIDs\.([A-Z_0-9]+)', (folder/'instanceIdToAreaId.lua').read_text()) if v in zone_ids}
    spells = {int(r['Id']):r for r in table(sql,'spell_template')}
    creatures = {int(r['Entry']):r for r in table(sql,'creature_template')}
    sqlitems = {int(r['entry']):r for r in table(sql,'item_template')}
    quests = {int(r['entry']):r for r in table(sql,'quest_template')}
    quest_spells=defaultdict(set)
    for quest,r in quests.items():
        for column in ('RewSpell','RewSpellCast'):
            sid=int(r[column])
            if sid in catalogue:quest_spells[sid].add(quest)
            teach=spells.get(sid,{})
            for i in (1,2,3):
                if teach.get('Effect'+str(i))=='36':quest_spells[int(teach['EffectTriggerSpell'+str(i)])].add(quest)
    # Resolve vendor templates and nested world-drop reference pools offline.
    vendors=defaultdict(set);vendor_templates=defaultdict(list)
    for r in creatures.values():vendor_templates[int(r['VendorTemplateId'])].append(int(r['Entry']))
    for tab in ('npc_vendor','npc_vendor_template'):
        for r in table(sql,tab):
            ids=[int(r['entry'])] if tab=='npc_vendor' else vendor_templates[int(r['entry'])]
            for npc in ids:vendors[int(r['item'])].add(npc)
    loot_npcs=defaultdict(set)
    for npc,r in creatures.items():loot_npcs[int(r['LootId'])].add(npc)
    direct=defaultdict(set);refs=defaultdict(set);parents=defaultdict(set)
    for tab in ('creature_loot_template','reference_loot_template'):
        for r in table(sql,tab):
            entry=int(r['entry']);ref=int(r['mincountOrRef'])
            if ref<0:parents[-ref].add((tab,entry))
            elif float(r['ChanceOrQuestChance'])>=0:
                (direct if tab=='creature_loot_template' else refs)[int(r['item'])].add(entry)
    def dropped_by(item):
        pools=set(direct[item]);seen=set();pending=list(refs[item])
        while pending:
            ref=pending.pop()
            if ref in seen:continue
            seen.add(ref)
            for tab,entry in parents[ref]:
                if tab=='creature_loot_template':pools.add(entry)
                else:pending.append(entry)
        return set().union(*(loot_npcs[p] for p in pools)) if pools else set()
    rewards=defaultdict(set)
    for quest,r in quests.items():
        for col in [f'RewChoiceItemId{i}' for i in range(1,7)]+[f'RewItemId{i}' for i in range(1,5)]:
            if int(r[col]):rewards[int(r[col])].add(quest)
    templates = defaultdict(list)
    for r in creatures.values(): templates[int(r['TrainerTemplateId'])].append(int(r['Entry']))
    trainers = defaultdict(list)
    for tab in ('npc_trainer','npc_trainer_template'):
        for r in table(sql,tab):
            teach=spells.get(int(r['spell']),{})
            for i in (1,2,3):
                if teach.get('Effect'+str(i)) != '36': continue
                target=int(teach['EffectTriggerSpell'+str(i)])
                profession=PROFESSIONS.get(int(r['reqskill'])) or (catalogue[target]['profession'] if target in catalogue else None)
                if target not in catalogue:
                    # The profession's initial recipes are granted by learning
                    # the profession, not sold as individual trainer spells.
                    profession=next((PROFESSIONS.get(int(spells.get(target,{}).get('EffectMiscValue'+str(j),'0')))
                                     for j in (1,2,3) if spells.get(target,{}).get('Effect'+str(j))=='118'),None)
                    targets=[sid for sid,c in catalogue.items() if c['autoTaught'] and c['profession']==profession]
                else:targets=[target]
                if not targets or profession is None:continue
                requirements=[]
                for j in (1,2,3):
                    ability=r['ReqAbility'+str(j)]
                    if ability not in ('NULL','0'):
                        requirements.append(spells.get(int(ability),{}).get('SpellName','additional prerequisite ability'))
                if int(r['condition_id']):requirements.append('additional Classic trainer condition; check the source before travelling')
                requirements='; '.join(requirements)
                ids=[int(r['entry'])] if tab=='npc_trainer' else templates[int(r['entry'])]
                for sid in targets:
                    if catalogue[sid]['profession']!=profession:continue
                    for npc in ids: trainers[sid].append((npc,int(r['reqskillvalue']),int(r['reqlevel']),requirements))
    npc_maps=defaultdict(set)
    for r in table(sql,'creature'):
        for key in ('id','id2','id3'):
            if key in r and int(r[key]):npc_maps[int(r[key])].add(int(r['map']))
    npcdata = {}
    def npc_info(npc):
        if npc in npcdata: return npcdata[npc]
        q=npcs[npc]
        if not q: return None
        zone=q[9]
        if zone not in zones:
            zone=next((z for z in sorted(q[7].keys()) if z in zones),None) if q[7] else None
            if zone is None:
                candidates={instance_zones[m] for m in npc_maps[npc] if m in instance_zones}
                if len(candidates)==1:zone=candidates.pop()
        if zone is None: return None
        coord=q[7] and q[7][zone] and q[7][zone][1]
        hascoords=coord and all(isinstance(coord[i],(int,float)) and 0<=coord[i]<=100 for i in (1,2))
        friendly=q[13]
        record={'npcID':npc,'name':q[1],'zone':zones[zone]}
        if hascoords:record.update(x=coord[1],y=coord[2])
        title=q[14] or creatures.get(npc,{}).get('SubName')
        if title and title!='NULL': record['title']=title
        if friendly in ('A','H','AH'):
            record['faction']={'A':'Alliance','H':'Horde','AH':'Neutral'}[friendly]
        npcdata[npc]=record
        return record
    questgivers=defaultdict(list)
    for npc,q in npcs.items():
        if q[10]:
            for quest in q[10].values(): questgivers[quest].append(npc)
    for r in table(sql,'creature_questrelation'):
        if int(r['id']) not in questgivers[int(r['quest'])]:questgivers[int(r['quest'])].append(int(r['id']))
    records={}; report=[]
    for spell,recipe in sorted(catalogue.items()):
        entries=[]; item=recipe['item']; classicspell=spells.get(spell)
        if not classicspell:
            report.append({'spellID':spell,**recipe,'status':'no_exact_classic_spell'});continue
        # Never match by localized names. A teaching item must teach this exact
        # spell in Classic; itemless recipes must have an exact trainer edge.
        validitem=False
        if item and item in sqlitems:
            it=sqlitems[item]
            for i in range(1,6):
                sid=int(it['spellid_'+str(i)])
                if sid==spell and it['spelltrigger_'+str(i)]=='6': validitem=True
                teach=spells.get(sid,{})
                if any(teach.get('Effect'+str(j))=='36' and teach.get('EffectTriggerSpell'+str(j))==str(spell) for j in (1,2,3)):validitem=True
        qitem=items[item] if validitem else None
        def append_npc(npc, kind, **extra):
            info=npc_info(npc)
            if not info: return
            if kind in ('vendor','trainer') and info.get('faction') is None: return
            if kind=='trainer' and (not info.get('title') or not int(npcs[npc][15] or 0)&16):return
            entry={'kind':kind,'npcID':npc,**extra}
            if entry not in entries: entries.append(entry)
        # Forever adds teaching scrolls to some unchanged Classic trainer spells.
        # Match the spell exactly, retain the Forever item guard on the record,
        # and label the trainer as Classic rather than inventing a scroll vendor.
        if trainers[spell]:
            for npc,skill,level,requirements in sorted(set(trainers[spell])):
                append_npc(npc,'trainer',profession=recipe['profession'],requiredSkill=skill,requiredLevel=level,
                           learnedWithProfession=recipe['autoTaught'],requirements=requirements or None)
        for quest in sorted(quest_spells[spell]):
            for npc in sorted(questgivers[quest]):
                append_npc(npc,'quest',questID=quest,questName=quests[quest]['Title'])
        if qitem:
            for npc in sorted(vendors[item] | (set(qitem[14].values()) if qitem[14] else set())): append_npc(npc,'vendor')
            if qitem[6] or rewards[item]:
                for quest in sorted(rewards[item] | (set(qitem[6].values()) if qitem[6] else set())):
                    if quest not in quests: continue
                    for npc in sorted(questgivers[quest]):
                        append_npc(npc,'quest',questID=quest,questName=quests[quest]['Title'])
            drops=sorted(dropped_by(item) | (set(qitem[2].values()) if qitem[2] else set()))
            if drops:
                # Keep every named spawn for narrow drops, representative
                # examples for enormous world-drop pools. Counts are explicit.
                located=[npc for npc in drops if npc_info(npc)]
                for npc in located[:24]: append_npc(npc,'mob',area=True)
        if entries:
            record={'spellID':spell,'sources':entries,'checked':'2026-10-22','examples':True}
            if item: record['itemID']=item
            else: record['trainerOnly']=True
            if qitem and drops:record['dropNPCCount']=len(drops)
            records[spell]=record
        report.append({'spellID':spell,**recipe,'status':'covered' if entries else 'no_locatable_classic_source',
                       'sources':len(entries)})
    # Count the older hand-reviewed references as well; otherwise the gap report
    # would incorrectly call an already documented boss/drop recipe uncovered.
    lua.compile((ROOT/'ClassicSources.lua').read_text())('CraftRoster',addon)
    curated=addon.ClassicSources.records
    curated_only={}
    for row in report:
        record=curated[row['spellID']]
        if row['status']!='covered' and record and record.itemID==row['item']:
            row['status']='covered';row['sourceSet']='curated';row['sources']=len(record.sources)
            curated_only[row['spellID']]=record
    used={s['npcID'] for r in records.values() for s in r['sources']}
    out=['-- Generated factual Classic references. See docs/CLASSIC_SOURCE_BUILD.md.',
         '-- QuestieDB: see bundled licence notice; Classic-DB GPL-2.0-or-later. No Forever approval.',
         'local _,addon=...', 'addon.ClassicSourceData={npcs={']
    for npc in sorted(used):out.append('['+str(npc)+']='+lua_value(npcdata[npc])+',')
    out.append('},recipes={')
    for spell,r in records.items():out.append('['+str(spell)+']='+lua_value(r)+',')
    out.append('},gaps={')
    for row in report:
        if row['status']!='covered':out.append('['+str(row['spellID'])+']='+lua_value(row['status'])+',')
    out.append('}}\n')
    (ROOT/'ClassicSourceData.lua').write_text('\n'.join(out))
    summary={'catalogue':len(catalogue),'covered':len(records)+len(curated_only),
             'generated':len(records),'curatedOnly':len(curated_only),'npcs':len(used),
             'byStatus':dict(Counter(r['status'] for r in report)),
             'byKind':dict(Counter(s['kind'] for r in records.values() for s in r['sources'])),
             'snapshots':{name:hashlib.sha256((folder/name).read_bytes()).hexdigest() for name in INPUT_HASHES}}
    (ROOT/'data/classic-source-coverage.json').write_text(json.dumps({'summary':summary,'recipes':report},indent=2)+'\n')
    print(json.dumps(summary,indent=2))


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('snapshots',type=Path)
    build(p.parse_args().snapshots)
