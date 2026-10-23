"""Build one offline HTML file and the Windows-friendly download ZIP; stdlib only."""
from pathlib import Path
import base64
from zipfile import ZipFile, ZIP_DEFLATED

root = Path(__file__).resolve().parents[1]
html = (root / 'index.html').read_text(encoding='utf-8')
html = html.replace('<link rel="stylesheet" href="style.css">', '<style>\n' + (root / 'style.css').read_text(encoding='utf-8') + '\n</style>')
html = html.replace('  <script src="model.js" defer></script>\n', '').replace('  <script src="art.js" defer></script>\n', '').replace('  <script src="map-view.js" defer></script>\n', '').replace('  <script src="game.js" defer></script>\n', '')
def script_text(name):
    source = (root / name).read_text(encoding='utf-8')
    if name == 'art.js':
        for asset in ['historical-sprites.png', 'historical-terrain.png']:
            encoded = base64.b64encode((root / 'assets' / asset).read_bytes()).decode('ascii')
            source = source.replace('assets/' + asset, 'data:image/png;base64,' + encoded)
    return source

scripts = '\n'.join('<script>\n' + script_text(name) + '\n</script>' for name in ['model.js', 'art.js', 'map-view.js', 'game.js'])
html = html.replace('</body>', scripts + '\n</body>')
(root / '河谷初生.html').write_text(html, encoding='utf-8')
out = root.parent / 'downloads' / 'riverdale-0.3.zip'
out.parent.mkdir(exist_ok=True)
with ZipFile(out, 'w', ZIP_DEFLATED) as archive:
    archive.write(root / '河谷初生.html', '河谷初生/河谷初生.html')
    archive.write(root / '开始游戏说明.txt', '河谷初生/开始游戏说明.txt')
with ZipFile(out) as archive:
    assert archive.testzip() is None
print(f'Built offline HTML ({len(html.encode("utf-8")):,} bytes) and {out.name} ({out.stat().st_size:,} bytes)')
