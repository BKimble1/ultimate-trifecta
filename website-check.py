from pathlib import Path
from html.parser import HTMLParser
from urllib.parse import urlsplit
root=Path(__file__).resolve().parent/'website'
errors=[]
class Check(HTMLParser):
    def __init__(self,p): super().__init__(); self.p=p
    def handle_starttag(self,tag,attrs):
        a=dict(attrs)
        for key in ('href','src'):
            v=a.get(key,'')
            if v.startswith('/') and not v.startswith('//'):
                path=root/urlsplit(v).path.lstrip('/')
                if path.is_dir(): path=path/'index.html'
                if not path.is_file(): errors.append(f'{self.p}: missing {v}')
for p in root.rglob('*.html'):
    s=p.read_text()
    if chr(8212) in s or '&mdash;' in s: errors.append(f'{p}: em dash')
    Check(p).feed(s)
if errors: raise SystemExit('\n'.join(errors))
print('All internal file paths and punctuation checks passed.')
