extends Node


@export var noise_height_texture: NoiseTexture2D;

var noise: Noise;
var noise_seed: int = 1;
var noise_value_array: Array[float] = [];
var width: int = 480;
var height: int = 270;
var x_start_render: Vector2i = Vector2i.ZERO;
var y_start_render: Vector2i = Vector2i.ZERO;

var source_id: int = 0;
var water_atlas_coord: Vector2i = Vector2i(1,2);
var land_atlas_coord: Vector2i = Vector2i(0,0);
var grass_atlas_coord: Vector2i = Vector2i(1,0);
var trees_atlas_coord: Vector2i = Vector2i(8,0);

@onready var overworld: Node2D = $"../Overworld";
@onready var layer_ground: TileMapLayer = $"../Overworld/LayerGround";
@onready var layer_water: TileMapLayer = $"../Overworld/LayerWater";
@onready var layer_grass: TileMapLayer = $"../Overworld/LayerGrass";
@onready var layer_trees: TileMapLayer = $"../Overworld/LayerTrees";

func _ready() -> void:
	randomize();
	noise_seed = randi();
	noise = noise_height_texture.noise;
	noise.seed = noise_seed;

	@warning_ignore("integer_division")
	x_start_render = Vector2i(width * -1 / 2, width / 2);
	@warning_ignore("integer_division")
	y_start_render = Vector2i(height * -1 / 2, height / 2);

	generate_world();
#}

func generate_world() -> void:
	noise_value_array = [];
	for x in range(x_start_render.x, x_start_render.y):
		for y in range(y_start_render.x, y_start_render.y):
			var noise_value = noise.get_noise_2d(x,y);
			noise_value_array.append(noise_value);
			if noise_value >= 0.0: # place land
				layer_ground.set_cell( Vector2i(x,y), source_id, land_atlas_coord);
				if noise_value > 0.1:
					layer_grass.set_cell( Vector2i(x,y), source_id, grass_atlas_coord);
				if noise_value > 0.2:
					layer_trees.set_cell( Vector2i(x,y), source_id, trees_atlas_coord);
			elif noise_value < 0.0:  # place water
				layer_water.set_cell( Vector2i(x,y), source_id, water_atlas_coord);
#}
