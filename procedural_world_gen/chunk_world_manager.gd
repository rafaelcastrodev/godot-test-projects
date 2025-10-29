"""
CHUNK WORLD MANAGER
"""
extends Node

@export var player: Node2D;

const WORLD_CHUNK_SCENE := preload("res://world_chunk.tscn");
const CHUNK_SIZE_TILES: int = 32;
const CHUNK_LOAD_RADIUS: int = 2;
const TILE_SIZE_PIXELS: int = 16;

const GRASS_PLACEMENT_DENSITY: float = 0.2;
const TREES_PLACEMENT_DENSITY: float = 0.1;
const WATER_NOISE_VALUE_THRESHOLD: float = 0.0;
const GROUND_NOISE_VALUE_THRESHOLD: float = 0.0;
const TREES_NOISE_VALUE_THRESHOLD: float = 0.2;
const GRASS_NOISE_VALUE_THRESHOLD: float = 0.03;
const POI_NOISE_VALUE_THRESHOLD: float = 0.6;
const POI_PLACEMENT_DENSITY: float = 0.05;

const GRASS_ATLAS_OPTIONS: Array[Dictionary] = [
	{ "coords": Vector2i(0,0), "weight": 5},
	{ "coords": Vector2i(1,0), "weight": 3},
	{ "coords": Vector2i(2,0), "weight": 3},
	{ "coords": Vector2i(3,0), "weight": 1},
	{ "coords": Vector2i(4,0), "weight": 2},
];

const TREES_ATLAS_OPTIONS: Array[Dictionary] = [
	{ "coords": Vector2i(5,0), "weight": 0},
	{ "coords": Vector2i(6,0), "weight": 1},
	{ "coords": Vector2i(7,0), "weight": 3},
	{ "coords": Vector2i(8,0), "weight": 0.2},
];

const POI_OPTIONS: Array[Dictionary] = [
	{
		"scene": "res://poi_village.tscn",
		"coords": Vector2i.ZERO,
		"weight": 1
	},
];

var chunks_in_generation: Dictionary = {};
var world_data: Dictionary = {};
var active_chunks: Dictionary = {};
var current_player_chunk = Vector2i.ZERO;

var noise: Noise;

var _water_changeset_chunks: Dictionary = {};

@onready var water_layer: TileMapLayer = $LayerWater;

func _ready() -> void:

	randomize();

	noise = FastNoiseLite.new();
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH;
	noise.seed = randi();

	water_layer.z_index = -2;

	current_player_chunk = get_chunk_coords_from_world(player.global_position);

	update_chunks();
#}


func _process(_delta: float) -> void:

	var new_player_chunk = get_chunk_coords_from_world(player.global_position);

	if new_player_chunk != current_player_chunk:
		current_player_chunk = new_player_chunk;
		update_chunks();

	_paint_water_tiles();
#}



func update_chunks():

	var desired_chunks = {};
	var chunk_range = _get_current_chunk_range();

	for x in range(chunk_range.horizontal.x, chunk_range.horizontal.y):
		for y in range(chunk_range.vertical.x, chunk_range.vertical.y):

			var chunk_coord = Vector2i(x, y);
			desired_chunks[chunk_coord] = true;

			if not active_chunks.has(chunk_coord) and not chunks_in_generation.has(chunk_coord):
				load_chunk(chunk_coord);

		#} endfor y
	#} endfor x

	var chunks_to_unload = [];
	for chunk_coord in active_chunks.keys():
		if not desired_chunks.has(chunk_coord):
			chunks_to_unload.append(chunk_coord);


	for chunk_coord in chunks_to_unload:
		unload_chunk(chunk_coord);
#}


func load_chunk(chunk_coord: Vector2i):

	if world_data.has(chunk_coord):
		_instantiate_chunk(chunk_coord, world_data[chunk_coord]);
	else:
		var thread = Thread.new();
		chunks_in_generation[chunk_coord] = thread;
		thread.start(_generate_data_thread.bind(chunk_coord));
#}


func _generate_data_thread(chunk_coord: Vector2i):

	var chunk_data = generate_chunk_data(chunk_coord);
	_on_data_generated.call_deferred(chunk_coord, chunk_data);
#}


func _on_data_generated(chunk_coord: Vector2i, chunk_data: Dictionary):

	world_data[chunk_coord] = chunk_data;

	if chunks_in_generation.has(chunk_coord):
		var finished_thread: Thread = chunks_in_generation[chunk_coord];
		finished_thread.wait_to_finish();
		chunks_in_generation.erase(chunk_coord);

	var desired_chunks = {};
	var chunk_range = _get_current_chunk_range();

	for x in range(chunk_range.horizontal.x, chunk_range.horizontal.y):
		for y in range(chunk_range.vertical.x, chunk_range.vertical.y):
			desired_chunks[Vector2i(x, y)] = true;

	if not desired_chunks.has(chunk_coord):
		return;

	_instantiate_chunk(chunk_coord, chunk_data);
#}


func _instantiate_chunk(chunk_coord: Vector2i, chunk_data: Dictionary):

	var new_chunk_node: WorldChunk = WORLD_CHUNK_SCENE.instantiate();
	new_chunk_node.name = "Chunk_%s_%s" % [chunk_coord.x, chunk_coord.y];
	add_child(new_chunk_node);
	new_chunk_node.initialize(chunk_data);
	new_chunk_node.position = get_world_pos_from_chunk_coords(chunk_coord);
	active_chunks[chunk_coord] = new_chunk_node;

	if chunk_data.water_tiles:
		_prepare_water_tiles(chunk_coord, chunk_data.water_tiles);
	#}
#}


func _prepare_water_tiles(chunk_coord: Vector2i, water_tiles: Dictionary) -> void:

	var key = "%s_%s" % [chunk_coord.x, chunk_coord.y];
	_water_changeset_chunks[key] = BetterTerrain.create_terrain_changeset(water_layer, water_tiles);
#}


func _paint_water_tiles() -> void:

	var applied_keys = [];
	var neighbor_update_list: Array[Vector2i] = [];

	for key in _water_changeset_chunks:
		var changeset: Dictionary = _water_changeset_chunks[key];

		if changeset.is_empty():
			applied_keys.append(key);
			continue;

		if BetterTerrain.is_terrain_changeset_ready(changeset):
			BetterTerrain.apply_terrain_changeset(changeset);
			applied_keys.append(key);

			var parts: PackedStringArray;
			var coord_str: String = "";

			if key.begins_with("unload_"):
				coord_str = key.trim_prefix("unload_");
			else:
				coord_str = key;

			parts = coord_str.split("_");

			if parts.size() == 2:
				var coord = Vector2i(int(parts[0]), int(parts[1]));
				neighbor_update_list.append(coord);
		#} endif is_terrain_ready

	## --- Erase all applied keys ---
	for key in applied_keys:
		_water_changeset_chunks.erase(key);

	## --- NEW: Process neighbor updates *after* applying changes ---
	var unique_neighbors_to_update: Dictionary = {}
	for chunk_coord in neighbor_update_list:
		var neighbors: Array[Vector2i] = [
			chunk_coord + Vector2i.LEFT,
			chunk_coord + Vector2i.RIGHT,
			chunk_coord + Vector2i.UP,
			chunk_coord + Vector2i.DOWN
		];

		for n_coord in neighbors:
			if active_chunks.has(n_coord): # Only update active neighbors
				unique_neighbors_to_update[n_coord] = true; # Use dictionary to avoid duplicates

	# Now, re-queue changesets for all unique neighbors
	for n_coord in unique_neighbors_to_update:
		if world_data.has(n_coord) and world_data[n_coord].water_tiles:
			_prepare_water_tiles(n_coord, world_data[n_coord].water_tiles);
#}


func get_world_pos_from_chunk_coords(chunk_coord: Vector2i) -> Vector2:

	return chunk_coord * CHUNK_SIZE_TILES * TILE_SIZE_PIXELS;
#}


func get_chunk_coords_from_world(world_pos: Vector2) -> Vector2i:

	var tile_coord = (world_pos / TILE_SIZE_PIXELS).floor()
	var chunk_coord = (tile_coord / CHUNK_SIZE_TILES).floor()
	return chunk_coord as Vector2i
#}


func unload_chunk(chunk_coord: Vector2i):

	if active_chunks.has(chunk_coord):
		var chunk_node = active_chunks[chunk_coord];
		chunk_node.queue_free();
		active_chunks.erase(chunk_coord);

	var load_key = "%s_%s" % [chunk_coord.x, chunk_coord.y];
	if _water_changeset_chunks.has(load_key):
		_water_changeset_chunks.erase(load_key);

	if world_data.has(chunk_coord) and world_data[chunk_coord].water_tiles:
		var tiles_to_clear: Dictionary = {};

		for global_tile_coord in world_data[chunk_coord].water_tiles:
			tiles_to_clear[global_tile_coord] = -1; # -1 means "no terrain"

		# Use a unique key for the unload operation
		var unload_key = "unload_%s_%s" % [chunk_coord.x, chunk_coord.y];
		_water_changeset_chunks[unload_key] = BetterTerrain.create_terrain_changeset(water_layer, tiles_to_clear);
#}


func generate_chunk_data(chunk_coord: Vector2i) -> Dictionary:

	var data = {
		"water_tiles": {},
		"ground_tiles": [],
		"grass_tiles": {},
		"trees_tiles": {},
		"poi": []
	}
	var local_tile_coords: Vector2i = Vector2i.ZERO;
	var global_tile_x = 0;
	var global_tile_y = 0;
	var global_tile_coords: Vector2i = Vector2i.ZERO;
	var noise_value: float = 0.0;
	#var poi_noise_val = noise.get_noise_2d(chunk_coord.x, chunk_coord.y);
	var is_ground_filled: bool = false;
	var chosen_tree: Dictionary = {};
	var chosen_grass: Dictionary = {};
	var chosen_poi: Dictionary = {};

	for x in range(CHUNK_SIZE_TILES):
		for y in range(CHUNK_SIZE_TILES):

			global_tile_x = chunk_coord.x * CHUNK_SIZE_TILES + x;
			global_tile_y = chunk_coord.y * CHUNK_SIZE_TILES + y;
			global_tile_coords = Vector2i(global_tile_x, global_tile_y);
			noise_value = noise.get_noise_2d(global_tile_x,global_tile_y);
			local_tile_coords = Vector2i(x, y);

			if noise_value >= GROUND_NOISE_VALUE_THRESHOLD:
				is_ground_filled = false;

				if noise_value >= TREES_NOISE_VALUE_THRESHOLD:
					if randf() < TREES_PLACEMENT_DENSITY:
						chosen_tree = _pick_weighted_random(TREES_ATLAS_OPTIONS);

						data["trees_tiles"][local_tile_coords] = chosen_tree.coords;
						is_ground_filled = true
				#} endif treenoise

				if not is_ground_filled:
					if randf() < GRASS_PLACEMENT_DENSITY:
						chosen_grass = _pick_weighted_random(GRASS_ATLAS_OPTIONS);
						data["grass_tiles"][local_tile_coords] = chosen_grass.coords;
						is_ground_filled = true;
				#} endif grass not is_ground_filled

				if noise_value >= POI_NOISE_VALUE_THRESHOLD:
					if randf() < POI_PLACEMENT_DENSITY:
						chosen_poi = _pick_weighted_random(POI_OPTIONS);
						chosen_poi.coords = local_tile_coords * TILE_SIZE_PIXELS;
						data["poi"].append(chosen_poi);

				if not is_ground_filled:
					## Still without proper use, but registering where is ground.
					data["ground_tiles"].append(local_tile_coords);
				#} endif not is_ground_filled

			else:
				## Uses "0" for BetterTerrain type, since the "key" (global_tile_coords) is the X-Y coordinates
				data["water_tiles"][global_tile_coords] = 0;
			#} endif ground_noise_value

		#} endfor y
	#} endfor x

	return data;
#}

## Uses the "weight" attribute in the array element to pick accordingly
func _pick_weighted_random(array: Array[Dictionary]) -> Dictionary:

	randomize();
	var total_weight: float = 0.0;
	for item in array:
		total_weight += item.weight;

	var random_pick: float = randf() * total_weight;

	for item in array:
		random_pick -= item.weight;
		if random_pick <= 0.0:
			return item.duplicate();

	return array.back();
#}


func _get_current_chunk_range() -> Dictionary:

	var x_coords: Vector2i = Vector2i(current_player_chunk.x - CHUNK_LOAD_RADIUS, current_player_chunk.x + CHUNK_LOAD_RADIUS + 1);
	var y_coords: Vector2i = Vector2i(current_player_chunk.y - CHUNK_LOAD_RADIUS, current_player_chunk.y + CHUNK_LOAD_RADIUS + 1);

	return {
		"horizontal": x_coords,
		"vertical": y_coords
	};
#}


""" ============== DEBUG FEATURES ============== """
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
