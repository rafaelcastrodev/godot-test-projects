class_name FlapbirdPipe
extends Area2D

signal pipe_touched;

@onready var sprite_2d: Sprite2D = $Sprite2D;

func _ready() -> void:
	body_entered.connect(_on_body_entered_pipe.bind());
#}

func get_size() -> Vector2:
	return sprite_2d.get_rect().size * self.scale;
#}

func _on_body_entered_pipe(body: Node2D) -> void:
	#print_debug(body);
	pipe_touched.emit();
#}
