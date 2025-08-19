class_name FlapbirdPlayer
extends CharacterBody2D

@onready var sprite_2d: Sprite2D = $Sprite2D

func get_size() -> Vector2:
	return sprite_2d.get_rect().size * self.scale;
#}
