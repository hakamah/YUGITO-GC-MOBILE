from __future__ import annotations

from dataclasses import dataclass
import json
from pathlib import Path
from typing import Iterable


PROJECT_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_CARD_FILE = PROJECT_ROOT / "cards" / "core_set.json"


@dataclass(frozen=True)
class CardDefinition:
    id: str
    name: str
    stars: float
    max_hp: int
    taijutsu: int
    ninjutsu: int
    genjutsu: int
    element: str
    passive_name: str = ""
    passive: str = ""
    special_name: str = ""
    special: str = ""
    special_style: str | None = None
    image: str = ""
    roles: tuple[str, ...] = ()

    def stat(self, style: str) -> int:
        style = style.lower()
        if style == "taijutsu":
            return self.taijutsu
        if style == "ninjutsu":
            return self.ninjutsu
        if style == "genjutsu":
            return self.genjutsu
        raise ValueError(f"Style inconnu: {style}")

    @property
    def star_label(self) -> str:
        value = f"{self.stars:g}".replace(".", ",")
        return f"{value}★"

    @property
    def image_path(self) -> Path | None:
        if not self.image:
            return None
        path = Path(self.image)
        if not path.is_absolute():
            path = PROJECT_ROOT / path
        return path


def load_cards(path: Path | None = None) -> list[CardDefinition]:
    card_path = path or DEFAULT_CARD_FILE
    with card_path.open("r", encoding="utf-8") as fh:
        raw = json.load(fh)
    cards = [
        CardDefinition(
            id=item["id"],
            name=item["name"],
            stars=float(item.get("stars", 3.0)),
            max_hp=int(item["hp"]),
            taijutsu=int(item["taijutsu"]),
            ninjutsu=int(item["ninjutsu"]),
            genjutsu=int(item["genjutsu"]),
            element=item["element"].lower(),
            passive_name=item.get("passive_name", ""),
            passive=item.get("passive", ""),
            special_name=item.get("special_name", ""),
            special=item.get("special", ""),
            special_style=(item.get("special_style") or None),
            image=item.get("image", ""),
            roles=tuple(str(x).upper() for x in item.get("roles", []) if str(x).strip()),
        )
        for item in raw
    ]
    # Le panel de sélection et l'encyclopédie utilisent tous la même liste :
    # toujours 5★ -> 4,5★ -> 4★ -> 3,5★ -> 3★, puis ordre alphabétique.
    return sorted(cards, key=lambda card: (-card.stars, card.name.casefold()))


def card_ids(cards: Iterable[CardDefinition]) -> list[str]:
    return [card.id for card in cards]
