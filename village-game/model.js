(function (root) {
  'use strict';
  const VERSION = 2;
  const MAP_WIDTH = 40, MAP_HEIGHT = 32, CAMP = 16 * MAP_WIDTH + 20;
  const TERRAIN_NAMES = { grass: '草地', forest: '树林', stone: '石矿', water: '河流', hill: '山地' };
  const terrainKnown = type => typeof type === 'string' && Object.prototype.hasOwnProperty.call(TERRAIN_NAMES, type);
  function terrainMap() {
    const cells = [];
    const noise = (x, y) => { const n = Math.sin(x * 127.1 + y * 311.7 + 482) * 43758.5453; return n - Math.floor(n); };
    for (let y = 0; y < MAP_HEIGHT; y++) for (let x = 0; x < MAP_WIDTH; x++) {
      const river = 8 + Math.sin(y * .19) * 3 + Math.sin(y * .47) * .8;
      const distance = Math.abs(x - river);
      const grove = Math.sin(x * .42 + y * .17) + Math.cos(y * .39 - x * .12);
      let type = distance < 1.25 ? 'water' : (Math.hypot(x - 35, y - 4) < 4.8 || Math.hypot(x - 3, y - 27) < 3.4) ? 'hill' : grove > .58 ? 'forest' : noise(x, y) > .94 ? 'stone' : 'grass';
      if (Math.hypot(x - 20, y - 16) < 4) type = 'grass';
      cells.push(type);
    }
    cells[17 * MAP_WIDTH + 25] = 'forest';
    cells[20 * MAP_WIDTH + 17] = 'stone';
    return cells;
  }
  function distance(a, b) { return Math.hypot(a % MAP_WIDTH - b % MAP_WIDTH, Math.floor(a / MAP_WIDTH) - Math.floor(b / MAP_WIDTH)); }
  function inReach(state, tile) { return state.tiles.some((type, index) => type && distance(tile, index) <= 6); }
  function availableTile(state, type) { return state.tiles.findIndex((value, index) => !value && !buildReason(state, type, index)); }
  function projectSpec(state, project = state.project) {
    if (!project) return null;
    if (project.type !== 'clear') return BUILDINGS[project.type];
    const forest = state.terrain[project.tile] === 'forest';
    return { name: forest ? '清理树林' : '清理石矿', work: forest ? 2 : 3, cost: {}, description: forest ? '腾出草地，获得 4 木材' : '腾出草地，获得 3 石料' };
  }
  const DAYS = 20;
  const JOBS = ['food', 'wood', 'stone', 'build'];
  const BUILDINGS = {
    house: { name: '木屋', cost: { wood: 8, stone: 3 }, work: 2, limit: 20, description: '增加 3 个居住位置', icon: 'house' },
    farm: { name: '农圃', cost: { wood: 10, stone: 4 }, work: 3, limit: 8, description: '每名采食者每天额外产出 1 食物', icon: 'farm' },
    warehouse: { name: '仓库', cost: { wood: 12, stone: 6 }, work: 3, limit: 6, description: '所有资源的储量上限增加 50', icon: 'warehouse' }
  };
  const known = type => typeof type === 'string' && Object.prototype.hasOwnProperty.call(BUILDINGS, type);
  const clone = value => JSON.parse(JSON.stringify(value));
  function fresh() {
    const tiles = Array(MAP_WIDTH * MAP_HEIGHT).fill(null);
    tiles[CAMP] = 'camp';
    return { version: VERSION, day: 0, population: 5, peakPopulation: 5,
      resources: { food: 18, wood: 10, stone: 6 }, jobs: { food: 2, wood: 1, stone: 1, build: 1 },
      tiles, terrain: terrainMap(), project: null, hunger: 0, phase: 'playing', endless: false,
      log: [{ day: 0, text: '五位开拓者带着补给来到河谷。先建一座木屋，为后来的人留个位置。', tone: 'info' }] };
  }
  function count(state, type) { return state.tiles.filter(tile => tile === type).length; }
  function capacity(state) { return 5 + count(state, 'house') * 3; }
  function storage(state) { return 30 + count(state, 'warehouse') * 50; }
  function employed(state) { return JOBS.reduce((sum, job) => sum + state.jobs[job], 0); }
  function idle(state) { return state.population - employed(state); }
  function rates(state) {
    const food = state.jobs.food * (3 + count(state, 'farm'));
    return { food, netFood: food - state.population, wood: state.jobs.wood * 2, stone: state.jobs.stone, build: state.jobs.build };
  }
  function goals(state) {
    return [
      { key: 'people', title: '聚集 10 位居民', detail: `${state.population} / 10 人`, done: state.population >= 10 },
      { key: 'homes', title: '让每个人都有住处', detail: `${state.population} 人 / ${capacity(state)} 个床位`, done: capacity(state) >= state.population },
      { key: 'farm', title: '建成一座农圃', detail: `${count(state, 'farm')} / 1 座`, done: count(state, 'farm') >= 1 },
      { key: 'warehouse', title: '建成一座仓库', detail: `${count(state, 'warehouse')} / 1 座`, done: count(state, 'warehouse') >= 1 },
      { key: 'food', title: '备足两天食物，并实现自给', detail: `${state.resources.food} / ${state.population * 2} 储粮 · 每日 ${rates(state).netFood >= 0 ? '+' : ''}${rates(state).netFood}`, done: state.resources.food >= state.population * 2 && rates(state).netFood >= 0 }
    ];
  }
  function log(state, text, tone = 'info') {
    state.log.unshift({ day: state.day, text, tone });
    state.log = state.log.slice(0, 50);
  }
  function assign(state, job, delta) {
    if (state.phase !== 'playing' || !JOBS.includes(job) || ![-1, 1].includes(delta)) return false;
    if (delta > 0 && idle(state) <= 0) return false;
    if (delta < 0 && state.jobs[job] <= 0) return false;
    state.jobs[job] += delta;
    return true;
  }
  function buildReason(state, type, tile) {
    if (state.phase !== 'playing') return '本局已经结束';
    if (!known(type)) return '未知建筑';
    if (!Number.isInteger(tile) || tile < 0 || tile >= state.tiles.length || state.tiles[tile]) return '请先选择一块空地';
    if (state.project) return '请先完成当前工地';
    if (!inReach(state, tile)) return '距离村落太远，请沿建筑逐步扩建';
    if (state.terrain[tile] === 'water') return '河流不能直接建造';
    if (state.terrain[tile] === 'hill') return '山地不能直接建造';
    if (['forest', 'stone'].includes(state.terrain[tile])) return '先清理地块，再建造';
    const spec = BUILDINGS[type];
    if (count(state, type) >= spec.limit) return '已达到该建筑的数量上限';
    if (Object.entries(spec.cost).some(([key, amount]) => state.resources[key] < amount)) return '木材或石料不足';
    return '';
  }
  function startBuild(state, type, tile) {
    const reason = buildReason(state, type, tile);
    if (reason) return { ok: false, reason };
    const spec = BUILDINGS[type];
    for (const [key, amount] of Object.entries(spec.cost)) state.resources[key] -= amount;
    state.project = { type, tile, progress: 0 };
    log(state, `开始修建${spec.name}。分配建造者才能推进工地。`);
    return { ok: true };
  }
  function cancelBuild(state) {
    if (!state.project || state.phase !== 'playing') return false;
    const spec = projectSpec(state);
    const limit = storage(state);
    for (const [key, amount] of Object.entries(spec.cost)) state.resources[key] = Math.min(limit, state.resources[key] + amount);
    log(state, state.project.type === 'clear' ? '取消清理，不消耗也不产出资源。' : `取消${spec.name}，返还建材（受仓储上限限制）。`);
    state.project = null;
    return true;
  }
  function advance(state) {
    if (state.phase !== 'playing') return false;
    state.day += 1;
    // All daily production uses the buildings and workers present at the start of the day.
    const production = rates(state);
    const foodAvailable = state.resources.food + production.food;
    const shortage = Math.max(0, state.population - foodAvailable);
    state.resources.food = Math.max(0, foodAvailable - state.population);
    state.resources.wood += production.wood;
    state.resources.stone += production.stone;
    if (shortage > 0) {
      state.hunger += 1;
      log(state, `食物短缺 ${shortage} 份。连续两天挨饿会有居民离开。`, 'bad');
      if (state.hunger >= 2) {
        state.population -= 1;
        state.hunger = 0;
        for (const job of ['build', 'stone', 'wood', 'food']) {
          while (employed(state) > state.population && state.jobs[job] > 0) state.jobs[job] -= 1;
        }
        log(state, '一位居民因缺粮离开。请优先恢复食物生产。', 'bad');
      }
    } else state.hunger = 0;
    if (state.project) {
      state.project.progress += production.build;
      const spec = projectSpec(state);
      if (state.project.progress >= spec.work) {
        if (state.project.type === 'clear') {
          const forest = state.terrain[state.project.tile] === 'forest';
          state.resources[forest ? 'wood' : 'stone'] += forest ? 4 : 3;
          state.terrain[state.project.tile] = 'grass';
          log(state, `${spec.name}完成，${spec.description}。`, 'good');
        } else {
          state.tiles[state.project.tile] = state.project.type;
          log(state, `${spec.name}建成了！${spec.description}。`, 'good');
        }
        state.project = null;
      }
    }
    const limit = storage(state);
    const overflow = Object.values(state.resources).some(value => value > limit);
    for (const key of ['food', 'wood', 'stone']) state.resources[key] = Math.min(limit, state.resources[key]);
    if (overflow) log(state, '仓储已满，超出的资源无法保留。建仓库可以提高上限。', 'warn');
    if (state.day % 3 === 0 && state.population > 0) {
      if (capacity(state) > state.population && state.resources.food >= state.population * 2 && shortage === 0) {
        state.population += 1;
        state.resources.food = Math.max(0, state.resources.food - 2);
        state.peakPopulation = Math.max(state.peakPopulation, state.population);
        log(state, '一位旅人加入村落，领取了 2 份食物。记得为新居民分配工作。', 'good');
      } else log(state, '旅人路过了河谷：需要空床位、两天储粮且当日不缺粮，才愿意定居。', 'warn');
    }
    if (state.population <= 0) {
      state.phase = 'lost';
      log(state, '最后一位居民也离开了，河谷重归寂静。', 'bad');
    } else if (!state.endless && goals(state).every(goal => goal.done)) {
      state.phase = 'won';
      log(state, '村落已能自给自足。这片河谷，有了自己的名字。', 'good');
    } else if (!state.endless && state.day >= DAYS) {
      state.phase = 'lost';
      log(state, '20 天到了，村落尚未达成全部目标。试着调整分工，再开一局。', 'bad');
    }
    return true;
  }
  function clearReason(state, tile) {
    if (state.phase !== 'playing') return '本局已经结束';
    if (!Number.isInteger(tile) || tile < 0 || tile >= state.tiles.length || state.tiles[tile]) return '请选择未建造的地块';
    if (state.project) return '请先完成当前工地';
    if (!inReach(state, tile)) return '距离村落太远';
    if (!['forest','stone'].includes(state.terrain[tile])) return '只有树林和石矿需要清理';
    return '';
  }
  function startClear(state, tile) {
    const reason = clearReason(state, tile);
    if (reason) return { ok: false, reason };
    state.project = { type: 'clear', tile, progress: 0 };
    log(state, `开始${projectSpec(state).name}，需要建造者施工。`);
    return { ok: true };
  }
  function validate(input) {
    if (!input || input.version !== VERSION) throw new Error('存档版本不兼容');
    const value = clone(input);
    // 0.2 saves keep their buildings and projects; retired terrain becomes ordinary grass.
    if (Array.isArray(value.terrain)) value.terrain = value.terrain.map(type => type === 'fertile' ? 'grass' : type);
    const integer = (n, min, max) => Number.isInteger(n) && n >= min && n <= max;
    if (!integer(value.day, 0, 100000) || !integer(value.population, 0, 65) || !integer(value.peakPopulation, value.population, 65)) throw new Error('人口或日期数据无效');
    if (!['playing', 'won', 'lost'].includes(value.phase) || typeof value.endless !== 'boolean') throw new Error('游戏状态无效');
    if (!Array.isArray(value.tiles) || value.tiles.length !== MAP_WIDTH * MAP_HEIGHT || value.tiles[CAMP] !== 'camp' || value.tiles.filter(x => x === 'camp').length !== 1) throw new Error('地图数据无效');
    if (!Array.isArray(value.terrain) || value.terrain.length !== MAP_WIDTH * MAP_HEIGHT || value.terrain.some(type => !terrainKnown(type))) throw new Error('地形数据无效');
    if (value.tiles.some(type => type !== null && type !== 'camp' && !known(type))) throw new Error('建筑数据无效');
    if (value.tiles.some((type, index) => type && value.terrain[index] !== 'grass')) throw new Error('建筑地形不合法');
    for (const type of Object.keys(BUILDINGS)) if (count(value, type) > BUILDINGS[type].limit) throw new Error('建筑数量无效');
    if (!value.jobs || JOBS.some(job => !integer(value.jobs[job], 0, value.population)) || employed(value) > value.population) throw new Error('工作分配无效');
    if (!value.resources || ['food', 'wood', 'stone'].some(key => !integer(value.resources[key], 0, storage(value)))) throw new Error('资源数据无效');
    if (!integer(value.hunger, 0, 1)) throw new Error('饥饿状态无效');
    if (value.project !== null) {
      const p = value.project;
      if (!p || !(known(p.type) || p.type === 'clear') || !integer(p.tile, 0, MAP_WIDTH * MAP_HEIGHT - 1) || value.tiles[p.tile] !== null || !inReach(value, p.tile) || !integer(p.progress, 0, projectSpec(value, p).work - 1) || (p.type === 'clear' ? !['forest','stone'].includes(value.terrain[p.tile]) : count(value, p.type) >= BUILDINGS[p.type].limit || value.terrain[p.tile] !== 'grass')) throw new Error('工地数据无效');
    }
    if (!Array.isArray(value.log) || value.log.length > 50 || value.log.some(item => !item || !integer(item.day, 0, value.day) || typeof item.text !== 'string' || item.text.length > 300 || !['info', 'good', 'warn', 'bad'].includes(item.tone))) throw new Error('日志数据无效');
    if ((value.phase === 'playing' || value.phase === 'won') && value.population === 0) throw new Error('人口与游戏状态矛盾');
    if (value.phase === 'won' && !goals(value).every(goal => goal.done)) throw new Error('胜利条件不完整');
    if (value.phase === 'playing' && !value.endless && value.day >= DAYS) throw new Error('挑战已到期');
    // Only retain fields understood by the game; imported files cannot add runtime settings.
    const clean = fresh();
    for (const key of Object.keys(clean)) clean[key] = clone(value[key]);
    return clean;
  }
  const api = { VERSION, MAP_WIDTH, MAP_HEIGHT, CAMP, TERRAIN_NAMES, terrainMap, inReach, availableTile, projectSpec, clearReason, startClear, DAYS, JOBS, BUILDINGS, fresh, count, capacity, storage, idle, rates, goals, assign, buildReason, startBuild, cancelBuild, advance, validate, clone };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  else root.VillageModel = api;
})(typeof window !== 'undefined' ? window : globalThis);
