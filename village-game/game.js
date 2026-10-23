(function () {
  'use strict';
  const M = window.VillageModel;
  const $ = id => document.getElementById(id);
  const KEY = 'riverdale-village-v2';
  const DAY_MS = 12000;
  let state = M.fresh();
  let selected = M.CAMP+1;
  let mapView;
  let paused = true;
  let speed = 1;
  let elapsed = 0;
  let modalOpen = false;
  let modalKind = '';
  let toastTimeout;
  let saved = false;
  let saveAvailable = true;
  let loadError = false;
  const art = {
    house: '<path d="M19 46h56v37H19z" fill="#d0b17b"/><path d="M10 48L47 15l38 33-8 7-30-25-29 25z" fill="#8c6248"/><path d="M38 57h17v26H38z" fill="#66503d"/><path d="M23 57h10v11H23zm37 0h10v11H60z" fill="#e7d9a1"/><path d="M66 29V15h9v22" fill="#a78b69"/><path d="M17 84h62" stroke="#93a57e" stroke-width="5" stroke-linecap="round"/>',
    camp: '<path d="M8 78L48 17l40 61z" fill="#b89965"/><path d="M48 17v61H8z" fill="#e7d4a1"/><path d="M36 78l12-33 13 33" fill="#66593e"/><path d="M48 8v12" stroke="#695e43" stroke-width="3"/><path d="M7 81h83" stroke="#8f9f70" stroke-width="5" stroke-linecap="round"/>',
    farm: '<path d="M8 40l47-16 33 20-45 24z" fill="#aa8559"/><path d="M8 40v17l35 23V68zm35 28v12l45-23V44" fill="#927147"/><g stroke="#e0bd7d" stroke-width="3"><path d="M21 42l34-11m-22 20l34-14m-22 21l31-15"/></g><g stroke="#5f854b" stroke-width="3"><path d="M28 39v-13m21 11V21m16 20V27m-14 28V42m-16 7V35"/></g><g fill="#8da45f"><ellipse cx="25" cy="27" rx="7" ry="3" transform="rotate(30 25 27)"/><ellipse cx="53" cy="23" rx="7" ry="3" transform="rotate(-30 53 23)"/><ellipse cx="69" cy="28" rx="7" ry="3"/><ellipse cx="47" cy="43" rx="7" ry="3"/></g>',
    warehouse: '<path d="M12 43h70v39H12z" fill="#b69869"/><path d="M5 45L29 18h38l23 27z" fill="#69816a"/><path d="M29 58h36v24H29z" fill="#826342"/><path d="M47 58v24m-18-24l36 24m0-24L29 82" stroke="#c3a578" stroke-width="3"/><path d="M16 49h12v9H16zm50 0h12v9H66z" fill="#d6ddbf"/><path d="M8 83h79" stroke="#96a782" stroke-width="5" stroke-linecap="round"/>',
    food: '<path d="M15 26c-9-12-9-18-7-21 12 5 15 13 7 21zm0 0C17 12 23 8 29 9c-1 12-5 17-14 17z" fill="currentColor"/><path d="M15 17v16" stroke="currentColor" stroke-width="2"/><path d="M10 32h14" stroke="currentColor" stroke-width="2"/>',
    wood: '<path d="M5 13l17-7 9 10-18 10z" fill="currentColor" opacity=".7"/><ellipse cx="10" cy="22" rx="6" ry="9" transform="rotate(-35 10 22)" fill="none" stroke="currentColor" stroke-width="2"/><path d="M9 19l3 6m7-12l7-2" stroke="currentColor" stroke-width="2"/>',
    stone: '<path d="M3 27L8 11l15-5 10 12-3 13H13z" fill="currentColor" opacity=".75"/><path d="M8 11l9 11 16-4m-16 4l-4 9" fill="none" stroke="#fffef9" stroke-width="1.5"/>',
    people: '<circle cx="13" cy="11" r="5" fill="currentColor"/><path d="M4 31v-7c0-8 18-8 18 0v7" fill="currentColor"/><circle cx="27" cy="13" r="4" fill="currentColor" opacity=".5"/><path d="M25 20c8-1 9 5 9 11h-8" fill="currentColor" opacity=".5"/>'
  };
  function icon(name, resource = false) {
    if(!resource&&window.VillageArt.frames[name])return `<span class="building-art art-${name}" aria-hidden="true"></span>`;
    return `<svg viewBox="0 0 ${resource ? '36 36' : '96 96'}" aria-hidden="true">${art[name] || art.house}</svg>`;
  }
  function toast(text) {
    $('toast').textContent = text;
    $('toast').hidden = false;
    clearTimeout(toastTimeout);
    toastTimeout = setTimeout(() => { $('toast').hidden = true; }, 3500);
  }
  function save() {
    try {
      localStorage.setItem(KEY, JSON.stringify({ state, selected, speed }));
      saveAvailable = true;
      $('save-state').textContent = '已自动保存 · 离线不推进时间';
    } catch (_) {
      saveAvailable = false;
      $('save-state').textContent = '浏览器无法自动保存，请使用导出存档';
    }
  }
  try {
    const raw = localStorage.getItem(KEY);
    if (raw) {
      const data = JSON.parse(raw);
      state = M.validate(data.state);
      selected = Number.isInteger(data.selected) && data.selected >= 0 && data.selected < M.MAP_WIDTH*M.MAP_HEIGHT ? data.selected : M.CAMP+1;
      speed = [1, 2, 4].includes(data.speed) ? data.speed : 1;
      saved = true;
    }
  } catch (_) { loadError = true; }
  function showModal(kind, title, body, actions) {
    paused = true;
    modalOpen = true;
    modalKind = kind;
    $('modal-eyebrow').textContent = kind === 'result' ? '这一段河谷故事' : '一局小小的村落经营';
    $('modal-title').textContent = title;
    $('modal-art').innerHTML = icon(kind === 'result' && state.phase === 'won' ? 'house' : 'camp');
    $('modal-body').innerHTML = body;
    $('modal-actions').replaceChildren();
    for (const action of actions) {
      const button = document.createElement('button');
      button.textContent = action.label;
      button.className = action.primary ? 'primary' : 'quiet';
      button.addEventListener('click', action.run);
      $('modal-actions').appendChild(button);
    }
    $('modal').hidden = false;
    $('modal').querySelector('.modal-sheet').focus();
    renderClock();
  }
  function hideModal() {
    modalOpen = false;
    modalKind = '';
    $('modal').hidden = true;
    $('pause').focus();
    renderClock();
  }
  function begin() { hideModal(); paused = false; save(); render(); }
  function restart() {
    state = M.fresh(); selected = M.CAMP+1; elapsed = 0; speed = 1; paused = true;
    hideModal(); save(); render(); welcome(false);
  }
  function welcome(isSaved) {
    showModal('welcome', isSaved ? '河谷，还在等你。' : '五个人，一片空地。',
      `<p>${isSaved ? '已找回这台设备上的村落。回来后时间保持暂停，准备好再继续。' : '这里没有复杂的操作，也没有需要追赶的敌人。先照顾好五位居民，再让更多人把这里当成家。'}</p><ul><li>采食、伐木、采石、建造，四种工作由你分配。</li><li>拖动和缩放地图选址。农圃可建在普通草地，树林与石矿需先清理。</li><li>20 天内：10 位居民、有足够床位、农圃、仓库，且食物能够自给。</li></ul><p>一开始就能暂停慢慢想，也能点击“推进一天”结算。进度自动保存在浏览器；离线不会推进时间。</p>`,
      [{ label: isSaved ? '继续这段生活' : '开拓这片土地', primary: true, run: begin }]);
  }
  function result() {
    const won = state.phase === 'won';
    const completed = M.goals(state).filter(goal => goal.done).length;
    showModal('result', won ? '这片河谷，成了家。' : '故事，还可以重新开始。',
      `<p>${won ? '住所、食物和分工终于连成了循环。你不再只是消耗补给，而是在经营一个能够延续的村落。' : state.population <= 0 ? '居民因缺粮陆续离开。下一次，先保证每日食物不低于消耗，再考虑扩建。' : '20 天的挑战结束了。没有完成的目标，会告诉你下一次该怎样安排。'}</p><div class="result-summary"><div><strong>${state.day}</strong><small>度过的天数</small></div><div><strong>${state.population}</strong><small>村落居民</small></div><div><strong>${completed}/5</strong><small>完成的目标</small></div></div>`,
      [...(won ? [{ label: '继续自由经营', primary: true, run: () => { state.endless = true; state.phase = 'playing'; hideModal(); paused = true; save(); render(); } }] : [{ label: '查看村落', primary: true, run: hideModal }]),
        { label: '重新开始', run: restart }]);
  }
  function advice() {
    if (state.phase !== 'playing') return '这一局已结束。可以查看村落，或重新开始尝试另一种安排。';
    if (M.rates(state).netFood < 0) return '食物每天都在减少。先从其他岗位调一位居民去采食，或建设农圃提高效率。';
    if (state.project && state.jobs.build === 0) return '工地正在等待建造者。减少其他岗位人数，再为建造分配至少 1 人。';
    if (M.idle(state) > 0) return `有 ${M.idle(state)} 位居民尚未分配工作。点击岗位旁的 ＋，让每双手都有事情做。`;
    if (M.capacity(state) <= state.population) return '先建一座木屋。没有空床位，路过的旅人就不会加入村落。';
    if (!M.count(state, 'farm')) return '接下来可以建农圃：同样的采食人数，可以养活更多居民。';
    if (!M.count(state, 'warehouse')) return '建一座仓库，把资源上限从 30 提高到 80，也完成一个发展目标。';
    if (M.capacity(state) < 10) return '再建一座木屋，为 10 位居民提前准备好床位。';
    return '保持食物自给，留足两天储粮，等待每三天一次的旅人到访。';
  }
  function renderResources() {
    const rates = M.rates(state), limit = M.storage(state);
    const cards = [
      ['food', '食物', state.resources.food, limit, `产出 ${rates.food} − 消耗 ${state.population} · 每日 ${rates.netFood >= 0 ? '+' : ''}${rates.netFood}`, rates.netFood < 0],
      ['wood', '木材', state.resources.wood, limit, `每日 +${rates.wood} · 用于建造`, false],
      ['stone', '石料', state.resources.stone, limit, `每日 +${rates.stone} · 用于建造`, false],
      ['people', '居民', state.population, M.capacity(state), `空床 ${M.capacity(state) - state.population} · 待分配 ${M.idle(state)} 人`, false]
    ];
    $('resources').innerHTML = cards.map(([key, name, value, max, rate, bad]) => `<div class="resource" data-resource="${key}"><div class="resource-symbol">${icon(key, true)}</div><div><div class="name">${name}</div><div class="amount">${value}<small>/ ${max}${key === 'people' ? ' 床位' : ''}</small></div><div class="rate ${bad ? 'negative' : ''}">${rate}</div></div></div>`).join('');
  }
  function renderMap() {
    if(!mapView) mapView=new window.VillageMap($('map'),icon,index=>{selected=index;save();renderMap();renderBuildings();});
    mapView.update(state,selected);
    const terrain=M.TERRAIN_NAMES[state.terrain[selected]];
    const name=state.tiles[selected]==='camp'?'开拓营地':state.tiles[selected]?M.BUILDINGS[state.tiles[selected]].name:terrain;
    const x=selected%M.MAP_WIDTH+1,y=Math.floor(selected/M.MAP_WIDTH)+1;
    $('selection-label').textContent=`(${x}, ${y}) ${name} · ${M.inReach(state,selected)?'村落范围内':'远离村落，需逐步扩建'}`;
    const reason=M.clearReason(state,selected);
    $('clear-land').disabled=!!reason;
    $('clear-land').title=reason||'分配建造者清理，完成后获得资源';
    $('clear-land').textContent=['forest','stone'].includes(state.terrain[selected])?'清理'+terrain:'清理地块';
  }
  function renderBuildings() {
    $('building-options').replaceChildren();
    for (const [type, spec] of Object.entries(M.BUILDINGS)) {
      const reason = M.buildReason(state, type, selected);
      const button = document.createElement('button');
      button.className = 'building'; button.dataset.build = type; button.disabled = !!reason;
      button.title = reason || `在选中空地修建${spec.name}`;
      button.innerHTML = `<div class="building-top">${icon(type)}<h4>${spec.name}</h4></div><p>${spec.description}</p><div class="cost">木 ${spec.cost.wood} · 石 ${spec.cost.stone}</div><div class="build-status">${reason || `开工 · 需要 ${spec.work} 工作量`}</div>`;
      button.addEventListener('click', () => {
        const outcome = M.startBuild(state, type, selected);
        if (!outcome.ok) return toast(outcome.reason);
        save(); render(); toast(`开始修建${spec.name}${state.jobs.build ? '' : '，请分配建造者'}`);
      });
      $('building-options').appendChild(button);
    }
    if (state.project) {
      const p = state.project, spec = M.projectSpec(state);
      $('project').innerHTML = `<div class="project-text"><strong>${spec.name}施工中</strong> · ${p.progress} / ${spec.work} 工作量<br><span class="soft">${state.jobs.build > 0 ? `每天推进 ${state.jobs.build}，预计还需 ${Math.ceil((spec.work - p.progress) / state.jobs.build)} 天` : '分配建造者后才能推进'}</span></div><div class="mini-track"><span style="width:${p.progress / spec.work * 100}%"></span></div><button id="cancel-project">取消并返还</button>`;
      $('cancel-project').addEventListener('click', () => { M.cancelBuild(state); save(); render(); toast('工地已取消，建材按仓储容量返还'); });
    } else $('project').innerHTML = '<span class="soft">没有施工中的建筑。建材在开工时扣除，建造者每天推进 1 工作量 / 人。</span>';
  }
  function renderJobs() {
    const descriptions = { food: ['采食者', '每人每天 ' + (3 + M.count(state, 'farm')) + ' 食物', '♧'], wood: ['伐木者', '每人每天 2 木材', '↟'], stone: ['采石者', '每人每天 1 石料', '◇'], build: ['建造者', '每人每天 1 工作量', '⌂'] };
    $('jobs').replaceChildren();
    for (const job of M.JOBS) {
      const [name, detail, symbol] = descriptions[job];
      const row = document.createElement('div'); row.className = 'job';
      row.innerHTML = `<div class="job-description"><span class="job-symbol" aria-hidden="true">${symbol}</span><div><div class="job-name">${name}</div><small>${detail}</small></div></div><div class="job-controls"><button data-job="${job}" data-delta="-1" aria-label="减少${name}" ${state.jobs[job] <= 0 || state.phase !== 'playing' ? 'disabled' : ''}>−</button><strong>${state.jobs[job]}</strong><button data-job="${job}" data-delta="1" aria-label="增加${name}" ${M.idle(state) <= 0 || state.phase !== 'playing' ? 'disabled' : ''}>+</button></div>`;
      row.querySelectorAll('button').forEach(button => button.addEventListener('click', () => {
        if (M.assign(state, job, Number(button.dataset.delta))) { save(); render(); }
      }));
      $('jobs').appendChild(row);
    }
    $('idle').textContent = `待分配 ${M.idle(state)} 人`;
    $('idle').classList.toggle('has-idle', M.idle(state) > 0);
    $('advice').textContent = advice();
    $('advice').classList.toggle('danger', M.rates(state).netFood < 0 || !!(state.project && state.jobs.build === 0));
  }
  function renderGoals() {
    const goals = M.goals(state);
    $('goal-count').textContent = `${goals.filter(goal => goal.done).length}/5`;
    $('goals').innerHTML = goals.map(goal => `<div class="goal ${goal.done ? 'done' : ''}" data-goal="${goal.key}"><span class="goal-check">✓</span><div><strong>${goal.title}</strong><small>${goal.detail}</small></div></div>`).join('');
  }
  function renderJournal() {
    $('journal').replaceChildren();
    for (const item of state.log) {
      const li = document.createElement('li'); li.className = item.tone;
      const day = document.createElement('span'); day.className = 'log-day'; day.textContent = item.day ? `第 ${item.day} 天` : '抵达';
      const text = document.createElement('span'); text.textContent = item.text;
      li.append(day, text); $('journal').appendChild(li);
    }
  }
  function renderClock() {
    const ended = state.phase !== 'playing';
    $('clock-state').textContent = ended ? (state.phase === 'won' ? '目标已达成' : '本局已结束') : paused || modalOpen ? '时间已暂停' : '村落正在生活';
    $('pause').textContent = paused || modalOpen ? '开始时间' : '暂停时间';
    $('pause').disabled = ended || modalOpen;
    $('next-day').disabled = ended || modalOpen;
    $('clock-fraction').textContent = `${DAY_MS / 1000 / speed}s / 天`;
    $('day-progress').style.transform = `scaleX(${elapsed / DAY_MS})`;
    document.querySelectorAll('[data-speed]').forEach(button => { button.classList.toggle('active', Number(button.dataset.speed) === speed); button.disabled = ended || modalOpen; });
  }
  function render() {
    $('day-label').textContent = `第 ${state.phase === 'playing' ? state.day + 1 : state.day} 天`;
    $('day-subtitle').textContent = state.endless ? '自由经营 · 没有期限' : '20 天河谷挑战';
    $('challenge-progress').style.width = `${Math.min(100, state.day / M.DAYS * 100)}%`;
    renderResources(); renderMap(); renderBuildings(); renderJobs(); renderGoals(); renderJournal(); renderClock();
  }
  function advance() {
    if (modalOpen || !M.advance(state)) return;
    elapsed = 0;
    save(); render();
    if (state.phase !== 'playing') result();
    else toast(`第 ${state.day} 天已结算${M.idle(state) > 0 ? ' · 有居民等待分配工作' : ''}`);
  }
  $('clear-land').addEventListener('click',()=>{const outcome=M.startClear(state,selected);if(outcome.ok){save();render();toast('已安排清理，建造者会推进工程');}else toast(outcome.reason);});
  $('pause').addEventListener('click', () => { paused = !paused; renderClock(); });
  $('next-day').addEventListener('click', advance);
  document.querySelectorAll('[data-speed]').forEach(button => button.addEventListener('click', () => { speed = Number(button.dataset.speed); save(); renderClock(); }));
  $('help').addEventListener('click', () => showModal('help', '先照顾人，再扩建村落。', '<p>食物每天先产出再消耗，每人吃 1 份。每名采食者产出 3 份，每座农圃额外增加 1 份 / 人。农圃可建在普通草地，河流和山地不能直接建造。</p><ul><li>用 − 腾出待分配居民，再用 ＋ 安排新岗位。</li><li>拖动地图、滚轮缩放，小地图快速定位；回到营地或全图按钮帮助找路。点击地块，再选建筑。建造者推进工地与清理。</li><li>木屋增加 3 个床位；仓库为每种资源增加 50 容量。</li><li>旅人每 3 天来一次，需要空床位、两天储粮且当天不缺粮。</li><li>连续两天缺粮，有一位居民离开。没人留下或 20 天未达标，本局失败。</li></ul><p>每日新建成的农圃从次日生效。新居民当日领取 2 份食物，从次日开始正常消耗。胜利需要 10 人、住处、农圃、仓库、两天储粮和不亏损的食物生产。</p>', [{ label: '明白了，返回村落', primary: true, run: hideModal }]));
  $('new-game').addEventListener('click', () => showModal('restart', '重新开拓这片河谷？', '<p>这会替换当前浏览器存档。想保留这座村落，可以先返回并点击“导出存档”。</p>', [{ label: '返回村落', run: hideModal }, { label: '确认重新开始', primary: true, run: restart }]));
  $('export-save').addEventListener('click', () => {
    const blob = new Blob([JSON.stringify({ state, selected, speed }, null, 2)], { type: 'application/json' });
    const url = URL.createObjectURL(blob), link = document.createElement('a'); link.href = url; link.download = `河谷初生-第${state.day}天.json`;
    document.body.appendChild(link); link.click(); link.remove(); setTimeout(() => URL.revokeObjectURL(url), 2000); toast('已导出存档，离开浏览器也能保留');
  });
  $('import-save').addEventListener('click', () => { paused = true; renderClock(); $('save-file').click(); });
  $('save-file').addEventListener('change', async event => {
    const file = event.target.files[0]; if (!file) return;
    try {
      if (file.size > 200000) throw new Error('存档文件过大');
      const payload = JSON.parse(await file.text());
      const imported = M.validate(payload.state);
      showModal('import', '载入这座村落？', `<p>存档包含第 ${imported.day} 天的村落，现有 ${imported.population} 位居民。载入会覆盖当前自动存档；取消则保留当前游戏。</p>`, [{ label: '取消', run: hideModal }, { label: '确认载入', primary: true, run: () => { state = imported; selected = M.CAMP+1; speed = [1, 2, 4].includes(payload.speed) ? payload.speed : 1; elapsed = 0; hideModal(); paused = true; save(); render(); if (state.phase !== 'playing') result(); toast('存档已载入，时间保持暂停'); } }]);
    } catch (error) { toast('无法载入：' + error.message); }
    event.target.value = '';
  });
  document.addEventListener('keydown', event => {
    if (event.code === 'Space' && !event.repeat && !modalOpen && state.phase === 'playing' && !['INPUT', 'TEXTAREA', 'BUTTON'].includes(document.activeElement.tagName)) { event.preventDefault(); paused = !paused; renderClock(); }
    if (event.key === 'Escape' && modalOpen && !['welcome', 'result'].includes(modalKind)) hideModal();
    if (event.key === 'Tab' && modalOpen) {
      const focusables = [...$('modal').querySelectorAll('button:not(:disabled)')];
      const first = focusables[0], last = focusables[focusables.length - 1];
      if (event.shiftKey && (document.activeElement === first || document.activeElement.classList.contains('modal-sheet'))) { event.preventDefault(); last.focus(); }
      else if (!event.shiftKey && document.activeElement === last) { event.preventDefault(); first.focus(); }
    }
  });
  document.addEventListener('visibilitychange', () => { if (document.hidden) { paused = true; save(); renderClock(); } });
  window.addEventListener('pagehide', save);
  let previous = performance.now();
  function frame(now) {
    const dt = Math.min(250, now - previous); previous = now;
    if (!paused && !modalOpen && state.phase === 'playing' && !document.hidden) {
      elapsed += dt * speed;
      if (elapsed >= DAY_MS) advance();
      else $('day-progress').style.transform = `scaleX(${elapsed / DAY_MS})`;
    }
    requestAnimationFrame(frame);
  }
  const artStyle=document.createElement('style');
  // A direct image rule avoids browser limits on multi-megabyte CSS custom properties.
  artStyle.textContent=`.building-art{background-image:url("${window.VillageArt.sprites}")}`;
  document.head.appendChild(artStyle);
  render();
  if (saved && state.phase !== 'playing') result(); else welcome(saved);
  if (loadError) toast('旧存档无法读取，已准备新村落；你也可以导入导出的存档');
  if (!saveAvailable) $('save-state').textContent = '请使用导出存档';
  requestAnimationFrame(frame);
})();
