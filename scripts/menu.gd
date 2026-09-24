extends Control

## Title screen. New game loads the board; Settings swaps to an empty page in
## this same scene rather than a file of its own, because a page with nothing
## on it does not justify one yet.

const GAME_SCENE := "res://scenes/main.tscn"

@onready var _title_page: Control = $Center/Title
@onready var _settings_page: Control = $Center/Settings


func _ready() -> void:
	$Center/Title/NewGameButton.pressed.connect(_on_new_game_pressed)
	$Center/Title/SettingsButton.pressed.connect(_on_settings_pressed)
	$Center/Settings/BackButton.pressed.connect(_on_back_pressed)
	show_settings(false)


func show_settings(on: bool) -> void:
	_title_page.visible = not on
	_settings_page.visible = on


func _on_new_game_pressed() -> void:
	get_tree().change_scene_to_file(GAME_SCENE)


func _on_settings_pressed() -> void:
	show_settings(true)


func _on_back_pressed() -> void:
	show_settings(false)
