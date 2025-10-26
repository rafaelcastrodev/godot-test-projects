"""
CHUNK WORLD MANAGER
"""
extends Node

@export var player: Node2D;
@export var noise_texture: NoiseTexture2D;
@export var tile_set: TileSet;

const WORLD_CHUNK_SCENE := preload("res://world_chunk.tscn");
const CHUNK_SIZE_TILES: int = 32;
## How many chunks to load around the player.
## 1 = a 3x3 grid (9 chunks total)
## 2 = a 5x5 grid (25 chunks total)
const CHUNK_LOAD_RADIUS: int = 1;
const TILE_PIXELS: int = 16;

# The player's current chunk coordinate. We check this every frame.
var current_player_chunk = Vector2i.ZERO;
var noise: Noise;
var vegetation_noise: Noise;
var noise_seed: int = 0;
var noise_value_array: Array[float] = [];
var width: int = 100;
var height: int = 100;
var x_start_render: Vector2i = Vector2i.ZERO;
var y_start_render: Vector2i = Vector2i.ZERO;

var water_noise_value_threshold: float = 0.0;
var ground_noise_value_threshold: float = 0.0;
var trees_noise_value_threshold: float = 0.2;
var grass_noise_value_threshold: float = 0.03;
var grass_placement_density: float = 0.2; # % chance to place grass
var trees_placement_density: float = 0.1; # % chance to place trees

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
	{ "coords": Vector2i(6,0), "weight": 0},
	{ "coords": Vector2i(7,0), "weight": 1},
	{ "coords": Vector2i(8,0), "weight": 3},
	{ "coords": Vector2i(9,0), "weight": 0.2},
];

var poi_options: Array[Dictionary] = [
	{ "path": "res://poi_village.tscn", "weight": 1},
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
@onready var poi_layer: Node2D = $"../Overworld/LayerPOI";

## ----- World State -----
# The main dictionary that holds all generated chunk data.
# This provides persistence.
# Format: { Vector2i(chunk_coord): {"terrain": {...}, "poi": "res://path"} }
var world_data: Dictionary = {};
# A dictionary of *currently active* (instanced) chunk nodes.
# We use this to know which nodes to unload.
# Format: { Vector2i(chunk_coord): Node(TileMap) }
var active_chunks = {}

func _ready() -> void:

	randomize();

	# Initialize the noise generator
	#noise = FastNoiseLite.new()
	#noise.seed = randi() # Use a random seed
	#noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise_seed = randi();
	noise = noise_texture.noise;
	noise.seed = noise_seed;

	# Get the player's starting chunk and load the initial chunks
	current_player_chunk = get_chunk_coords_from_world(player.global_position);
	update_chunks();

	#@warning_ignore("integer_division")
	#x_start_render = Vector2i(width * -1 / 2, width / 2);
	#@warning_ignore("integer_division")
	#y_start_render = Vector2i(height * -1 / 2, height / 2);

	water_layer.z_index = -1;
	ground_layer.z_index = -1;
	grass_layer.z_index = -1;
#}


func _process(_delta: float) -> void:
	# Check if the player has moved to a new chunk
	var new_player_chunk = get_chunk_coords_from_world(player.global_position);

	if new_player_chunk != current_player_chunk:
		current_player_chunk = new_player_chunk
		# If they moved, update the loaded chunks
		update_chunks();
#}


# --- Main Chunk Logic ---

## This function is the core. It loads new chunks and unloads old ones.
func update_chunks():
	# 1. Create a set (as a dictionary) of all chunks that *should* be active
	var desired_chunks = {}
	for x in range(current_player_chunk.x - CHUNK_LOAD_RADIUS, current_player_chunk.x + CHUNK_LOAD_RADIUS + 1):
		for y in range(current_player_chunk.y - CHUNK_LOAD_RADIUS, current_player_chunk.y + CHUNK_LOAD_RADIUS + 1):
			var chunk_coord = Vector2i(x, y)
			desired_chunks[chunk_coord] = true

			# If this desired chunk isn't already active, load it
			if not active_chunks.has(chunk_coord):
				load_chunk(chunk_coord)

	# 2. Find all chunks that are active but no longer desired
	var chunks_to_unload = []
	for chunk_coord in active_chunks.keys():
		if not desired_chunks.has(chunk_coord):
			chunks_to_unload.append(chunk_coord)

	# 3. Unload them
	for chunk_coord in chunks_to_unload:
		unload_chunk(chunk_coord);
#}

## Loads a chunk: checks for saved data, generates if needed, and builds the node.
func load_chunk(chunk_coord: Vector2i):
	var chunk_data: Dictionary;

	# 1. Check if this chunk has been generated and saved before
	if world_data.has(chunk_coord):
		# Yes: Load the saved data
		chunk_data = world_data[chunk_coord];
	else:
		# No: Generate new data and save it
		chunk_data = generate_chunk_data(chunk_coord);
		world_data[chunk_coord] = chunk_data;

	# 2. Build the chunk node from the data
	#var new_chunk_node = TileMapLayer.new();
	var new_chunk_node: WorldChunk = WORLD_CHUNK_SCENE.instantiate();
	new_chunk_node.name = "Chunk_%s_%s" % [chunk_coord.x, chunk_coord.y];
	add_child(new_chunk_node);
	new_chunk_node.initialize(chunk_data)
	#new_chunk_node.tile_set = tile_set

	# Set the chunk's position in the world
	new_chunk_node.position = get_world_pos_from_chunk_coords(chunk_coord);
	return;
	# 3. Set all the tiles based on the "terrain" data
	var terrain_data = chunk_data["terrain"]
	for local_tile_coord in terrain_data:
		var atlas_coord = terrain_data[local_tile_coord]

		## Set the cell: Layer 0, Source 0 (your first tileset)
		new_chunk_node.set_cell(local_tile_coord, 0, atlas_coord)

	# 4. Handle POIs (Points of Interest)
	if chunk_data.has("poi") and chunk_data["poi"] != "":
		var poi_path = chunk_data["poi"]

		# Load the POI scene and instance it
		var poi_scene = load(poi_path)
		var poi_instance = poi_scene.instantiate()

		# Add the POI as a child of the chunk
		# This ensures it unloads with the chunk
		new_chunk_node.add_child(poi_instance)

		# Position the POI within the chunk
		# (Here, we assume it's at the center of the chunk)
		var center_pos = Vector2(CHUNK_SIZE_TILES, CHUNK_SIZE_TILES) * TILE_PIXELS / 2.0
		poi_instance.position = center_pos

	# 5. Add the chunk to the scene and our active list
	active_chunks[chunk_coord] = new_chunk_node
#}


## Gets the top-left pixel position for a chunk coordinate.
## We use this to set the TileMap's position.
func get_world_pos_from_chunk_coords(chunk_coord: Vector2i) -> Vector2:
	return chunk_coord * CHUNK_SIZE_TILES * TILE_PIXELS;
#}


## Converts a global pixel position (like player.global_position)
## into a chunk coordinate.
func get_chunk_coords_from_world(world_pos: Vector2) -> Vector2i:
	# Convert pixel position to tile coordinate
	var tile_coord = (world_pos / TILE_PIXELS).floor()
	# Convert tile coordinate to chunk coordinate
	var chunk_coord = (tile_coord / CHUNK_SIZE_TILES).floor()
	return chunk_coord as Vector2i
#}


## Frees the chunk node and removes it from the active list.
func unload_chunk(chunk_coord: Vector2i):
	if active_chunks.has(chunk_coord):
		var chunk_node = active_chunks[chunk_coord];
		# Free the node
		chunk_node.queue_free();
		# Remove from the active list
		active_chunks.erase(chunk_coord);
#}


func generate_chunk_data(chunk_coord: Vector2i) -> Dictionary:
	var data = {
		"water_tiles": [],  ## An array for water autotiling
		"ground_tiles": [], ## An array for ground tiles
		"grass_tiles": {},  ## A dictionary for specific grass tiles
		"trees_tiles": {},  ## A dictionary for specific tree tiles
		"poi": ""
	}

	for x in range(CHUNK_SIZE_TILES):
		for y in range(CHUNK_SIZE_TILES):

			## Get the *global* tile coordinate
			var global_tile_x = chunk_coord.x * CHUNK_SIZE_TILES + x;
			var global_tile_y = chunk_coord.y * CHUNK_SIZE_TILES + y;
			var noise_value = noise.get_noise_2d(global_tile_x,global_tile_y);
			## This is the local tile position *within* the chunk
			var local_tile_coords = Vector2i(x, y);

			if noise_value >= ground_noise_value_threshold:
				var is_ground_filled = false;

				## --- Place Trees ---
				if noise_value >= trees_noise_value_threshold:
					if randf() < trees_placement_density:
						var chosen_tree: Dictionary = _pick_weighted_random(trees_atlas_coord_array);
						## Save the tree data
						data["trees_tiles"][local_tile_coords] = chosen_tree.coords;
						is_ground_filled = true
				#} endif treenoise

				## --- Place Grass (if no tree) ---
				if not is_ground_filled:
					if randf() < grass_placement_density:
						var chosen_grass: Dictionary = _pick_weighted_random(grass_atlas_coord_array);
						## Save the grass data
						data["grass_tiles"][local_tile_coords] = chosen_grass.coords;
						is_ground_filled = true;
				#} endif grass not is_ground_filled

				## --- Place Ground (if nothing else) ---
				if not is_ground_filled:
					data["ground_tiles"].append(local_tile_coords);
				#} endif not is_ground_filled

			## --- Place Water ---
			else:
				data["water_tiles"].append(local_tile_coords);

			#} endif ground_noise_value
		#} endfor y
	#} endfor x

	## --- Generate POI ---
	var poi_noise_val = noise.get_noise_2d(chunk_coord.x, chunk_coord.y)
	if poi_noise_val > 0.6:
		var chosen_poi: Dictionary = _pick_weighted_random(poi_options);
		data["poi"] = chosen_poi.path;

	## Return the dictionary full of data
	return data;
#}


func _pick_weighted_random(array: Array[Dictionary]) -> Dictionary:
	randomize();
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
