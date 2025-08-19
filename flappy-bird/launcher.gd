extends Node


const BIRD: String = "res://flapbird/flapbird.tscn";


@onready var btn_bird: Button = $BtnBird;

# Called when the node enters the scene tree for the first time.
func _ready() -> void:

	btn_bird.button_up.connect(_on_button_up.bind("bird"));

func _on_button_up(game: String) -> void:
	var scene;
	match game:
		"bird": scene = BIRD;

	get_tree().change_scene_to_file(scene);
#}
