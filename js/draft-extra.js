/* Черновик темы: ползунок «чертёж → готовая мебель».
   Всё остальное поведение страницы — в js/main.js. */
(function () {
  "use strict";

  var rev = document.getElementById("rev");
  if (!rev) return;

  var dragging = false;

  function setPos(clientX) {
    var r = rev.getBoundingClientRect();
    var pct = ((clientX - r.left) / r.width) * 100;
    pct = Math.max(2, Math.min(98, pct));
    rev.style.setProperty("--pos", pct.toFixed(1) + "%");
    rev.setAttribute("aria-valuenow", Math.round(pct));
    rev.classList.add("is-touched");
  }

  rev.addEventListener("pointerdown", function (e) {
    dragging = true;
    rev.setPointerCapture(e.pointerId);
    setPos(e.clientX);
  });
  rev.addEventListener("pointermove", function (e) {
    if (dragging) setPos(e.clientX);
  });
  ["pointerup", "pointercancel"].forEach(function (ev) {
    rev.addEventListener(ev, function () { dragging = false; });
  });

  // стрелками с клавиатуры
  rev.addEventListener("keydown", function (e) {
    var cur = parseFloat(rev.style.getPropertyValue("--pos")) || 52;
    if (e.key === "ArrowLeft") cur -= 4;
    else if (e.key === "ArrowRight") cur += 4;
    else return;
    e.preventDefault();
    cur = Math.max(2, Math.min(98, cur));
    rev.style.setProperty("--pos", cur + "%");
    rev.setAttribute("aria-valuenow", Math.round(cur));
    rev.classList.add("is-touched");
  });
})();
