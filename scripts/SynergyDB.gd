class_name YugitoSynergyDB
extends RefCounted

const FAMILIES: Array = [
    ["sarutobi", "jiraiya", "minato"],
    ["gaara", "chiyo", "kankuro", "temari"],
    ["jiraiya", "tsunade", "orochimaru", "sarutobi"],
    ["orochimaru", "sasuke", "kabuto"],
    ["orochimaru", "kimimaro", "kabuto"],
    ["kakashi", "gai", "kurenai", "asuma"],
    ["kakashi", "sasuke", "naruto", "sakura"],
    ["yamato", "naruto", "sakura", "kakashi", "sai"],
    ["sasuke", "karin", "jugo", "suigetsu"],
    ["gai", "rock_lee", "tenten", "neji"],
    ["kurenai", "shino", "kiba", "hinata"],
    ["asuma", "ino", "shikamaru", "choji"],
    ["mei", "ao", "chojuro"],
    ["kisame", "gengetsu", "zabuza", "suigetsu"],
    ["a3_raikage", "a_raikage", "killer_bee", "omoi", "karui"],
    ["minato", "kakashi", "obito", "rin"],
    ["minato", "naruto", "kushina"],
    ["obito", "sasuke", "itachi", "madara", "shisui"],
    ["danzo", "itachi", "kakashi", "yamato", "sai"],
    ["onoki", "kurotsuchi", "mu"]
]

const DUOS: Array = [
    ["kisame", "itachi"], ["kakuzu", "hidan"], ["deidara", "sasori"],
    ["obito", "deidara"], ["madara", "obito"], ["tsunade", "sakura"],
    ["tsunade", "shizune"], ["nagato", "konan"], ["sakura", "ino"],
    ["shino", "torune"], ["konohamaru", "naruto"], ["konohamaru", "sarutobi"],
    ["hashirama", "tsunade"], ["haku", "zabuza"], ["tobirama", "sarutobi"],
    ["anko", "orochimaru"], ["killer_bee", "naruto"], ["danzo", "yamato"],
    ["tobi", "deidara"], ["tobi", "zetsu"], ["zetsu", "deidara"],
    ["zetsu", "sasori"], ["zetsu", "itachi"], ["zetsu", "kisame"],
    ["zetsu", "hidan"], ["zetsu", "kakuzu"], ["zetsu", "madara"],
    ["zetsu", "konan"], ["zetsu", "nagato"]
]

const AKATSUKI: Array[String] = ["deidara", "sasori", "itachi", "kisame", "hidan", "kakuzu", "madara", "konan", "nagato", "tobi"]

static func _contains_all(container_ids: Array, wanted_ids: Array[String]) -> bool:
    for cid: String in wanted_ids:
        if not container_ids.has(cid):
            return false
    return true

static func bonus_for(card_id: String, field_ids: Array[String]) -> float:
    if not field_ids.has(card_id):
        return 0.0
    if card_id == "zetsu":
        for other_id: String in field_ids:
            if other_id != card_id and AKATSUKI.has(other_id):
                return 0.15
    elif AKATSUKI.has(card_id) and field_ids.has("zetsu"):
        return 0.15

    if field_ids.size() == 3:
        for family_raw: Variant in FAMILIES:
            var family: Array = family_raw as Array
            var all_inside: bool = true
            for fid: String in field_ids:
                if not family.has(fid):
                    all_inside = false
                    break
            if all_inside:
                return 0.20

    var best: float = 0.0
    for other_id: String in field_ids:
        if other_id == card_id:
            continue
        for family_raw: Variant in FAMILIES:
            var family: Array = family_raw as Array
            if family.has(card_id) and family.has(other_id):
                best = maxf(best, 0.125)
        for duo_raw: Variant in DUOS:
            var duo: Array = duo_raw as Array
            if duo.has(card_id) and duo.has(other_id):
                best = maxf(best, 0.15)
    return best

static func description(card_id: String, cards_by_id: Dictionary) -> String:
    var lines: Array[String] = []
    for family_raw: Variant in FAMILIES:
        var family: Array = family_raw as Array
        if not family.has(card_id):
            continue
        var mates: Array[String] = []
        for member: Variant in family:
            var cid: String = str(member)
            if cid == card_id:
                continue
            var data: Dictionary = cards_by_id.get(cid, {}) as Dictionary
            mates.append(str(data.get("name", cid.replace("_", " ").capitalize())))
        mates.sort()
        if not mates.is_empty():
            lines.append("S 3/3  +20 % ALL STATS  •  2 membres = +12,5 %\n" + " • ".join(mates))

    var duo_mates: Array[String] = []
    for duo_raw: Variant in DUOS:
        var duo: Array = duo_raw as Array
        if not duo.has(card_id):
            continue
        for member: Variant in duo:
            var cid: String = str(member)
            if cid == card_id:
                continue
            var data: Dictionary = cards_by_id.get(cid, {}) as Dictionary
            var name: String = str(data.get("name", cid.replace("_", " ").capitalize()))
            if not duo_mates.has(name):
                duo_mates.append(name)
    if card_id == "zetsu":
        duo_mates.append("N'importe quel membre de l'Akatsuki")
    elif AKATSUKI.has(card_id):
        var zdata: Dictionary = cards_by_id.get("zetsu", {}) as Dictionary
        var zname: String = str(zdata.get("name", "Zetsu"))
        if not duo_mates.has(zname):
            duo_mates.append(zname)
    duo_mates.sort()
    if not duo_mates.is_empty():
        lines.append("S 2/2  +15 % ALL STATS\n" + " • ".join(duo_mates))
    if lines.is_empty():
        return "Aucun lien de synergie."
    return "\n\n".join(lines)
