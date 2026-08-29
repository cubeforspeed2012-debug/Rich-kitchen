#!/usr/bin/env python3
"""
Собирает черновые страницы из боевых.

Черновик = та же разметка (значит те же двуязычные data-атрибуты, форма,
лайтбокс, фильтры, scroll-сцены и аналитика), но с темой css/draft.css
и ссылками между черновыми страницами. Боевые файлы не трогаются.

Запуск:  python3 tools/build-draft.py
"""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# боевая страница -> черновая
PAGES = {
    "index.html":     "draft.html",
    "portfolio.html": "draft-portfolio.html",
    "matrasy.html":   "draft-matrasy.html",
    "reshetki.html":  "draft-reshetki.html",
}

FONTS_OLD = re.compile(
    r'<link href="https://fonts\.googleapis\.com/css2\?family=Cormorant[^"]*" rel="stylesheet">'
)
FONTS_NEW = (
    '<link href="https://fonts.googleapis.com/css2?'
    'family=Petrona:ital,wght@0,400;0,500;0,600;0,700;1,400;1,500'
    '&family=Archivo:wght@400;500;600;700'
    '&family=IBM+Plex+Mono:wght@400;500;600&display=swap" rel="stylesheet">'
)

DRAFT_BAR = (
    '\n<div class="draftbar">Черновик дизайна — '
    '<b>не финальная версия</b>, только для просмотра</div>\n'
)

# ползунок «чертёж → готово» вместо обычного фото в первом экране
HERO_OLD = ('<div class="frame"><img src="assets/img/hero.jpg" '
            'alt="Кухня Rich Kitchen" loading="eager"></div>')
HERO_NEW = '''<div class="frame">
        <div class="rev" id="rev" role="slider" tabindex="0"
             aria-label="Чертёж и готовая мебель"
             aria-valuemin="0" aria-valuemax="100" aria-valuenow="52">
          <img src="assets/img/hero.jpg" alt="Кухня Rich Kitchen" loading="eager">
          <div class="rev__blue"><img src="assets/img/hero.jpg" alt=""><span class="rev__grid"></span></div>
          <span class="rev__line"></span>
          <span class="rev__knob">↔</span>
          <span class="rev__lbl rev__lbl--l" data-ru="Чертёж" data-uz="Chizma">Чертёж</span>
          <span class="rev__lbl rev__lbl--r" data-ru="Готово" data-uz="Tayyor">Готово</span>
          <span class="rev__hint" data-ru="Потяните" data-uz="Torting">Потяните</span>
        </div>
      </div>'''


def convert(src_name: str, dst_name: str) -> str:
    src = (ROOT / src_name).read_text(encoding="utf-8")
    out = src

    # 1. тема
    out = out.replace("css/main.css?v=22", "css/draft.css?v=1")
    out = FONTS_OLD.sub(FONTS_NEW, out)

    # 2. ссылки между черновыми страницами (вместе с якорями: index.html#contact)
    for real, draft in PAGES.items():
        out = re.sub(rf'href="{re.escape(real)}(#[^"]*)?"',
                     lambda m, d=draft: f'href="{d}{m.group(1) or ""}"', out)

    # 3. черновик не должен попадать в поиск и подменять боевую страницу
    out = out.replace('<meta name="build" content="dev">',
                      '<meta name="build" content="dev">\n<meta name="robots" content="noindex, nofollow">')
    if 'name="robots"' not in out:
        out = out.replace("</head>", '<meta name="robots" content="noindex, nofollow">\n</head>', 1)
    out = re.sub(r'\n\s*<link rel="canonical"[^>]*>', "", out)

    # 4. заголовок вкладки — чтобы не путать с боевой
    out = re.sub(r"<title>(.*?)</title>",
                 lambda m: f"<title>Черновик — {m.group(1)}</title>", out, count=1, flags=re.S)

    # 5. ползунок «чертёж → готово» на главной
    if src_name == "index.html":
        out = out.replace(HERO_OLD, HERO_NEW, 1)

    # 6. скрипт черновика + плашка
    out = out.replace("</body>", f'{DRAFT_BAR}<script src="js/draft-extra.js?v=1"></script>\n</body>', 1)

    return out


def main() -> None:
    for real, draft in PAGES.items():
        if not (ROOT / real).exists():
            print(f"пропуск (нет файла): {real}")
            continue
        (ROOT / draft).write_text(convert(real, draft), encoding="utf-8")
        print(f"{real}  ->  {draft}")


if __name__ == "__main__":
    main()
