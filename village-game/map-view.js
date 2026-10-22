(function () {
  'use strict';
  const M = window.VillageModel, TILE = 48;
  const colors = { grass:'#c4d4a6', fertile:'#d4d9a1', forest:'#91af80', stone:'#b7bea9', water:'#7aaeb8', hill:'#9ba797' };
  class VillageMap {
    constructor(host, icon, onSelect) {
      this.host=host; this.onSelect=onSelect; this.state=null; this.selected=M.CAMP+1;
      this.camera={x:(M.CAMP%M.MAP_WIDTH+.5)*TILE,y:(Math.floor(M.CAMP/M.MAP_WIDTH)+.5)*TILE,zoom:.95};
      this.images={}; this.drag=null; this.dirty=false;
      host.innerHTML='<canvas id="world-map" tabindex="0" role="application" aria-label="河谷地图：拖动移动，滚轮缩放，方向键选择地块"></canvas><div class="map-toolbar"><button id="map-minus" aria-label="缩小地图">−</button><span id="map-zoom">95%</span><button id="map-plus" aria-label="放大地图">＋</button><button id="map-home">回到营地</button><button id="map-fit">全图</button><button id="map-expand">展开地图</button></div><div class="minimap-wrap"><span>河谷全境 · 40 × 32</span><canvas id="minimap" width="160" height="128" tabindex="0" aria-label="小地图，点击移动视野"></canvas></div><div class="map-caption"><span>拖动移动 · 滚轮缩放 · 方向键选地</span><span id="map-population"></span></div>';
      this.canvas=host.querySelector('#world-map');this.ctx=this.canvas.getContext('2d');
      this.mini=host.querySelector('#minimap');this.mctx=this.mini.getContext('2d');
      for(const type of ['camp','house','farm','warehouse']) {
        const image=new Image();image.onload=()=>this.request();
        image.src='data:image/svg+xml;charset=utf-8,'+encodeURIComponent(icon(type).replace('<svg ', '<svg xmlns="http://www.w3.org/2000/svg" '));this.images[type]=image;
      }
      this.resize=new ResizeObserver(()=>this.request());this.resize.observe(host);
      this.canvas.addEventListener('pointerdown',event=>{
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
    home(){this.focusTile(M.CAMP);this.camera.zoom=.95;this.request();}
    focusTile(tile){this.camera.x=(tile%M.MAP_WIDTH+.5)*TILE;this.camera.y=(Math.floor(tile/M.MAP_WIDTH)+.5)*TILE;this.request();}
    update(state,selected){this.state=state;this.selected=selected;this.request();}
    request(){if(this.dirty)return;this.dirty=true;requestAnimationFrame(()=>{this.dirty=false;this.draw();});}
    tree(c,x,y,size,color){c.fillStyle='#776c4a';c.fillRect(x-size*.07,y,size*.14,size*.35);c.fillStyle=color;c.beginPath();c.moveTo(x,y-size*.85);c.lineTo(x-size*.48,y+size*.06);c.lineTo(x+size*.48,y+size*.06);c.closePath();c.fill();c.fillStyle='#60845c';c.beginPath();c.moveTo(x,y-size*.85);c.lineTo(x,y+size*.06);c.lineTo(x+size*.48,y+size*.06);c.closePath();c.fill();}
    draw(){
      if(!this.state)return;
      const w=this.host.clientWidth,h=this.host.clientHeight;if(!w||!h)return;
      const dpr=Math.min(2,window.devicePixelRatio||1),c=this.ctx;
      if(this.canvas.width!==Math.round(w*dpr)||this.canvas.height!==Math.round(h*dpr)){this.canvas.width=Math.round(w*dpr);this.canvas.height=Math.round(h*dpr);}
      c.setTransform(dpr,0,0,dpr,0,0);c.fillStyle='#b0bda3';c.fillRect(0,0,w,h);
      c.translate(w/2,h/2);c.scale(this.camera.zoom,this.camera.zoom);c.translate(-this.camera.x,-this.camera.y);
      const x0=Math.max(0,Math.floor((this.camera.x-w/2/this.camera.zoom)/TILE)-1),x1=Math.min(M.MAP_WIDTH-1,Math.ceil((this.camera.x+w/2/this.camera.zoom)/TILE)+1);
      const y0=Math.max(0,Math.floor((this.camera.y-h/2/this.camera.zoom)/TILE)-1),y1=Math.min(M.MAP_HEIGHT-1,Math.ceil((this.camera.y+h/2/this.camera.zoom)/TILE)+1);
      for(let y=y0;y<=y1;y++)for(let x=x0;x<=x1;x++){
        const i=y*M.MAP_WIDTH+x,t=this.state.terrain[i],px=x*TILE,py=y*TILE;
        c.fillStyle=colors[t];c.fillRect(px,py,TILE+.4,TILE+.4);
        if(t==='water'){
          c.strokeStyle='#b6d8d6';c.lineWidth=1.4;c.beginPath();c.moveTo(px+8,py+17+(x%2)*9);c.quadraticCurveTo(px+20,py+14,px+35,py+18);c.stroke();
        }else if(t==='fertile'){
          c.strokeStyle='#b6bb82';c.lineWidth=1;c.beginPath();for(let n=0;n<3;n++){c.moveTo(px+8,py+12+n*12);c.lineTo(px+40,py+12+n*12);}c.stroke();
        }else if(t==='hill'){
          c.fillStyle='#82917f';c.beginPath();c.moveTo(px+3,py+43);c.lineTo(px+23,py+5);c.lineTo(px+46,py+43);c.fill();c.fillStyle='#bac3b0';c.beginPath();c.moveTo(px+23,py+5);c.lineTo(px+34,py+25);c.lineTo(px+23,py+21);c.lineTo(px+15,py+24);c.fill();
        }else if(t==='stone'){
          for(let n=0;n<3;n++){const rx=px+12+(n%2)*21,ry=py+14+n*9;c.fillStyle=n%2?'#929d92':'#a3ada0';c.beginPath();c.ellipse(rx,ry,8+n,5+n,-.3,0,Math.PI*2);c.fill();}
        }else if(t==='grass'){
          c.strokeStyle='#acbf91';c.lineWidth=1;c.beginPath();c.moveTo(px+12,py+27);c.lineTo(px+15,py+22);c.lineTo(px+17,py+27);c.moveTo(px+33,py+13);c.lineTo(px+35,py+9);c.stroke();
        }
        if(this.camera.zoom>.5){c.strokeStyle='#7d947a19';c.lineWidth=.5;c.strokeRect(px,py,TILE,TILE);}
      }
      // Buildings and tree silhouettes are drawn after ground so they can overlap cell edges.
      for(let y=y0;y<=y1;y++)for(let x=x0;x<=x1;x++){
        const i=y*M.MAP_WIDTH+x,t=this.state.terrain[i],px=x*TILE,py=y*TILE;
        if(t==='forest'){this.tree(c,px+15,py+27,24,'#527b57');this.tree(c,px+34,py+35,28,'#426b4e');}
        const project=this.state.project&&this.state.project.tile===i;
        const type=project?this.state.project.type:this.state.tiles[i];
        if(type){
          c.fillStyle='#e0cca1';c.fillRect(px+3,py+4,42,40);
          if(type==='clear'){c.strokeStyle='#ba8441';c.lineWidth=3;c.strokeRect(px+5,py+5,38,38);c.beginPath();c.moveTo(px+5,py+5);c.lineTo(px+43,py+43);c.stroke();}
          else if(this.images[type]&&this.images[type].complete&&this.images[type].naturalWidth>0){c.globalAlpha=project ? 0.65 : 1;c.drawImage(this.images[type],px-5,py-12,58,58);c.globalAlpha=1;}
          if(project){c.fillStyle='#ead8b6';c.fillRect(px+3,py+42,42,4);c.fillStyle='#b58a4d';c.fillRect(px+3,py+42,42*this.state.project.progress/M.projectSpec(this.state).work,4);}
          if(this.camera.zoom>.6){c.font='10px "Microsoft YaHei",sans-serif';c.textAlign='center';c.fillStyle='#304a37';c.fillText(project?'施工中':type==='camp'?'营地':M.BUILDINGS[type].name,px+24,py+54);}
        }
      }
      const sx=this.selected%M.MAP_WIDTH*TILE,sy=Math.floor(this.selected/M.MAP_WIDTH)*TILE;
      c.fillStyle='#fff8c535';c.fillRect(sx,sy,TILE,TILE);c.strokeStyle='#af7334';c.lineWidth=2.5/this.camera.zoom;c.strokeRect(sx+1,sy+1,TILE-2,TILE-2);
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
