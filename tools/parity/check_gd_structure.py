from __future__ import annotations
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
FILES = sorted((ROOT / "scripts").glob("*.gd")) + sorted((ROOT / "tools" / "parity").glob("*.gd"))
PAIRS = {')':'(', ']':'[', '}':'{'}
OPEN = set(PAIRS.values())
CLOSE = set(PAIRS)


def check(path: Path) -> None:
    text = path.read_text(encoding='utf-8')
    stack: list[tuple[str,int,int]] = []
    quote: str | None = None
    triple = False
    escaped = False
    line = 1
    col = 0
    i = 0
    while i < len(text):
        ch = text[i]
        col += 1
        if ch == '\n':
            line += 1; col = 0
            if quote is not None and not triple:
                raise AssertionError(f"{path}: chaîne non fermée avant L{line}")
            i += 1; continue
        if quote is not None:
            if escaped:
                escaped = False; i += 1; continue
            if ch == '\\':
                escaped = True; i += 1; continue
            if triple and text.startswith(quote * 3, i):
                quote = None; triple = False; i += 3; col += 2; continue
            if not triple and ch == quote:
                quote = None
            i += 1; continue
        if ch == '#':
            nl = text.find('\n', i)
            if nl < 0: break
            i = nl; continue
        if ch in ('\"', "'"):
            if text.startswith(ch * 3, i):
                quote = ch; triple = True; i += 3; col += 2; continue
            quote = ch; triple = False; i += 1; continue
        if ch in OPEN:
            stack.append((ch,line,col))
        elif ch in CLOSE:
            if not stack or stack[-1][0] != PAIRS[ch]:
                raise AssertionError(f"{path}: fermeture {ch} inattendue L{line}:{col}")
            stack.pop()
        i += 1
    if quote is not None:
        raise AssertionError(f"{path}: chaîne non fermée en fin de fichier")
    if stack:
        ch,l,c = stack[-1]
        raise AssertionError(f"{path}: {ch} non fermé depuis L{l}:{c}")
    print(f"[OK] {path.relative_to(ROOT)}")


def main() -> int:
    for path in FILES:
        check(path)
    print(f"ALL GDSCRIPT STRUCTURE CHECKS PASSED ({len(FILES)} files)")
    return 0

if __name__ == '__main__':
    raise SystemExit(main())
