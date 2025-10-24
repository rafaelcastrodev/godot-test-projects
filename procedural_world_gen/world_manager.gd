extends Node


@export var terrain_noise_texture: NoiseTexture2D;

var terrain_noise: Noise;
var vegetation_noise: Noise;
var terrain_noise_seed: int = 2;
var terrain_noise_value_array: Array[float] = [];
var width: int = 100;
var height: int = 100;
var x_start_render: Vector2i = Vector2i.ZERO;
var y_start_render: Vector2i = Vector2i.ZERO;

var water_noise_value_threshold: float = 0.0;
var ground_noise_value_threshold: float = 0.0;
var trees_noise_value_threshold: float = 0.2;
var grass_noise_value_threshold: float = 0.05;
var grass_placement_density: float = 0.3; # 40% chance to place grass

var tile_source_id: int = 0;
var water_atlas_coord: Vector2i = Vector2i(1,2);
var ground_atlas_coord: Vector2i = Vector2i(0,0);
var grass_atlas_coord: Vector2i = Vector2i(1,0);
var trees_atlas_coord: Vector2i = Vector2i(8,0);

var water_layer_terrain_set_index: int = 0;
var water_layer_terrain_index: int = 0;

var grass_atlas_coord_array: Array[Dictionary] = [
	{ "coords": Vector2i(1,0), "weight": 5},
	{ "coords": Vector2i(2,0), "weight": 3},
	{ "coords": Vector2i(3,0), "weight": 3},
	{ "coords": Vector2i(4,0), "weight": 1},
	{ "coords": Vector2i(5,0), "weight": 2},
];

var trees_atlas_coord_array: Array[Dictionary] = [
	{ "coords": Vector2i(6,0), "weight": 1},
	{ "coords": Vector2i(7,0), "weight": 1},
	{ "coords": Vector2i(8,0), "weight": 1},
	{ "coords": Vector2i(9,0), "weight": 1},
];

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
	#terrain_noise_seed = randi();
	terrain_noise = terrain_noise_texture.noise;
	terrain_noise.seed = terrain_noise_seed;

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

	terrain_noise_value_array = [];
	var tile_coords: Vector2i = Vector2i.ZERO;

	for x in range(x_start_render.x, x_start_render.y):
		for y in range(y_start_render.x, y_start_render.y):
			var noise_value = terrain_noise.get_noise_2d(x,y);
			tile_coords.x = x;
			tile_coords.y = y;

			terrain_noise_value_array.append(noise_value);

			if noise_value >= ground_noise_value_threshold: # place land
				## Normal circunstances ground is above water, but this time I want all ground bellow
				#ground_layer.set_cell( tile_coords, tile_source_id, ground_atlas_coord);

				if noise_value >= trees_noise_value_threshold:
					trees_tiles_array.append(tile_coords);
					trees_layer.set_cell( tile_coords, tile_source_id, trees_atlas_coord);
				elif noise_value >= grass_noise_value_threshold:
					if randf() < grass_placement_density:
						var chosen_grass: Dictionary = pick_weighted_random(grass_atlas_coord_array);
						grass_tiles_array.append(tile_coords);
						grass_layer.set_cell(
							tile_coords,
							tile_source_id,
							chosen_grass.coords
						);
				else:
					ground_tiles_array.append(tile_coords);

			else:  # place water
				water_tiles_array.append(tile_coords);
			#} endif

		#} endfor y
	#} endfor x

	#print(terrain_noise_value_array.min()) # -0.6
	#print(terrain_noise_value_array.max()) # 0.6
	water_layer.set_cells_terrain_connect(
		water_tiles_array,
		water_layer_terrain_set_index,
		water_layer_terrain_index
	);
#}


func pick_weighted_random(array: Array[Dictionary]) -> Dictionary:
	var total_weight: float = 0.0;
	for item in array:
		total_weight += item.weight;

	var random_pick: float = randf() * total_weight;

	for item in array:
		random_pick -= item.weight;
		if random_pick <= 0.0:
			return item;

	# Fallback (should not happen, but good to have)
	return array.back();
#}


"""
===========================================
			DEBUG FEATURES
===========================================
"""
#region

@onready var camera_2d: Camera2D = $"../CharacterBody2D/Camera2D";

func _input(_event: InputEvent) -> void:
	if Input.is_action_just_pressed("zoom_in"):
		var zoom_val = camera_2d.zoom.x + 0.1;
		camera_2d.zoom = Vector2(zoom_val, zoom_val)
	if Input.is_action_just_pressed("zoom_out"):
		var zoom_val = camera_2d.zoom.x - 0.1;
		camera_2d.zoom = Vector2(zoom_val, zoom_val)
#}

#endregion
