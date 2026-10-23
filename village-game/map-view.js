(function () {
  'use strict';
  const M = window.VillageModel, TILE = 64;
  const colors = { grass:'#95a765', forest:'#668553', stone:'#afb0a0', water:'#57a4b3', hill:'#8d9585' };
  class VillageMap {
    constructor(host, icon, onSelect) {
      this.host=host; this.onSelect=onSelect; this.state=null; this.selected=M.CAMP+1;
      this.camera={x:(M.CAMP%M.MAP_WIDTH+.5-(host.clientWidth>600?3:0))*TILE,y:(Math.floor(M.CAMP/M.MAP_WIDTH)+.5)*TILE,zoom:.8};
      this.images={}; this.patterns={}; this.grid=false; this.drag=null; this.dirty=false;
      host.innerHTML='<canvas id="world-map" tabindex="0" role="application" aria-label="河谷地图：拖动移动，滚轮缩放，方向键选择地块"></canvas><div class="map-toolbar"><button id="map-minus" aria-label="缩小地图">−</button><span id="map-zoom">80%</span><button id="map-plus" aria-label="放大地图">＋</button><button id="map-home">回到营地</button><button id="map-fit">全图</button><button id="map-grid" aria-pressed="false">网格</button><button id="map-expand">展开地图</button></div><div class="minimap-wrap"><span>河谷全境 · 40 × 32</span><canvas id="minimap" width="160" height="128" tabindex="0" aria-label="小地图，点击移动视野"></canvas></div><span id="art-loading" class="art-loading">正在载入写实素材…</span><div class="map-caption"><span>拖动移动 · 滚轮缩放 · 方向键选地</span><span id="map-population"></span></div>';
      this.canvas=host.querySelector('#world-map');this.ctx=this.canvas.getContext('2d');
      this.mini=host.querySelector('#minimap');this.mctx=this.mini.getContext('2d');
      let loaded=0;
      const art=window.VillageArt;
      this.canvas.dataset.artReady='false';
      for(const type of ['sprites','terrain']) {
        const image=new Image();
        image.onload=()=>{
          if(type==='terrain')this.makePatterns(image);
          loaded++;
          if(loaded===2){this.canvas.dataset.artReady='true';host.querySelector('#art-loading').hidden=true;}
          this.request();
        };
        image.onerror=()=>{host.querySelector('#art-loading').textContent='素材加载失败，请重新打开完整下载的游戏';this.canvas.dataset.artReady='error';};
        this.images[type]=image;
        image.src=art[type];
      }
      this.resize=new ResizeObserver(()=>this.request());this.resize.observe(host);
      this.canvas.addEventListener('pointerdown',event=>{
        if(this.drag)return;
        event.preventDefault();
        if(event.button!==0 && event.button!==1 && event.button!==2)return;
        this.canvas.focus({preventScroll:true});
        this.drag={id:event.pointerId,x:event.clientX,y:event.clientY,cx:this.camera.x,cy:this.camera.y,moved:false};
        this.canvas.setPointerCapture(event.pointerId);
      });
      this.canvas.addEventListener('pointermove',event=>{
        if(!this.drag)return;
        const dx=event.clientX-this.drag.x,dy=event.clientY-this.drag.y;
        if(Math.hypot(dx,dy)>5)this.drag.moved=true;
        if(this.drag.moved){this.camera.x=this.drag.cx-dx/this.camera.zoom;this.camera.y=this.drag.cy-dy/this.camera.zoom;this.clamp();this.request();}
      });
      this.canvas.addEventListener('pointerup',event=>{
        if(!this.drag||event.pointerId!==this.drag.id)return;
        const moved=this.drag.moved;this.drag=null;
        if(this.canvas.hasPointerCapture(event.pointerId))this.canvas.releasePointerCapture(event.pointerId);
        if(!moved&&event.button===0){const at=this.screenToWorld(event.clientX,event.clientY);this.select(Math.floor(at.x/TILE),Math.floor(at.y/TILE));}
      });
      this.canvas.addEventListener('pointercancel',()=>{this.drag=null;});
      this.canvas.addEventListener('contextmenu',event=>event.preventDefault());
      this.canvas.addEventListener('wheel',event=>{event.preventDefault();this.zoom(this.camera.zoom*Math.exp(-event.deltaY*.0015),event.clientX,event.clientY);},{passive:false});
      this.canvas.addEventListener('keydown',event=>{
        const moves={ArrowLeft:[-1,0],ArrowRight:[1,0],ArrowUp:[0,-1],ArrowDown:[0,1]};
        if(moves[event.key]){event.preventDefault();const [dx,dy]=moves[event.key];this.select(Math.max(0,Math.min(M.MAP_WIDTH-1,this.selected%M.MAP_WIDTH+dx)),Math.max(0,Math.min(M.MAP_HEIGHT-1,Math.floor(this.selected/M.MAP_WIDTH)+dy)));this.focusTile(this.selected);}
        if(event.key==='+'||event.key==='='){event.preventDefault();this.zoom(this.camera.zoom*1.2);}
        if(event.key==='-'){event.preventDefault();this.zoom(this.camera.zoom/1.2);}
        if(event.key==='Home'){event.preventDefault();this.home();}
      });
      host.querySelector('#map-minus').onclick=()=>this.zoom(this.camera.zoom/1.25);
      host.querySelector('#map-plus').onclick=()=>this.zoom(this.camera.zoom*1.25);
      host.querySelector('#map-home').onclick=()=>this.home();
      host.querySelector('#map-fit').onclick=()=>{this.camera.x=M.MAP_WIDTH*TILE/2;this.camera.y=M.MAP_HEIGHT*TILE/2;this.zoom(Math.min(this.host.clientWidth/(M.MAP_WIDTH*TILE+50),this.host.clientHeight/(M.MAP_HEIGHT*TILE+50)));};
      host.querySelector('#map-grid').onclick=()=>{this.grid=!this.grid;host.querySelector('#map-grid').setAttribute('aria-pressed',String(this.grid));this.request();};
      host.querySelector('#map-expand').onclick=()=>this.expand();
      document.addEventListener('keydown',event=>{if(event.key==='Escape'&&this.host.closest('.map-card').classList.contains('expanded-map'))this.expand(false);});
      this.mini.addEventListener('pointerdown',event=>{const r=this.mini.getBoundingClientRect();this.camera.x=(event.clientX-r.left)/r.width*M.MAP_WIDTH*TILE;this.camera.y=(event.clientY-r.top)/r.height*M.MAP_HEIGHT*TILE;this.clamp();this.request();});
      this.mini.addEventListener('keydown',event=>{if(event.key==='Enter'||event.key===' '){event.preventDefault();this.home();}});
    }
    expand(force) {
      const expanded=this.host.closest('.map-card').classList.toggle('expanded-map',force);
      document.body.classList.toggle('map-expanded',expanded);
      this.host.querySelector('#map-expand').textContent=expanded?'收起地图 [Esc]':'展开地图';this.request();
    }
    select(x,y){if(x<0||y<0||x>=M.MAP_WIDTH||y>=M.MAP_HEIGHT)return;this.selected=y*M.MAP_WIDTH+x;this.onSelect(this.selected);this.request();}
    screenToWorld(x,y){const r=this.host.getBoundingClientRect();return{x:this.camera.x+(x-r.left-r.width/2)/this.camera.zoom,y:this.camera.y+(y-r.top-r.height/2)/this.camera.zoom};}
    clamp(){this.camera.x=Math.max(0,Math.min(M.MAP_WIDTH*TILE,this.camera.x));this.camera.y=Math.max(0,Math.min(M.MAP_HEIGHT*TILE,this.camera.y));}
    zoom(value,x,y){
      const rect=this.host.getBoundingClientRect();x=x===undefined?rect.left+rect.width/2:x;y=y===undefined?rect.top+rect.height/2:y;
      const before=this.screenToWorld(x,y);this.camera.zoom=Math.max(.1,Math.min(2,value));const after=this.screenToWorld(x,y);
      this.camera.x+=before.x-after.x;this.camera.y+=before.y-after.y;this.clamp();this.request();
    }
    home(){this.camera.x=(M.CAMP%M.MAP_WIDTH+.5-(this.host.clientWidth>600?3:0))*TILE;this.camera.y=(Math.floor(M.CAMP/M.MAP_WIDTH)+.5)*TILE;this.camera.zoom=.8;this.request();}
    focusTile(tile){this.camera.x=(tile%M.MAP_WIDTH+.5)*TILE;this.camera.y=(Math.floor(tile/M.MAP_WIDTH)+.5)*TILE;this.request();}
    update(state,selected){this.state=state;this.selected=selected;this.request();}
    request(){if(this.dirty)return;this.dirty=true;requestAnimationFrame(()=>{this.dirty=false;this.draw();});}
    makePatterns(image){
      const names=['grass','earth','water','rock'];
      names.forEach((name,index)=>{
        const texture=document.createElement('canvas');texture.width=256;texture.height=256;
        texture.getContext('2d').drawImage(image,(index%2)*image.width/2,Math.floor(index/2)*image.height/2,image.width/2,image.height/2,0,0,256,256);
        if(name==='grass'){const tc=texture.getContext('2d');tc.fillStyle='#a3ad72';tc.globalAlpha=.4;tc.fillRect(0,0,256,256);}
        this.patterns[name]=this.ctx.createPattern(texture,'repeat');
      });
    }
    sprite(c,type,cx,base,size,alpha=1){
      const image=this.images.sprites,frame=window.VillageArt.frames[type];
      if(!image||!image.complete||!image.naturalWidth||!frame)return;
      c.globalAlpha=alpha;
      // Exclude a neighboring fence at the atlas cell edge from the tree silhouette.
      const inset=type==='tree'?image.width/3*.035:0;
      c.drawImage(image,frame[0]*image.width/3+inset,frame[1]*image.height/2,image.width/3-inset,image.height/2,cx-size/2,base-size*.94,size,size);
      c.globalAlpha=1;
    }
    terrainAt(x,y){return x<0||y<0||x>=M.MAP_WIDTH||y>=M.MAP_HEIGHT?'void':this.state.terrain[y*M.MAP_WIDTH+x];}
    draw(){
      if(!this.state)return;
      const w=this.host.clientWidth,h=this.host.clientHeight;if(!w||!h)return;
      const dpr=Math.min(2,window.devicePixelRatio||1),c=this.ctx;
      if(this.canvas.width!==Math.round(w*dpr)||this.canvas.height!==Math.round(h*dpr)){this.canvas.width=Math.round(w*dpr);this.canvas.height=Math.round(h*dpr);}
      c.setTransform(dpr,0,0,dpr,0,0);c.fillStyle='#b2b78f';c.fillRect(0,0,w,h);
      c.imageSmoothingEnabled=true;c.imageSmoothingQuality='high';
      c.translate(w/2,h/2);c.scale(this.camera.zoom,this.camera.zoom);c.translate(-this.camera.x,-this.camera.y);
      // Extra border accounts for tall sprites protruding beyond their ground cell.
      const x0=Math.max(0,Math.floor((this.camera.x-w/2/this.camera.zoom)/TILE)-2),x1=Math.min(M.MAP_WIDTH-1,Math.ceil((this.camera.x+w/2/this.camera.zoom)/TILE)+2);
      const y0=Math.max(0,Math.floor((this.camera.y-h/2/this.camera.zoom)/TILE)-2),y1=Math.min(M.MAP_HEIGHT-1,Math.ceil((this.camera.y+h/2/this.camera.zoom)/TILE)+2);
      for(let y=y0;y<=y1;y++)for(let x=x0;x<=x1;x++){
        const i=y*M.MAP_WIDTH+x,t=this.state.terrain[i],px=x*TILE,py=y*TILE;
        c.fillStyle=this.patterns.grass||colors.grass;c.fillRect(px,py,TILE+.5,TILE+.5);
        if(t!=='water'){
          if(t==='hill')c.fillStyle=this.patterns.rock||colors.hill;
          else c.fillStyle=this.patterns.grass||colors[t];
          c.fillRect(px,py,TILE+.5,TILE+.5);
          c.fillStyle=t==='forest'?'#e7e7bf0c':'#f7edcf28';c.fillRect(px,py,TILE+.5,TILE+.5);
        }
        if(this.state.tiles[i]||this.state.project&&this.state.project.tile===i){
          c.fillStyle=this.patterns.earth||'#b69b72';
          c.beginPath();c.ellipse(px+TILE*.5,py+TILE*.55,TILE*.56,TILE*.43,0,0,Math.PI*2);c.fill();
        }
      }
      // Shorelines follow the water topology; shared edges do not receive outline seams.
      for(let y=y0;y<=y1;y++)for(let x=x0;x<=x1;x++){
        if(this.terrainAt(x,y)!=='water')continue;
        const px=x*TILE,py=y*TILE;
        const left=this.terrainAt(x-1,y)!=='water',right=this.terrainAt(x+1,y)!=='water',top=this.terrainAt(x,y-1)!=='water',bottom=this.terrainAt(x,y+1)!=='water';
        c.fillStyle=this.patterns.water||colors.water;c.beginPath();c.roundRect(px,py,TILE+.5,TILE+.5,[top&&left?14:0,top&&right?14:0,bottom&&right?14:0,bottom&&left?14:0]);c.fill();
        c.strokeStyle='#d3c59b';c.lineWidth=3;c.lineCap='round';c.beginPath();
        if(left){c.moveTo(px,py+12);c.lineTo(px,py+TILE-12);}if(right){c.moveTo(px+TILE,py+12);c.lineTo(px+TILE,py+TILE-12);}
        if(top){c.moveTo(px+12,py);c.lineTo(px+TILE-12,py);}if(bottom){c.moveTo(px+12,py+TILE);c.lineTo(px+TILE-12,py+TILE);}c.stroke();
      }
      if(this.grid&&this.camera.zoom>.35){
        c.strokeStyle='#fff7df60';c.lineWidth=1/this.camera.zoom;
        for(let y=y0;y<=y1;y++)for(let x=x0;x<=x1;x++)c.strokeRect(x*TILE,y*TILE,TILE,TILE);
      }
      for(let y=y0;y<=y1;y++)for(let x=x0;x<=x1;x++){
        const i=y*M.MAP_WIDTH+x,t=this.state.terrain[i],px=x*TILE,py=y*TILE;
        const variation=((x*37+y*71)%17)/17;
        if(t==='forest')this.sprite(c,'tree',px+TILE*.5+(variation-.5)*8,py+TILE*.8,TILE*(1.55+variation*.3));
        if(t==='stone')this.sprite(c,'rock',px+TILE*.5,py+TILE*.82,TILE*1.1);
        if(t==='hill'&&(x+y)%2===0)this.sprite(c,'rock',px+TILE*.48,py+TILE*.85,TILE*1.65);
        const project=this.state.project&&this.state.project.tile===i;
        const type=project?this.state.project.type:this.state.tiles[i];
        if(type){
          if(type==='clear'){
            c.strokeStyle='#d4a967';c.lineWidth=2;c.setLineDash([7,4]);c.strokeRect(px+3,py+3,TILE-6,TILE-6);c.setLineDash([]);
          }else this.sprite(c,type,px+TILE*.5,py+TILE*.86,TILE*(type==='farm'?1.25:1.45),project ? 0.48 : 1);
          if(project){c.fillStyle='#e6dbc5';c.fillRect(px+5,py+TILE-5,TILE-10,5);c.fillStyle='#b18747';c.fillRect(px+5,py+TILE-5,(TILE-10)*this.state.project.progress/M.projectSpec(this.state).work,5);}
          if(this.camera.zoom>.65){
            const label=project?'施工中':type==='camp'?'营地':M.BUILDINGS[type].name;
            c.font='11px "Microsoft YaHei",sans-serif';c.textAlign='center';
            const width=c.measureText(label).width+12;c.fillStyle='#fff9e5da';c.fillRect(px+TILE*.5-width/2,py+TILE-1,width,17);c.fillStyle='#4a4535';c.fillText(label,px+TILE*.5,py+TILE+11);
          }
        }
      }
      const sx=this.selected%M.MAP_WIDTH*TILE,sy=Math.floor(this.selected/M.MAP_WIDTH)*TILE;
      c.strokeStyle='#fff6cd';c.lineWidth=4/this.camera.zoom;c.strokeRect(sx+2,sy+2,TILE-4,TILE-4);
      c.strokeStyle='#927043';c.lineWidth=1.5/this.camera.zoom;c.strokeRect(sx+2,sy+2,TILE-4,TILE-4);
      this.host.querySelector('#map-zoom').textContent=Math.round(this.camera.zoom*100)+'%';
      this.host.querySelector('#map-population').textContent=this.state.population+' 位居民 · '+M.count(this.state,'house')+' 座木屋';
      this.drawMini(w,h);
    }
    drawMini(w,h){
      const c=this.mctx,sx=this.mini.width/M.MAP_WIDTH,sy=this.mini.height/M.MAP_HEIGHT;
      for(let i=0;i<this.state.tiles.length;i++){c.fillStyle=this.state.tiles[i]?'#775a3a':colors[this.state.terrain[i]];c.fillRect(i%M.MAP_WIDTH*sx,Math.floor(i/M.MAP_WIDTH)*sy,sx+.2,sy+.2);}
      c.strokeStyle='#fff9dc';c.lineWidth=1.5;
      c.strokeRect((this.camera.x-w/2/this.camera.zoom)/TILE*sx,(this.camera.y-h/2/this.camera.zoom)/TILE*sy,w/this.camera.zoom/TILE*sx,h/this.camera.zoom/TILE*sy);
      c.fillStyle='#c47d32';c.fillRect(M.CAMP%M.MAP_WIDTH*sx-1,Math.floor(M.CAMP/M.MAP_WIDTH)*sy-1,5,5);
    }
  }
  window.VillageMap=VillageMap;
})();
