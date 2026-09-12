from icons import icon_svg, glyph_svg
cells = []
for n in ["swept", "impeller", "four"]:
    cells.append(f'<div style="display:flex;flex-direction:column;gap:14px;align-items:center">'
                 f'{icon_svg(n, 300, n + "a")}'
                 f'<div style="display:flex;gap:14px;align-items:end">{icon_svg(n, 64, n + "b")}{icon_svg(n, 32, n + "c")}{icon_svg(n, 16, n + "d")}</div>'
                 f'{glyph_svg(n, 120, n + "g", "#ffffff", "#0b1226", show_wake=True)}</div>')
open("preview.html", "w").write('<html><body style="margin:0;background:#111215;display:flex;gap:40px;padding:30px">' + "".join(cells) + "</body></html>")
print("preview.html")
