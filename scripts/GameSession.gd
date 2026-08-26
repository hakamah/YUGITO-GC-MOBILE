extends Node

var ally_deck: Array[String] = []
var enemy_deck: Array[String] = []
var ally_starters: Array[String] = []
var enemy_starters: Array[String] = []
var starting_team: String = "ally"
var draft_first_team: String = "ally"
var configured: bool = false

# Mode QA déterministe pour les scénarios de parité PC <-> Godot.
var parity_rng_enabled: bool = false
var parity_seed: int = 1

func clear() -> void:
    ally_deck.clear()
    enemy_deck.clear()
    ally_starters.clear()
    enemy_starters.clear()
    starting_team = "ally"
    draft_first_team = "ally"
    configured = false

func enable_parity_rng(seed_value: int) -> void:
    parity_rng_enabled = true
    parity_seed = seed_value

func disable_parity_rng() -> void:
    parity_rng_enabled = false

func configure_match(p_ally_deck: Array[String], p_enemy_deck: Array[String], p_ally_starters: Array[String], p_enemy_starters: Array[String], p_starting_team: String, p_draft_first_team: String) -> void:
    ally_deck = p_ally_deck.duplicate()
    enemy_deck = p_enemy_deck.duplicate()
    ally_starters = p_ally_starters.duplicate()
    enemy_starters = p_enemy_starters.duplicate()
    starting_team = p_starting_team
    draft_first_team = p_draft_first_team
    configured = true
