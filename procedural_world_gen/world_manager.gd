extends Node


@export var noise_height_texture: NoiseTexture2D;

var noise: Noise;
var noise_seed: int = 1;
var noise_value_array: Array[float] = [];
var width: int = 180;
var height: int = 270;
var x_start_render: Vector2i = Vector2i.ZERO;
var y_start_render: Vector2i = Vector2i.ZERO;

var source_id: int = 0;
var water_atlas_coord: Vector2i = Vector2i(1,2);
var ground_atlas_coord: Vector2i = Vector2i(0,0);
var grass_atlas_coord: Vector2i = Vector2i(1,0);
var trees_atlas_coord: Vector2i = Vector2i(8,0);

var water_layer_terrain_set_index: int = 0;
var water_layer_terrain_index: int = 0;

var water_tiles_array: Array[Vector2i] = [];
var ground_tiles_array: Array[Vector2i] = [];
var grass_tiles_array: Array[Vector2i] = [];
var trees_tiles_array: Array[Vector2i] = [];

@onready var overworld: Node2D = $"../Overworld";
@onready var water_layer: TileMapLayer = $"../Overworld/LayerWater";
@onready var ground_layer: TileMapLayer = $"../Overworld/LayerGround";
@onready var grass_layer: TileMapLayer = $"../Overworld/LayerGrass";
@onready var trees_layer: TileMapLayer = $"../Overworld/LayerTrees";

func _ready() -> void:
	randomize();
	#noise_seed = randi();
	noise = noise_height_texture.noise;
	noise.seed = noise_seed;

	@warning_ignore("integer_division")
	x_start_render = Vector2i(width * -1 / 2, width / 2);
	@warning_ignore("integer_division")
	y_start_render = Vector2i(height * -1 / 2, height / 2);

	water_layer.z_index = -1;
	ground_layer.z_index = -1;
	grass_layer.z_index = -1;
	generate_world();
#}

func generate_world() -> void:

	noise_value_array = [];

	for x in range(x_start_render.x, x_start_render.y):
		for y in range(y_start_render.x, y_start_render.y):

			var noise_value = noise.get_noise_2d(x,y);
			noise_value_array.append(noise_value);

			if noise_value >= 0.0: # place land
				## Normal circunstances ground is above water, but this time I want all ground bellow
				#ground_tiles_array.append(Vector2i(x,y));
				#ground_layer.set_cell( Vector2i(x,y), source_id, ground_atlas_coord);

				if noise_value > 0.1:
					grass_tiles_array.append(Vector2i(x,y));
					grass_layer.set_cell( Vector2i(x,y), source_id, grass_atlas_coord);

				if noise_value > 0.2:
					trees_tiles_array.append(Vector2i(x,y));
					trees_layer.set_cell( Vector2i(x,y), source_id, trees_atlas_coord);
			elif noise_value < 0.0:  # place water
				water_tiles_array.append(Vector2i(x,y));
			#} endif

		#} endfor y
	#} endfor x

	water_layer.set_cells_terrain_connect(water_tiles_array, water_layer_terrain_set_index, water_layer_terrain_index);
#}
