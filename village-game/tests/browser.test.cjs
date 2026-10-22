'use strict';
const { chromium } = require('playwright');
const assert = require('node:assert/strict');
const path = require('node:path');
const { pathToFileURL } = require('node:url');
const M = require('../model.js');
const url = process.env.GAME_TEST_URL || 'http://127.0.0.1:8765/index.html';
(async () => {
  const browser = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH || '/usr/bin/chromium', headless: true, args: ['--no-sandbox', '--disable-dev-shm-usage'] });
  const context = await browser.newContext({ viewport: { width: 1440, height: 1180 }, acceptDownloads: true });
  const page = await context.newPage();
  const errors = [], external = [];
  page.on('pageerror', error => errors.push(error.message));
  page.on('request', request => { if (/^https?:/.test(request.url()) && new URL(request.url()).hostname !== '127.0.0.1') external.push(request.url()); });
  const read = () => page.evaluate(() => JSON.parse(localStorage.getItem('riverdale-village-v1')).state);
  await page.goto(url);
  await context.setOffline(true);
  await page.getByRole('button', { name: '开拓这片土地', exact: true }).click();
  await page.getByRole('button', { name: '暂停时间', exact: true }).click();
  assert.equal((await read()).population, 5);
  assert.equal(await page.locator('.lot').count(), 24);
  assert.equal(await page.locator('[data-job="food"][data-delta="1"]').isDisabled(), true);
  await page.locator('[data-job="wood"][data-delta="-1"]').click();
  await page.locator('[data-job="food"][data-delta="1"]').click();
  assert.equal((await read()).jobs.food, 3);
  await page.locator('[data-job="food"][data-delta="-1"]').click();
  await page.locator('[data-job="wood"][data-delta="1"]').click();
  await page.locator('[data-lot="9"]').click();
  await page.locator('[data-build="house"]').click();
  assert.equal((await read()).resources.wood, 2);
  await page.getByRole('button', { name: '推进一天', exact: false }).click();
  assert.equal((await read()).project.progress, 1);
  await page.screenshot({ path: '/tmp/riverdale-desktop.png', fullPage: true });
  await context.setOffline(false);
  await page.reload();
  assert.equal(await page.getByRole('button', { name: '继续这段生活', exact: true }).count(), 1);
  await page.getByRole('button', { name: '继续这段生活', exact: true }).click();
  await page.getByRole('button', { name: '暂停时间', exact: true }).click();
  assert.equal((await read()).day, 1);
  assert.equal((await read()).project.progress, 1);
  // Use only UI buttons to implement the same feasible strategy as the model test.
  for(let day=0; day<20; day++) {
    let s=await read();
    if(s.phase!=='playing') break;
    const food=Math.ceil((s.population+1)/(3+M.count(s,'farm')));
    const desired={food,stone:1,build:1,wood:Math.max(0,s.population-food-2)};
    for(const job of M.JOBS) {
      for(let n=s.jobs[job];n>desired[job];n--) await page.locator(`[data-job="${job}"][data-delta="-1"]`).click();
    }
    s=await read();
    for(const job of M.JOBS) {
      for(let n=s.jobs[job];n<desired[job];n++) await page.locator(`[data-job="${job}"][data-delta="1"]`).click();
    }
    s=await read();
    if(!s.project) {
      const type=M.capacity(s)<Math.min(10,s.population+2)?'house':!M.count(s,'farm')?'farm':!M.count(s,'warehouse')?'warehouse':M.capacity(s)<10?'house':null;
      if(type) {
        await page.locator(`[data-lot="${s.tiles.indexOf(null)}"]`).click();
        const button=page.locator(`[data-build="${type}"]`);
        if(await button.isEnabled()) await button.click();
      }
    }
    await page.getByRole('button', { name: '推进一天', exact: false }).click();
  }
  const won=await read();
  assert.equal(won.phase,'won');assert.equal(won.population,10);
  assert.equal(await page.locator('#modal-title').textContent(),'这片河谷，成了家。');
  await page.screenshot({ path:'/tmp/riverdale-victory.png',fullPage:true });
  await page.getByRole('button',{name:'继续自由经营',exact:true}).click();
  assert.equal((await read()).endless,true);
  const downloadPromise=page.waitForEvent('download');
  await page.getByRole('button',{name:'导出存档',exact:true}).click();
  const download=await downloadPromise;
  assert.ok(download.suggestedFilename().endsWith('.json'));
  await page.locator('#save-file').setInputFiles({name:'village.json',mimeType:'application/json',buffer:Buffer.from(JSON.stringify({state:won,speed:2}))});
  await page.getByRole('button',{name:'确认载入',exact:true}).click();
  assert.equal((await read()).phase,'won');
  assert.deepEqual(errors,[]);assert.deepEqual(external,[]);
  const mobile=await context.newPage();
  mobile.on('pageerror',error=>errors.push(error.message));
  await mobile.setViewportSize({width:390,height:844});
  await mobile.goto(url);
  await mobile.getByRole('button',{name:'继续自由经营',exact:true}).click();
  await mobile.screenshot({path:'/tmp/riverdale-mobile.png',fullPage:true});
  assert.equal(await mobile.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),true,'mobile layout must not overflow');
  const lossContext=await browser.newContext();
  const loss=await lossContext.newPage();
  loss.on('pageerror',error=>errors.push(error.message));
  await loss.goto(url);
  await loss.getByRole('button',{name:'开拓这片土地',exact:true}).click();
  await loss.getByRole('button',{name:'暂停时间',exact:true}).click();
  for(let day=0;day<20;day++) await loss.getByRole('button',{name:'推进一天',exact:false}).click();
  assert.equal(await loss.locator('#modal-title').textContent(),'故事，还可以重新开始。');
  await loss.getByRole('button',{name:'查看村落',exact:true}).click();
  assert.equal(await loss.locator('#next-day').isDisabled(),true);
  assert.deepEqual(errors,[]);
  const timedContext=await browser.newContext();
  const timed=await timedContext.newPage();
  timed.on('pageerror',error=>errors.push(error.message));
  await timed.clock.install();
  await timed.goto(url);
  await timed.getByRole('button',{name:'开拓这片土地',exact:true}).click();
  await timed.clock.runFor(12050);
  let timedState=await timed.evaluate(()=>JSON.parse(localStorage.getItem('riverdale-village-v1')).state);
  assert.equal(timedState.day,1,'automatic daily production advances after twelve seconds');
  await timed.getByRole('button',{name:'暂停时间',exact:true}).click();
  await timed.clock.runFor(24000);
  timedState=await timed.evaluate(()=>JSON.parse(localStorage.getItem('riverdale-village-v1')).state);
  assert.equal(timedState.day,1,'paused time does not produce resources');
  await timed.locator('[data-speed="4"]').click();
  await timed.getByRole('button',{name:'开始时间',exact:true}).click();
  await timed.clock.runFor(3050);
  timedState=await timed.evaluate(()=>JSON.parse(localStorage.getItem('riverdale-village-v1')).state);
  assert.equal(timedState.day,2,'4x speed advances a day in three seconds');
  assert.deepEqual(errors,[]);
  console.log('BROWSER PASS: local browser launch, offline gameplay, worker buttons, construction, save/reload, UI-only victory on day '+won.day+', continue, export/import, mobile layout, deadline loss, automatic clock/pause/4x speed; no script errors or network requests.');
  await browser.close();
})().catch(error=>{console.error(error);process.exit(1);});
