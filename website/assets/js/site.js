/* Ultimate Trifecta: official site. No trackers, no third parties. */
(function () {
  "use strict";
  var doc = document.documentElement;
  doc.classList.remove("no-js");
  doc.classList.add("js");

  var reduce = window.matchMedia("(prefers-reduced-motion: reduce)");
  var saveData = navigator.connection && navigator.connection.saveData;
  var hasIO = "IntersectionObserver" in window;

  /* header: solid once the page moves */
  var header = document.querySelector(".site-header");
  var heroEl = document.querySelector(".hero, .page-hero.media, .lost");
  function onScroll() {
    if (!header) return;
    var y = window.scrollY || window.pageYOffset;
    var limit = heroEl ? Math.max(40, heroEl.offsetHeight * 0.12) : 10;
    header.classList.toggle("solid", y > limit || !heroEl);
  }
  onScroll();
  window.addEventListener("scroll", onScroll, { passive: true });

  /* mobile menu */
  var menuBtn = document.querySelector(".menu-btn");
  var menu = document.getElementById("mobile-menu");
  function setMenu(open) {
    doc.classList.toggle("menu-open", open);
    document.body.style.overflow = open ? "hidden" : "";
    if (menuBtn) {
      menuBtn.setAttribute("aria-expanded", open ? "true" : "false");
      menuBtn.setAttribute("aria-label", open ? "Close menu" : "Open menu");
    }
    if (menu) {
      menu.setAttribute("aria-hidden", open ? "false" : "true");
      if (open) menu.removeAttribute("inert"); else menu.setAttribute("inert", "");
    }
    if (menu) {
      var links = menu.querySelectorAll("a");
      for (var i = 0; i < links.length; i++) links[i].tabIndex = open ? 0 : -1;
    }
    if (header) header.classList.toggle("solid", open || (window.scrollY > 10));
  }
  if (menuBtn && menu) {
    setMenu(false);
    menuBtn.addEventListener("click", function () { setMenu(!doc.classList.contains("menu-open")); });
    menu.addEventListener("click", function (e) { if (e.target.closest("a")) setMenu(false); });
    window.addEventListener("resize", function () { if (window.innerWidth > 900) setMenu(false); });
  }

  /* reveal on scroll */
  var reveals = document.querySelectorAll(".reveal");
  if (hasIO && !reduce.matches) {
    var rio = new IntersectionObserver(function (entries) {
      entries.forEach(function (e) {
        if (e.isIntersecting) { e.target.classList.add("in"); rio.unobserve(e.target); }
      });
    }, { rootMargin: "0px 0px -8% 0px", threshold: 0.08 });
    reveals.forEach(function (el) { rio.observe(el); });
  } else {
    reveals.forEach(function (el) { el.classList.add("in"); });
  }

  /* videos: load near the viewport, play only while visible, never under
     reduced motion or Data Saver (the poster stays) */
  var motionOK = !reduce.matches && !saveData;
  function pick(v) {
    var small = window.innerWidth < 760 || (window.devicePixelRatio || 1) * window.innerWidth < 1100;
    return (small && v.dataset.srcSmall) ? v.dataset.srcSmall : v.dataset.src;
  }
  function load(v) {
    if (v.dataset.loaded) return;
    v.dataset.loaded = "1";
    v.muted = true;
    v.setAttribute("muted", "");
    v.playsInline = true;
    v.src = pick(v);
    v.addEventListener("playing", function () { v.classList.add("ready"); }, { once: true });
    v.addEventListener("loadeddata", function () { if (v.classList.contains("on") || !v.closest(".screen")) v.classList.add("ready"); }, { once: true });
  }
  function play(v) {
    if (!motionOK || v.dataset.userPaused) return;
    load(v);
    var p = v.play();
    if (p && p.catch) p.catch(function () {});
  }
  var autos = document.querySelectorAll("video[data-src]");
  if (motionOK && hasIO) {
    var vio = new IntersectionObserver(function (entries) {
      entries.forEach(function (e) {
        var v = e.target;
        if (e.isIntersecting) {
          if (v.closest(".screen") && !v.classList.contains("on")) { load(v); return; }
          play(v);
        } else if (!v.paused) {
          v.pause();
        }
      });
    }, { rootMargin: "200px 0px", threshold: 0.01 });
    autos.forEach(function (v) { vio.observe(v); });
  }
  reduce.addEventListener && reduce.addEventListener("change", function () { motionOK = !reduce.matches && !saveData; if (!motionOK) autos.forEach(function (v) { v.pause(); }); });

  /* hero pause */
  var pauseBtn = document.querySelector(".pause-btn");
  var heroVid = document.querySelector(".hero-media video");
  if (pauseBtn && heroVid) {
    if (!motionOK) { pauseBtn.classList.add("paused"); pauseBtn.setAttribute("aria-label", "Play background video"); }
    pauseBtn.addEventListener("click", function () {
      if (heroVid.paused) {
        delete heroVid.dataset.userPaused;
        load(heroVid);
        var p = heroVid.play(); if (p && p.catch) p.catch(function () {});
        pauseBtn.classList.remove("paused");
        pauseBtn.setAttribute("aria-label", "Pause background video");
      } else {
        heroVid.dataset.userPaused = "1";
        heroVid.pause();
        pauseBtn.classList.add("paused");
        pauseBtn.setAttribute("aria-label", "Play background video");
      }
    });
  }

  /* how a round plays: the pinned screen follows the step in view */
  var round = document.querySelector(".round");
  if (round && hasIO) {
    var steps = round.querySelectorAll(".step");
    var screenVids = round.querySelectorAll(".screen video");
    var bars = round.querySelectorAll(".progress i");
    var current = -1;
    function activate(i) {
      if (i === current) return;
      current = i;
      steps.forEach(function (s, k) { s.classList.toggle("on", k === i); });
      bars.forEach(function (b, k) { b.classList.toggle("on", k === i); b.classList.toggle("done", k < i); });
      screenVids.forEach(function (v, k) {
        var on = k === i;
        v.classList.toggle("on", on);
        if (on) {
          // (the pinned screen is hidden on phones: its clips stay unloaded there)
          if (motionOK && v.offsetParent !== null) { load(v); try { v.currentTime = 0; } catch (e) {} play(v); }
        } else if (!v.paused) { v.pause(); }
      });
    }
    var sio = new IntersectionObserver(function (entries) {
      entries.forEach(function (e) {
        if (e.isIntersecting) activate(Array.prototype.indexOf.call(steps, e.target));
      });
    }, { rootMargin: "-45% 0px -45% 0px", threshold: 0 });
    steps.forEach(function (s) { sio.observe(s); });
    activate(0);
  }

  /* trailer */
  var player = document.getElementById("player");
  if (player) {
    var pv = player.querySelector("video");
    var closeBtn = player.querySelector(".close");
    var opener = null;
    function openPlayer(e) {
      if (e) e.preventDefault();
      opener = document.activeElement;
      if (!pv.src) pv.src = pv.dataset.trailer;
      pv.muted = false;
      player.removeAttribute("inert");
      player.classList.add("open");
      player.setAttribute("aria-hidden", "false");
      document.body.style.overflow = "hidden";
      if (heroVid && !heroVid.paused) heroVid.pause();
      var p = pv.play(); if (p && p.catch) p.catch(function () {});
      closeBtn.focus();
    }
    function closePlayer() {
      player.classList.remove("open");
      player.setAttribute("aria-hidden", "true");
      player.setAttribute("inert", "");
      document.body.style.overflow = "";
      pv.pause();
      if (heroVid && motionOK && !heroVid.dataset.userPaused) { var p = heroVid.play(); if (p && p.catch) p.catch(function () {}); }
      if (opener) opener.focus();
    }
    document.querySelectorAll("[data-trailer]").forEach(function (b) { b.addEventListener("click", openPlayer); });
    closeBtn.addEventListener("click", closePlayer);
    player.addEventListener("click", function (e) { if (e.target === player) closePlayer(); });
    document.addEventListener("keydown", function (e) {
      if (e.key === "Escape" && player.classList.contains("open")) closePlayer();
      if (e.key === "Tab" && player.classList.contains("open")) {
        var f = [closeBtn, pv];
        var i = f.indexOf(document.activeElement);
        e.preventDefault();
        f[(i + (e.shiftKey ? f.length - 1 : 1)) % f.length].focus();
      }
    });
  }
  document.addEventListener("keydown", function (e) {
    if (e.key === "Escape" && doc.classList.contains("menu-open")) { setMenu(false); if (menuBtn) menuBtn.focus(); }
  });

  /* documents: the contents follow the reading position */
  var toc = document.querySelectorAll(".toc a");
  if (toc.length && hasIO) {
    var map = {};
    toc.forEach(function (a) { map[a.getAttribute("href").slice(1)] = a; });
    var heads = document.querySelectorAll(".doc h2[id]");
    var tio = new IntersectionObserver(function (entries) {
      entries.forEach(function (e) {
        if (e.isIntersecting) {
          toc.forEach(function (a) { a.classList.remove("on"); });
          var a = map[e.target.id];
          if (a) a.classList.add("on");
        }
      });
    }, { rootMargin: "0px 0px -70% 0px", threshold: 0 });
    heads.forEach(function (h) { tio.observe(h); });
  }
})();
