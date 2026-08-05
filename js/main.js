/* =========================================================
   Rich Kitchen — interactions
   ========================================================= */
(function () {
  "use strict";
  const $  = (s, c = document) => c.querySelector(s);
  const $$ = (s, c = document) => Array.from(c.querySelectorAll(s));

  /* ---------- Language ---------- */
  const html = document.documentElement;
  const STORE = "rk-lang";
  const langNodes = $$("[data-ru],[data-uz]");
  const phNodes   = $$("[data-ph-ru],[data-ph-uz]");

  function applyLang(lang) {
    html.setAttribute("data-lang", lang);
    html.setAttribute("lang", lang === "uz" ? "uz" : "ru");
    langNodes.forEach((el) => {
      const val = el.getAttribute("data-" + lang);
      if (val != null) el.innerHTML = val;
    });
    phNodes.forEach((el) => {
      const val = el.getAttribute("data-ph-" + lang);
      if (val != null) el.setAttribute("placeholder", val);
    });
    $$("#lang button").forEach((b) =>
      b.classList.toggle("active", b.dataset.set === lang)
    );
    try { localStorage.setItem(STORE, lang); } catch (e) {}
  }

  const saved = (() => { try { return localStorage.getItem(STORE); } catch (e) { return null; } })();
  applyLang(saved === "uz" ? "uz" : "ru");

  $("#lang").addEventListener("click", (e) => {
    const b = e.target.closest("button[data-set]");
    if (b) applyLang(b.dataset.set);
  });

  /* ---------- Year ---------- */
  const y = $("#year"); if (y) y.textContent = new Date().getFullYear();

  /* ---------- Nav scroll state ---------- */
  const nav = $("#nav");
  const onScroll = () => {
    nav.classList.toggle("scrolled", window.scrollY > 24);
    toTop.classList.toggle("show", window.scrollY > 640);
  };
  window.addEventListener("scroll", onScroll, { passive: true });

  /* ---------- Mobile menu ---------- */
  const mobile = $("#mobile");
  const openM = () => { mobile.classList.add("open"); document.body.style.overflow = "hidden"; };
  const closeM = () => { mobile.classList.remove("open"); document.body.style.overflow = ""; };
  $("#burger").addEventListener("click", openM);
  $("#mclose").addEventListener("click", closeM);
  $$("#mobile a").forEach((a) => a.addEventListener("click", closeM));

  /* ---------- Smooth anchor offset (sticky nav) ---------- */
  $$('a[href^="#"]').forEach((a) => {
    a.addEventListener("click", (e) => {
      const id = a.getAttribute("href");
      if (id.length < 2) return;
      const t = document.querySelector(id);
      if (!t) return;
      e.preventDefault();
      const top = t.getBoundingClientRect().top + window.scrollY - 74;
      window.scrollTo({ top, behavior: "smooth" });
    });
  });

  /* ---------- Reveal on scroll ---------- */
  const io = new IntersectionObserver((entries) => {
    entries.forEach((en) => {
      if (en.isIntersecting) { en.target.classList.add("in"); io.unobserve(en.target); }
    });
  }, { threshold: 0.14, rootMargin: "0px 0px -8% 0px" });
  $$(".reveal").forEach((el) => io.observe(el));

  /* ---------- Count-up stats ---------- */
  const counted = new WeakSet();
  const countIO = new IntersectionObserver((entries) => {
    entries.forEach((en) => {
      if (!en.isIntersecting || counted.has(en.target)) return;
      counted.add(en.target);
      const el = en.target;
      const target = parseInt(el.dataset.count, 10);
      const suffix = el.dataset.suffix || "";
      const dur = 1400; const start = performance.now();
      const tick = (now) => {
        const p = Math.min((now - start) / dur, 1);
        const eased = 1 - Math.pow(1 - p, 3);
        el.textContent = Math.round(target * eased) + suffix;
        if (p < 1) requestAnimationFrame(tick);
      };
      requestAnimationFrame(tick);
    });
  }, { threshold: 0.6 });
  $$("[data-count]").forEach((el) => countIO.observe(el));

  /* ---------- Marquee seamless loop ---------- */
  const mq = $("#marquee");
  if (mq) mq.innerHTML += mq.innerHTML;

  /* ---------- Projects filter ---------- */
  const filters = $("#filters");
  if (filters) {
    filters.addEventListener("click", (e) => {
      const b = e.target.closest("button[data-f]");
      if (!b) return;
      $$("button", filters).forEach((x) => x.classList.remove("active"));
      b.classList.add("active");
      const f = b.dataset.f;
      $$(".proj").forEach((p) => {
        const show = f === "all" || p.dataset.cat === f;
        p.classList.toggle("hide", !show);
      });
    });
  }

  /* ---------- Testimonials slider ---------- */
  const track = $("#tst-track");
  if (track) {
    const slides = $$(".tst__slide", track).length;
    let i = 0;
    const go = (n) => { i = (n + slides) % slides; track.style.transform = `translateX(-${i * 100}%)`; };
    $("#tst-next").addEventListener("click", () => { go(i + 1); reset(); });
    $("#tst-prev").addEventListener("click", () => { go(i - 1); reset(); });
    let timer = setInterval(() => go(i + 1), 6000);
    function reset() { clearInterval(timer); timer = setInterval(() => go(i + 1), 6000); }
  }

  /* ---------- Lead form ---------- */
  const form = $("#lead-form");
  if (form) {
    form.addEventListener("submit", (e) => {
      e.preventDefault();
      const name = $("#name"), phone = $("#phone");
      let ok = true;
      [name, phone].forEach((f) => {
        if (!f.value.trim()) { f.style.borderColor = "#B0735A"; ok = false; }
        else f.style.borderColor = "";
      });
      if (!ok) return;
      // NOTE: подключите отправку на бэкенд / Telegram-бот / e-mail здесь.
      $("#form-body").style.display = "none";
      $("#form-ok").classList.add("show");
    });
  }

  /* ---------- To top ---------- */
  const toTop = $("#toTop");
  toTop.addEventListener("click", () => window.scrollTo({ top: 0, behavior: "smooth" }));

  onScroll();
})();
