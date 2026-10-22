'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const M = require('../model.js');
const HOME=M.CAMP+1;
function place(s,type){const i=M.availableTile({...s,resources:{food:330,wood:330,stone:330}},type);assert.notEqual(i,-1);s.tiles[i]=type;return i;}

test('workers cannot exceed population or go below zero', () => {
  const s = M.fresh();
  assert.equal(M.assign(s, 'food', 1), false);
  assert.equal(M.assign(s, 'wood', -1), true);
  assert.equal(M.assign(s, 'wood', -1), false);
  assert.equal(M.assign(s, 'food', 1), true);
  assert.equal(M.idle(s), 0);
  assert.equal(M.assign(s, 'food', 2), false);
});
test('daily food production, consumption and materials are exact', () => {
  const s = M.fresh(); M.advance(s);
  assert.deepEqual(s.resources, {food:19,wood:12,stone:7});
  assert.equal(s.day, 1); assert.equal(s.population,5);
});
test('construction deducts once, requires workers, completes before arrivals', () => {
  const s = M.fresh();
  assert.equal(M.startBuild(s,'house',HOME).ok,true);
  assert.deepEqual(s.resources,{food:18,wood:2,stone:3});
  assert.equal(M.startBuild(s,'house',HOME+1).ok,false);
  M.assign(s,'build',-1); M.advance(s);
  assert.equal(s.project.progress,0);
  M.assign(s,'build',1); M.advance(s); M.advance(s);
  assert.equal(s.tiles[HOME],'house'); assert.equal(s.project,null);
  assert.equal(s.population,6); assert.equal(M.idle(s),1);
});
test('cancel refunds once and cannot duplicate resources', () => {
  const s=M.fresh(); M.startBuild(s,'house',HOME);
  assert.equal(M.cancelBuild(s),true); assert.equal(M.cancelBuild(s),false);
  assert.deepEqual(s.resources,{food:18,wood:10,stone:6});
});
test('farm production starts on the following day', () => {
  const s=M.fresh(); s.resources.wood=20;s.resources.stone=10;
  s.jobs={food:2,wood:0,stone:0,build:3};
  M.startBuild(s,'farm',M.availableTile(s,'farm')); M.advance(s);
  assert.equal(s.resources.food,19); assert.equal(M.rates(s).food,8);
  M.advance(s);assert.equal(s.resources.food,22);
});
test('storage overflow is capped; warehouse increases every resource capacity', () => {
  const s=M.fresh();s.resources={food:30,wood:30,stone:30};
  M.advance(s);assert.deepEqual(s.resources,{food:30,wood:30,stone:30});
  place(s,'warehouse'); M.advance(s);
  assert.equal(M.storage(s),80); assert.equal(s.resources.wood,32);
});
test('arrivals require spare housing and adequate food', () => {
  const noHouse=M.fresh();for(let i=0;i<3;i++)M.advance(noHouse);assert.equal(noHouse.population,5);
  const noFood=M.fresh();place(noFood,'house');noFood.resources.food=0;noFood.jobs.food=0;
  for(let i=0;i<3;i++)M.advance(noFood);assert.ok(noFood.population<6);
});
test('starvation removes one resident after two consecutive hungry days and fixes jobs', () => {
  const s=M.fresh();s.resources.food=0;s.jobs={food:0,wood:0,stone:0,build:5};
  M.advance(s);assert.equal(s.population,5);assert.equal(s.hunger,1);
  M.advance(s);assert.equal(s.population,4);assert.equal(s.jobs.build,4);assert.equal(M.idle(s),0);
  for(let i=0;i<8;i++)M.advance(s);
  assert.equal(s.population,0);assert.equal(s.phase,'lost');
  const day=s.day;M.advance(s);assert.equal(s.day,day);
});
function playStrategy() {
  const s=M.fresh();
  for(let day=0;day<20 && s.phase==='playing';day++) {
    const food=Math.ceil((s.population+1)/(3+M.count(s,'farm')));
    s.jobs={food,stone:1,build:1,wood:Math.max(0,s.population-food-2)};
    if(!s.project) {
      let type=M.capacity(s)<Math.min(10,s.population+2)?'house':!M.count(s,'farm')?'farm':!M.count(s,'warehouse')?'warehouse':M.capacity(s)<10?'house':null;
      if(type)M.startBuild(s,type,M.availableTile(s,type));
    }
    M.advance(s);
    M.validate(s);
  }
  return s;
}
test('a valid resource-and-worker strategy wins within 20 days', () => {
  const s=playStrategy();
  console.log('Strategy outcome:',s.phase,'day',s.day,'population',s.population,'resources',s.resources);
  assert.equal(s.phase,'won');assert.ok(s.day<=20);assert.equal(M.goals(s).every(g=>g.done),true);
});
test('doing nothing has a real day-20 loss, and day 20 can also be won', () => {
  const s=M.fresh();for(let i=0;i<20;i++)M.advance(s);assert.equal(s.day,20);assert.equal(s.phase,'lost');
  const win=M.fresh();win.day=19;win.population=10;win.peakPopulation=10;win.jobs={food:3,wood:3,stone:2,build:2};place(win,'house');place(win,'house');place(win,'farm');place(win,'warehouse');win.resources.food=30;
  M.advance(win);assert.equal(win.day,20);assert.equal(win.phase,'won');
});
test('random valid actions always preserve model invariants', () => {
  let seed=19374;
  const random=n=>{seed=(seed*1664525+1013904223)>>>0;return seed%n;};
  for(let run=0;run<100;run++) {
    const s=M.fresh();
    for(let action=0;action<100 && s.phase==='playing';action++) {
      switch(random(4)) {
        case 0:M.assign(s,M.JOBS[random(4)],random(2)?1:-1);break;
        case 1:M.startBuild(s,Object.keys(M.BUILDINGS)[random(3)],random(M.MAP_WIDTH*M.MAP_HEIGHT));break;
        case 2:M.cancelBuild(s);break;
        default:M.advance(s);
      }
      assert.deepEqual(M.validate(s),s);
    }
  }
});
test('saves roundtrip, reject malformed state, and do not mutate input', () => {
  const s=playStrategy();assert.deepEqual(M.validate(JSON.parse(JSON.stringify(s))),s);
  for(const change of [x=>x.population=-1,x=>x.resources.food=999,x=>x.jobs.food=500,x=>x.tiles[M.CAMP]=null,x=>x.log[0].tone='html',x=>x.project={type:'house',tile:M.CAMP,progress:0},x=>x.tiles[HOME]='unknown',x=>x.tiles[HOME]='__proto__',x=>x.tiles[HOME]=['house']]) {
    const broken=M.fresh();change(broken);assert.throws(()=>M.validate(broken));
  }
});

test('large terrain is deterministic, contains all biomes, and reserves a safe camp',()=>{
 const s=M.fresh();assert.equal(s.tiles.length,1280);assert.deepEqual(s.terrain,M.terrainMap());
 for(const t of Object.keys(M.TERRAIN_NAMES))assert.ok(s.terrain.includes(t));
 assert.equal(s.terrain[M.CAMP],'grass');assert.equal(s.tiles[M.CAMP],'camp');
 assert.ok(M.availableTile(s,'farm')>=0);
});
test('water, mountains, forest and distant land reject building without taking resources',()=>{
 const s=M.fresh(),before={...s.resources};
 for(const t of ['water','hill','forest','stone']){
  const tile=s.terrain.indexOf(t);assert.equal(M.startBuild(s,'house',tile).ok,false);assert.deepEqual(s.resources,before);
 }
 assert.equal(M.startBuild(s,'house',0).ok,false);
 assert.equal(M.startBuild(s,'farm',HOME).ok,false);
});
test('clearing requires workers and produces materials once; cancel creates no resources',()=>{
 const s=M.fresh(),tile=17*M.MAP_WIDTH+25;
 assert.equal(M.startClear(s,tile).ok,true);
 const initial=s.resources.wood;s.jobs={food:2,wood:0,stone:1,build:2};
 M.advance(s);assert.equal(s.terrain[tile],'grass');assert.equal(s.resources.wood,initial+4);
 assert.equal(M.startClear(s,tile).ok,false);M.validate(s);
 const rock=20*M.MAP_WIDTH+17;assert.equal(M.startClear(s,rock).ok,true);
 const stone=s.resources.stone;M.cancelBuild(s);assert.equal(s.resources.stone,stone);assert.equal(s.terrain[rock],'stone');
});
test('terrain restrictions survive save validation',()=>{
 const s=M.fresh();s.tiles[s.terrain.indexOf('water')]='house';assert.throws(()=>M.validate(s));
 const t=M.fresh();t.tiles[HOME]='farm';assert.throws(()=>M.validate(t));
 const old=M.fresh();old.version=1;assert.throws(()=>M.validate(old));
});
