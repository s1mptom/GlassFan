"""Writes the canvas artboards: one identical sheet per blade direction, so the
only thing that differs between them is the fan."""
import json, re, pathlib
from icons import icon_svg, glyph_svg, dial_parts

FONT = '-apple-system, "SF Pro Display", "SF Pro Text", "Helvetica Neue", sans-serif'

def canon(svg):
    """Explicit end tags everywhere - the editor wants canonical HTML."""
    return re.sub(r"<(\w+)([^<>]*?)\s*/>", r"<\1\2></\1>", svg.replace("\n", ""))

def caption(text):
    return (f'<div style="font-size: 10.5px; font-weight: 500; letter-spacing: 0.07em; '
            f'text-transform: uppercase; color: rgba(255, 255, 255, 0.4)">{text}</div>')

def tile_label(text):
    return f'<div style="font-size: 11px; color: rgba(255, 255, 255, 0.45); text-align: center">{text}</div>'

def dock(name, key, wallpaper, shelf, border):
    icons = "".join(f'<div style="display: flex; flex-direction: column; align-items: center">{canon(icon_svg(name, s, f"{key}{s}"))}</div>'
                    for s in (128, 64, 32, 16))
    return (f'<div style="display: flex; flex-direction: column; gap: 8px; flex-grow: 1">'
            f'<div style="background: {wallpaper}; border-radius: 18px; padding: 14px">'
            f'<div style="display: flex; align-items: flex-end; gap: 18px; padding: 10px 16px; border-radius: 16px; '
            f'background: {shelf}; border: 0.5px solid {border}">{icons}</div></div>')

def dial_tile(name, key, rpm, size, label, show_value=True):
    static, turning, spinning = dial_parts(name, size, key, rpm)
    spin = ' class="gf-spin"' if spinning else ""
    number = ""
    if show_value:
        number = (f'<div style="position: absolute; left: 0; top: 0; width: {size}px; height: {size}px; display: flex; '
                  f'flex-direction: column; align-items: center; justify-content: center">'
                  f'<div style="font-size: {size * 0.30:.1f}px; font-weight: 600; font-variant-numeric: tabular-nums; '
                  f'letter-spacing: -0.02em; color: #ffffff; line-height: 1">{rpm}</div>'
                  f'<div style="font-size: {size * 0.08:.1f}px; color: rgba(255, 255, 255, 0.4); margin-top: 3px">об/мин</div></div>')
    return (f'<div style="display: flex; flex-direction: column; gap: 8px; align-items: center">'
            f'<div style="width: 142px; height: 142px; border-radius: 16px; background: #17191e; '
            f'border: 0.5px solid rgba(255, 255, 255, 0.07); display: flex; align-items: center; justify-content: center">'
            f'<div style="position: relative; width: {size}px; height: {size}px">'
            f'<div{spin} style="position: absolute; left: 0; top: 0; width: {size}px; height: {size}px">{canon(turning)}</div>'
            f'{canon(static)}{number}</div></div>{tile_label(label)}</div>')

def glyph_tile(name, key, color, ground, hub_color, label, border):
    return (f'<div style="display: flex; flex-direction: column; gap: 8px; align-items: center">'
            f'<div style="width: 142px; height: 142px; border-radius: 16px; background: {ground}; '
            f'border: 0.5px solid {border}; display: flex; align-items: center; justify-content: center">'
            f'{canon(glyph_svg(name, 112, key, color, hub_color))}</div>{tile_label(label)}</div>')

def sheet(name, title, body):
    k = name[:2]
    return f'''<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <script src="./support.js"></script>
</head>
<body>
<x-dc>
<helmet>
  <style>
    body {{ margin: 0; background: #0c0d10; font-family: {FONT}; }}
    a {{ color: #6aa9f0; }} a:hover {{ color: #9cc6f6; }}
    @keyframes gfspin {{ to {{ transform: rotate(360deg); }} }}
    .gf-spin {{ animation: gfspin 2.4s linear infinite; transform-origin: 50% 50%; }}
    @media (prefers-reduced-motion: reduce) {{ .gf-spin {{ animation: none; }} }}
  </style>
</helmet>
<div style="width: 1320px; min-height: 700px; box-sizing: border-box; padding: 36px 40px 40px; background: #111215; color: #ffffff; display: flex; flex-direction: column; gap: 28px">
  <div style="display: flex; align-items: baseline; gap: 22px">
    <div style="font-size: 26px; font-weight: 600; letter-spacing: -0.01em; white-space: nowrap">{title}</div>
    <div style="font-size: 13px; line-height: 1.5; color: rgba(255, 255, 255, 0.52); max-width: 820px; text-wrap: pretty">{body}</div>
  </div>
  <div style="display: flex; gap: 40px; align-items: flex-start">
    <div style="display: flex; flex-direction: column; gap: 10px">
      {caption("Иконка · 1024")}
      <div style="width: 460px; height: 460px; border-radius: 22px; background: #0b0c0f; border: 0.5px solid rgba(255, 255, 255, 0.06); display: flex; align-items: center; justify-content: center">{canon(icon_svg(name, 440, k + "big"))}</div>
    </div>
    <div style="display: flex; flex-direction: column; gap: 24px; flex-grow: 1">
      <div style="display: flex; flex-direction: column; gap: 10px">
        {caption("В доке · 128 · 64 · 32 · 16")}
        <div style="display: flex; gap: 14px">
          {dock(name, k + "dd", "linear-gradient(135deg, #1d2a45, #241a36)", "rgba(40, 42, 52, 0.72)", "rgba(255, 255, 255, 0.14)")}<div style="font-size: 11px; color: rgba(255, 255, 255, 0.45)">Тёмные обои</div></div>
          {dock(name, k + "dl", "linear-gradient(135deg, #dfe6f1, #efe7f2)", "rgba(255, 255, 255, 0.55)", "rgba(0, 0, 0, 0.08)")}<div style="font-size: 11px; color: rgba(255, 255, 255, 0.45)">Светлые обои</div></div>
        </div>
      </div>
      <div style="display: flex; flex-direction: column; gap: 10px">
        {caption("Глиф и циферблат в приложении")}
        <div style="display: flex; gap: 14px">
          {glyph_tile(name, k + "gd", "#ffffff", "#17191e", "#0b1226", "Глиф", "rgba(255, 255, 255, 0.07)")}
          {glyph_tile(name, k + "gl", "#10141a", "#eef1f6", "#ffffff", "На светлом", "rgba(0, 0, 0, 0.06)")}
          {dial_tile(name, k + "d0", 0, 132, "В покое · 0")}
          {dial_tile(name, k + "d1", 2600, 132, "Вращение · шлейф позади")}
          {dial_tile(name, k + "d2", 2600, 58, "Сайдбар · 58", show_value=False)}
        </div>
      </div>
    </div>
  </div>
</div>
</x-dc>
</body>
</html>
'''

SHEETS = [
    ("Main.dc.html", "swept", "Шесть изогнутых",
     "Шесть серповидных лопастей, кончики отогнуты назад — против вращения, так что шлейф продолжает изгиб лопасти. "
     "Уравновешен, как чётный вентилятор, и сразу читается как кулер; различим и в 32. "
     "Цена: изгиб отменяет зеркальную симметрию — баланс держится на повороте, а не на отражении."),
    ("Impeller.dc.html", "impeller", "Крыльчатка",
     "Девять тонких лопастей вокруг широкой ступицы — так выглядит турбина внутри MacBook. "
     "Самый богатый рисунок в крупном размере. "
     "Цена: в 32 и меньше лопасти сливаются в диск."),
    ("StraightFour.dc.html", "four", "Прямые четыре",
     "Четыре широкие лопасти без изгиба — симметрия по обеим осям, самый чёткий силуэт в 16. "
     "Цена: читается скорее как пропеллер, чем как кулер, и шлейфу почти не за чем тянуться."),
]

layout = {"pages": [{"id": "page-1", "name": "Выбрано"}, {"id": "page-2", "name": "Отложено"}],
          "artboards": [], "annotations": [], "launch": {"view": "canvas", "page": "page-1"}}
for i, (fname, name, title, body) in enumerate(SHEETS):
    pathlib.Path(fname).write_text(sheet(name, title, body))
    layout["artboards"].append({"file": fname, "x": 0, "y": 0 if i == 0 else (i - 1) * 840,
                                "w": 1320, "h": 700, "page": "page-1" if i == 0 else "page-2",
                                "title": ["A · Шесть изогнутых", "B · Крыльчатка", "C · Прямые четыре"][i]})
layout["annotations"].append({
    "id": "brief", "x": 0, "y": -170, "w": 560, "page": "page-1",
    "text": "Выбран вариант A — шесть изогнутых лопастей.\n\n"
            "Той же формулой теперь рисуются иконка приложения и циферблат внутри него. "
            "Шлейф — только позади лопасти: её копии, повёрнутые против вращения и гаснущие.\n\n"
            "B и C — на странице «Отложено»."})
pathlib.Path("canvas.json").write_text(json.dumps(layout, ensure_ascii=False, indent=2))
for f in ["Main.dc.html", "Impeller.dc.html", "StraightFour.dc.html"]:
    print(f, pathlib.Path(f).stat().st_size // 1024, "KB")
