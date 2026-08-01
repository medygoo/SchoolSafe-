/* ============================================================
   Le Sage — shared site behaviour
   scroll progress · reveal-on-scroll · count-up · parallax
   sticky-header shrink · mobile menu · gallery lightbox
   ============================================================ */
(function(){
  var reduce = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  /* ---- inject progress bar ---- */
  var bar = document.createElement('div');
  bar.className = 'progress';
  document.body.appendChild(bar);
  function onScroll(){
    var h = document.documentElement;
    var max = h.scrollHeight - h.clientHeight;
    bar.style.width = (max > 0 ? (h.scrollTop / max) * 100 : 0) + '%';
  }
  window.addEventListener('scroll', onScroll, {passive:true}); onScroll();

  /* ---- sticky header shrink ---- */
  var header = document.querySelector('header');
  if(header){
    var hs = function(){ header.classList.toggle('scrolled', window.scrollY > 24); };
    window.addEventListener('scroll', hs, {passive:true}); hs();
  }

  /* ---- mobile menu ---- */
  var burger = document.querySelector('.burger');
  var drawer = document.querySelector('.mobile-menu');
  var scrim  = document.querySelector('.scrim');
  function closeMenu(){ if(burger)burger.classList.remove('open'); if(drawer)drawer.classList.remove('open'); if(scrim)scrim.classList.remove('open'); document.body.style.overflow=''; }
  function openMenu(){ burger.classList.add('open'); drawer.classList.add('open'); scrim.classList.add('open'); document.body.style.overflow='hidden'; }
  if(burger && drawer){
    burger.addEventListener('click', function(){ drawer.classList.contains('open') ? closeMenu() : openMenu(); });
    if(scrim) scrim.addEventListener('click', closeMenu);
    drawer.querySelectorAll('a').forEach(function(a){ a.addEventListener('click', closeMenu); });
  }

  /* ---- gallery lightbox ---- */
  var figs = document.querySelectorAll('.g-grid figure');
  if(figs.length){
    var lb = document.createElement('div');
    lb.className = 'lightbox';
    lb.innerHTML = '<button class="lb-close" aria-label="Fermer">&times;</button><button class="lb-nav lb-prev" aria-label="Précédent">&#8249;</button><img alt=""/><button class="lb-nav lb-next" aria-label="Suivant">&#8250;</button><div class="lb-cap"></div>';
    document.body.appendChild(lb);
    var lbImg = lb.querySelector('img'), lbCap = lb.querySelector('.lb-cap');
    var srcs = [], caps = [], idx = 0;
    figs.forEach(function(f,i){
      var img = f.querySelector('img'); var cap = f.querySelector('figcaption');
      srcs.push(img.src); caps.push(cap ? cap.textContent : '');
      f.addEventListener('click', function(){ idx=i; show(); lb.classList.add('open'); document.body.style.overflow='hidden'; });
    });
    function show(){ lbImg.src = srcs[idx]; lbCap.textContent = caps[idx]; }
    function close(){ lb.classList.remove('open'); document.body.style.overflow=''; }
    lb.querySelector('.lb-close').addEventListener('click', close);
    lb.querySelector('.lb-next').addEventListener('click', function(e){ e.stopPropagation(); idx=(idx+1)%srcs.length; show(); });
    lb.querySelector('.lb-prev').addEventListener('click', function(e){ e.stopPropagation(); idx=(idx-1+srcs.length)%srcs.length; show(); });
    lb.addEventListener('click', function(e){ if(e.target===lb) close(); });
    document.addEventListener('keydown', function(e){
      if(!lb.classList.contains('open')) return;
      if(e.key==='Escape') close();
      if(e.key==='ArrowRight'){ idx=(idx+1)%srcs.length; show(); }
      if(e.key==='ArrowLeft'){ idx=(idx-1+srcs.length)%srcs.length; show(); }
    });
  }

  if(reduce) return;

  /* ---- reveal-on-scroll ---- */
  function tag(sel, cls){
    document.querySelectorAll(sel).forEach(function(el){
      if(el.closest('.hero-inner') || el.closest('.ph-inner')) return;
      el.classList.add('reveal'); if(cls) el.classList.add(cls);
    });
  }
  tag('.sec-head');
  tag('.about-figure', 'r-left');
  tag('.about-grid > div:last-child', 'r-right');
  tag('.pillar'); tag('.prog-card', 'r-zoom'); tag('.person', 'r-zoom');
  tag('.ex-cell'); tag('.g-grid figure', 'r-zoom'); tag('.t-card', 'r-rot');
  tag('.enroll .info', 'r-left'); tag('form.card', 'r-right'); tag('.fact');
  tag('.stat'); tag('.feature-row'); tag('.lead-card', 'r-zoom');
  tag('.info-block', 'r-left'); tag('.contact-card');
  tag('.kid-card', 'r-zoom'); tag('.day-step', 'r-zoom'); tag('.polaroid'); tag('.fun-stat', 'r-zoom');

  /* stagger siblings */
  ['.pillars','.prog-grid','.team-grid','.ex-grid','.g-grid','.t-grid','.stats .wrap','.facts','.feature-list','.lead-grid','.kids-grid','.day-track','.wall-grid','.kid-fun'].forEach(function(g){
    document.querySelectorAll(g).forEach(function(p){
      Array.prototype.forEach.call(p.children, function(c,i){
        if(c.classList.contains('reveal')) c.style.transitionDelay = (i%4*0.1)+'s';
      });
    });
  });

  var io = new IntersectionObserver(function(entries){
    entries.forEach(function(e){ if(e.isIntersecting){ e.target.classList.add('in'); io.unobserve(e.target); } });
  }, {threshold:0.14, rootMargin:'0px 0px -7% 0px'});
  document.querySelectorAll('.reveal').forEach(function(el){ io.observe(el); });

  /* ---- count-up ---- */
  function countUp(el){
    var raw = el.getAttribute('data-count') || el.textContent.trim();
    var m = raw.match(/^(\d+)(.*)$/); if(!m) return;
    var target = parseInt(m[1],10), suffix = m[2], t0=null, dur=1500;
    function step(ts){ if(!t0)t0=ts; var p=Math.min((ts-t0)/dur,1); var e=1-Math.pow(1-p,3);
      el.textContent = Math.round(e*target)+suffix; if(p<1) requestAnimationFrame(step); }
    requestAnimationFrame(step);
  }
  var statIO = new IntersectionObserver(function(entries){
    entries.forEach(function(e){ if(e.isIntersecting){ countUp(e.target); statIO.unobserve(e.target); } });
  }, {threshold:0.6});
  document.querySelectorAll('.stat .num, .ex-cell .num').forEach(function(el){ statIO.observe(el); });

  /* ---- hero parallax ---- */
  document.querySelectorAll('.hero-bg, .page-hero .ph-bg').forEach(function(bg){
    window.addEventListener('scroll', function(){
      var y = window.scrollY;
      if(y < window.innerHeight){ bg.style.transform = 'translateY('+(y*0.16)+'px)'; }
    }, {passive:true});
  });
})();
