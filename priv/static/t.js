(function(){
  if(window.__wwt)return;
  var s=document.currentScript||document.querySelector("script[data-w],script[data-site]");
  if(!s)return;
  var id=s.getAttribute("data-w")||s.getAttribute("data-site");if(!id)return;
  var ep=s.src.split("?")[0],timer,last,ticks=0;
  function routeHash(){
    var h=location.hash||"";
    return (h.indexOf("#/")===0||h.indexOf("#!/")===0)?h:"";
  }
  function here(){return location.pathname+location.search+routeHash()}
  function send(n,x){
    var b={s:id,n:n,p:location.pathname+routeHash(),q:location.search,h:location.hostname,r:document.referrer,l:navigator.language,w:innerWidth};
    if(x)for(var k in x)b[k]=x[k];
    var body=JSON.stringify(b);
    try{
      if(navigator.sendBeacon&&navigator.sendBeacon(ep,new Blob([body],{type:"text/plain"})))return;
    }catch(e){}
    try{fetch(ep,{method:"POST",body:body,headers:{"content-type":"text/plain"},keepalive:true,mode:"no-cors"})}catch(e){}
  }
  function view(){
    var now=here();
    if(now===last)return;
    last=now;
    send("v");
  }
  function later(){clearTimeout(timer);timer=setTimeout(view,40)}
  last=here();
  send("v");
  var ps=history.pushState,rs=history.replaceState;
  history.pushState=function(){var r=ps.apply(this,arguments);later();return r};
  history.replaceState=function(){var r=rs.apply(this,arguments);later();return r};
  addEventListener("popstate",later);
  addEventListener("hashchange",later);
  addEventListener("turbo:load",later);
  addEventListener("turbolinks:load",later);
  addEventListener("pageshow",function(e){if(e.persisted){last="";view()}});
  if(window.navigation&&navigation.addEventListener)navigation.addEventListener("navigate",later);
  var gone=0;
  function leave(){if(gone)return;gone=1;send("x")}
  document.addEventListener("visibilitychange",function(){
    if(document.visibilityState==="hidden")leave();
    else gone=0;
  });
  addEventListener("pagehide",leave);
  setInterval(function(){
    if(document.visibilityState!=="visible")return;
    view();
    if(++ticks%15===0)send("h");
  },1000);
  document.addEventListener("click",function(ev){
    var path=ev.composedPath&&ev.composedPath(),el,i;
    if(path){
      for(i=0;i<path.length;i++){
        el=path[i];
        if(el&&el.matches&&el.matches("a,button,[data-wwt],[role=button]"))break;
        el=null;
      }
    }
    if(!el&&ev.target&&ev.target.closest)el=ev.target.closest("a,button,[data-wwt],[role=button]");
    if(!el)return;
    var t=(el.getAttribute("data-wwt")||(el.innerText||"").replace(/\s+/g," ").trim()||el.getAttribute("href")||"").slice(0,40);
    if(t)send("k",{e:t});
  },true);
  window.wwt=function(name){send("c",{e:String(name||"event").slice(0,40)})};
  window.__wwt=1;
})();
