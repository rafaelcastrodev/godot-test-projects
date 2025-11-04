##
##	WORLD CHUNK MANAGER
##
##	Manages the procedural generation, loading, and unloading of world chunks
##	based on the player's position. It uses threading for generation
##	and a BetterTerrain helper for painting water autotiles.

class_name WorldChunkManager
extends Node


##	Exported Variables
@export var player: Node2D; # The player node. Used to determine which chunks to load.

##	Scene References
const WORLD_CHUNK_SCENE: PackedScene = preload("res://systems/world_chunk.tscn");

##	World Generation Parameters
const CHUNK_LOAD_RADIUS: int = 1; # Load radius in chunks (e.g., 1 = 3x3 grid)
const TILE_SIZE_PIXELS: int = 16; # Pixel size of a single tile
const CHUNK_SIZE_TILES: int = 32; # Tile dimensions of a single chunk (e.g., 32 = 32x32 tiles)
const MAX_GENERATION_THREADS: int = 4; # Max concurrent chunk generation threads

##	Noise and Placement Parameters
const GRASS_PLACEMENT_DENSITY: float = 0.2; # Chance to place grass on a valid tile
const TREES_PLACEMENT_DENSITY: float = 0.08; # Chance to place a tree on a valid tile
const WATER_NOISE_VALUE_THRESHOLD: float = 0.0; # Noise values below this become water
const GROUND_NOISE_VALUE_THRESHOLD: float = 0.0; # Noise values above this become ground
const TREES_NOISE_VALUE_THRESHOLD: float = 0.2; # Ground noise values above this *can* be trees
const GRASS_NOISE_VALUE_THRESHOLD: float = 0.03; # Ground noise values above this *can* be grass
const POI_NOISE_VALUE_THRESHOLD: float = 0.03; # (Currently unused)
const MIN_POI_PER_CHUNK: int = 0; # Mínimo de POIs a tentar colocar
const MAX_POI_PER_CHUNK: int = 3; # Máximo de POIs a tentar colocar
const POI_ANTI_REPETITION_PENALTY: float = 0.1; # Multiplicador de peso após um POI ser escolhido (0.1 = 90% de redução)
const POI_MIN_DISTANCE_TILES: int = TILE_SIZE_PIXELS;

#region TILE DEFINITIONS
# Weighted options for tile variations.
# "coords" = Atlas coordinates in the TileSet
# "weight" = Relative probability of being chosen

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

# Point of Interest definitions
const POI_OPTIONS: Array[Dictionary] = [
	{
		"scene": "res://scenes/poi_village.tscn",
		"coords": Vector2i.ZERO, # This will be set during generation
		"weight": 0.5
	},
	{
		"scene": "res://scenes/poi_castle.tscn",
		"coords": Vector2i.ZERO, # This will be set during generation
		"weight": 0.1
	},
	{
		"scene": "res://scenes/poi_fortress.tscn",
		"coords": Vector2i.ZERO, # This will be set during generation
		"weight": 0.3
	},
];
#endregion

##@ Private State Variables
var _noise: Noise = null; # The main noise generator for terrain
var _world_data: Dictionary = {}; # Caches all generated chunk data. {Vector2i: Dictionary}
var _active_chunks: Dictionary = {}; # Stores currently instantiated chunk nodes. {Vector2i: WorldChunk}
var _chunks_in_generation: Dictionary = {}; # Tracks chunks being generated in threads. {Vector2i: Thread}
var _chunks_to_generate_queue: Dictionary = {};
var _current_player_chunk: Vector2i = Vector2i.ZERO; # The player's current chunk coordinate
var _water_changeset_chunks: Dictionary = {}; # Pending autotile updates for the water layer. {String: Dictionary}

@onready var water_layer: TileMapLayer = $LayerWater;


##
##	Initializes the noise, sets up layers, and performs the initial chunk load.
##
func _ready() -> void:

	# Re-randomize the seed of the random number generator
	randomize();

	# Configure the noise generator
	_noise = FastNoiseLite.new();
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH;
	#_noise.seed = randi();

	water_layer.z_index = -1; # Ensure water renders behind other layers

	# Get initial player position and load surrounding chunks
	_current_player_chunk = _get_chunk_coords_from_world(player.global_position);
	_update_chunks();
#}


##
##	Main game loop. Checks for player movement, updates chunks,
##	and applies pending water tile updates.
##
func _process(_delta: float) -> void:

	var new_player_chunk: Vector2i = _get_chunk_coords_from_world(player.global_position);

	# Check if player has moved to a new chunk
	if new_player_chunk != _current_player_chunk:
		_current_player_chunk = new_player_chunk;
		_update_chunks(); # Trigger chunk loading/unloading

	_process_generation_queue(); # Processa a fila de geração e a fila de pintura de água a cada frame
	_paint_water_tiles(); # Apply any ready water autotile changesets
#}

##
##	Converts a global world position (pixels) into chunk coordinates.
##
func _get_chunk_coords_from_world(world_pos: Vector2) -> Vector2i:

	var tile_coord: Vector2 = (world_pos / TILE_SIZE_PIXELS).floor();
	var chunk_coord: Vector2 = (tile_coord / CHUNK_SIZE_TILES).floor();
	return chunk_coord as Vector2i;
#}

##
##	The core chunk loading/unloading logic.
##
##	It determines the "desired" set of chunks around the player.
##	It loads any desired chunks that are not active.
##	It unloads any active chunks that are no longer desired.
##
func _update_chunks():

	var chunks_to_load = {};  # Set of chunks that *should* be active
	var chunks_to_unload: Array[Vector2i] = [];  # List of chunks to remove
	var chunk_range = _get_current_chunk_range();
	var chunk_coord: Vector2i = Vector2i.ZERO;

	# 1. Identify all chunks that should be loaded
	for x in range(chunk_range.horizontal.x, chunk_range.horizontal.y):
		for y in range(chunk_range.vertical.x, chunk_range.vertical.y):

			chunk_coord = Vector2i(x, y);
			chunks_to_load[chunk_coord] = true;

			# If this chunk isn't loaded and isn't already generating, load it.
			if not _active_chunks.has(chunk_coord) and not _chunks_in_generation.has(chunk_coord):
				_load_chunk(chunk_coord);
		#} endfor y
	#} endfor x

	# 2. Identify active chunks that are no longer in the load radius
	for coord in _active_chunks.keys():
		if not chunks_to_load.has(coord):
			chunks_to_unload.append(coord);

	# 3. Unload all chunks marked for removal
	for chunk in chunks_to_unload:
		_unload_chunk(chunk);
#}

##
##	Calculates the rectangular range of chunks that should be loaded
##	around the player's current chunk position.
##
func _get_current_chunk_range() -> Dictionary:

	var x_coords: Vector2i = Vector2i(_current_player_chunk.x - CHUNK_LOAD_RADIUS, _current_player_chunk.x + CHUNK_LOAD_RADIUS + 1);
	var y_coords: Vector2i = Vector2i(_current_player_chunk.y - CHUNK_LOAD_RADIUS, _current_player_chunk.y + CHUNK_LOAD_RADIUS + 1);

	return {
		"horizontal": x_coords,
		"vertical": y_coords
	};
#}

##
##	Loads a chunk at the given coordinates.
##
##	- If data is cached in `_world_data`, instantiate it directly.
##	- If not cached, start a new thread to generate the data, as long as
##	  the thread limit is not exceeded.
##
func _load_chunk(chunk_coord: Vector2i):

	#var thread: Thread = null;

	# 1. Check cache
	if _world_data.has(chunk_coord):
		_instantiate_chunk(chunk_coord, _world_data[chunk_coord]);
	else:
		# 2. Check thread limit
		#if _chunks_in_generation.size() >= MAX_GENERATION_THREADS:
			#return; # Will try again next frame in _update_chunks

		# (A função _update_chunks já verificou que não está ativo ou gerando)
		_chunks_to_generate_queue[chunk_coord] = true;

		# 3. Start generation thread
		#thread = Thread.new();
		#_chunks_in_generation[chunk_coord] = thread;
		# Start the thread, binding the chunk_coord as an argument
		#thread.start(_generate_chunk_data_thread.bind(chunk_coord));
#}

##
##	[RUNS ON A THREAD]
##	Generates chunk data by calling the main generation function
##	and defers the result back to the main thread.
##
func _generate_chunk_data_thread(chunk_coord: Vector2i):
	var thread_local_noise = FastNoiseLite.new();
	var chunk_data: Dictionary = {};
	var thread_local_noise_seed = _noise.seed;
	thread_local_noise.seed = thread_local_noise_seed;
	thread_local_noise.noise_type = _noise.noise_type;
	chunk_data = _generate_chunk_data(chunk_coord, thread_local_noise, thread_local_noise_seed);

	# Safely call the main thread function when this thread is done
	_on_chunk_data_generated.call_deferred(chunk_coord, chunk_data);
#}

##
##	[RUNS ON A THREAD]
##	The main procedural generation algorithm.
##
##	Iterates through every tile in the chunk, samples noise,
##	and decides what to place (water, ground, grass, trees).
##
func _generate_chunk_data(chunk_coord: Vector2i, noise_gen: FastNoiseLite, thread_seed: int) -> Dictionary:

	var data: Dictionary = {
		"water_tiles": {}, # {global_coord: terrain_id}
		"ground_tiles": [], # [local_coord]
		"grass_tiles": {}, # {local_coord: atlas_coord}
		"trees_tiles": {}, # {local_coord: atlas_coord}
		"poi": [] # [Dictionary]
	}
	var local_tile_coords: Vector2i = Vector2i.ZERO;
	var global_tile_x: int = 0;
	var global_tile_y: int = 0;
	var global_tile_coords: Vector2i = Vector2i.ZERO;
	var noise_value: float = 0.0;
	var is_ground_filled: bool = false; # Prevents placing grass AND trees on the same tile
	var chosen_tree: Dictionary = {};
	var chosen_grass: Dictionary = {};
	var poi_chosen_location: Vector2i;
	var rng = RandomNumberGenerator.new();
	rng.seed = hash(Vector2i(thread_seed, chunk_coord.x * 1000 + chunk_coord.y));

	# Iterate over every tile *within* this chunk
	for x in range(CHUNK_SIZE_TILES):
		for y in range(CHUNK_SIZE_TILES):

			# Calculate global tile coordinates for noise sampling
			global_tile_x = chunk_coord.x * CHUNK_SIZE_TILES + x;
			global_tile_y = chunk_coord.y * CHUNK_SIZE_TILES + y;
			global_tile_coords = Vector2i(global_tile_x, global_tile_y);
			noise_value = noise_gen.get_noise_2d(global_tile_x,global_tile_y);
			local_tile_coords = Vector2i(x, y);

			# --- Main Generation Logic ---
			if noise_value >= GROUND_NOISE_VALUE_THRESHOLD:
				is_ground_filled = false; # Reset flag for this tile

				# 1. Try to place trees
				if noise_value >= TREES_NOISE_VALUE_THRESHOLD:
					if rng.randf() < TREES_PLACEMENT_DENSITY:
						chosen_tree = _pick_weighted_random(TREES_ATLAS_OPTIONS, rng);

						data["trees_tiles"][local_tile_coords] = chosen_tree.coords;
						is_ground_filled = true
				#} endif treenoise

				# 2. If no tree, try to place grass
				if not is_ground_filled:
					if rng.randf() < GRASS_PLACEMENT_DENSITY:
						chosen_grass = _pick_weighted_random(GRASS_ATLAS_OPTIONS, rng);
						data["grass_tiles"][local_tile_coords] = chosen_grass.coords;
						is_ground_filled = true;
				#} endif grass not is_ground_filled

				# 3. If nothing else, mark as plain ground
				if not is_ground_filled:
					## Still without proper use, but registering where is ground.
					data["ground_tiles"].append(local_tile_coords);
				#} endif not is_ground_filled
			else:
				# 4. It's water
				# Uses "0" for BetterTerrain type (the default terrain).
				# The key (global_tile_coords) is what matters for autotiling.
				data["water_tiles"][global_tile_coords] = 0;
			#} endif ground_noise_value

		#} endfor y
	#} endfor x

	# 1. Criar cópias mutáveis dos dados que vamos modificar
	var available_ground_tiles: Array = data["ground_tiles"].duplicate();
	var current_poi_options: Array[Dictionary] = [];
	for poi_option in POI_OPTIONS:
		current_poi_options.append(poi_option.duplicate(true)); # Cópia profunda

	# 2. Determinar quantos POIs tentar colocar neste chunk
	var poi_count_to_place = rng.randi_range(MIN_POI_PER_CHUNK, MAX_POI_PER_CHUNK);

	for i in range(poi_count_to_place):

		# 3. Parar se não houver mais locais ou POIs válidos
		var total_weight = _get_total_poi_weight(current_poi_options);
		if available_ground_tiles.is_empty() or total_weight <= 0.0:
			break; # Não há mais locais ou POIs para escolher

		# 4. Escolher um tipo de POI (com base no peso atual)
		var chosen_poi_copy: Dictionary = _pick_weighted_random(current_poi_options, rng);

		# 5. Escolher um local
		var location_index: int = rng.randi_range(0, available_ground_tiles.size() - 1);
		poi_chosen_location = available_ground_tiles[location_index];
		#available_ground_tiles.remove_at(location_index); # Garante que este tile não seja usado novamente

		# 6. Salvar o POI
		# If you want to centralize the POI add (Vector2i.ONE * TILE_SIZE_PIXELS / 2) to position.
		var pixel_position = (poi_chosen_location * TILE_SIZE_PIXELS);
		print(pixel_position)
		chosen_poi_copy.coords = pixel_position;
		data["poi"].append(chosen_poi_copy);

		# 7. Aplicar a penalidade de repetição (Modifica a lista 'current_poi_options')
		# Encontra o POI na lista (pelo "scene", que age como ID) e reduz seu peso
		for poi_option in current_poi_options:
			if poi_option.scene == chosen_poi_copy.scene:
				poi_option.weight = poi_option.weight * POI_ANTI_REPETITION_PENALTY;
				break; # Para o loop interno

		# 8. [NOVA LÓGICA] Remover a "zona de exclusão" de tiles disponíveis
		# Iteramos de trás para frente para remover itens com segurança
		var idx = available_ground_tiles.size() - 1
		while idx >= 0:
			var tile_coord: Vector2i = available_ground_tiles[idx]

			# Se o tile estiver dentro da distância mínima, remova-o
			if tile_coord.distance_to(poi_chosen_location) < float(POI_MIN_DISTANCE_TILES):
				available_ground_tiles.remove_at(idx)

			idx -= 1
		#} endwhile
	#} endfor
	#}

	return data;
#}


##
##	[MAIN THREAD CALLBACK]
##	Receives generated data from a finished thread.
##
##	It caches the data and, if the chunk is still
##	within the player's load radius, instantiates it.
##
func _on_chunk_data_generated(chunk_coord: Vector2i, chunk_data: Dictionary):

	var finished_thread: Thread = null;
	var chunks_to_load: Dictionary = {};
	var chunk_range: Dictionary = _get_current_chunk_range();

	# 1. Cache the data
	_world_data[chunk_coord] = chunk_data;

	# 2. Clean up the finished thread
	if _chunks_in_generation.has(chunk_coord):
		finished_thread = _chunks_in_generation[chunk_coord];
		finished_thread.wait_to_finish();
		_chunks_in_generation.erase(chunk_coord);

	# 3. Check if the player has moved away while this was generating
	for x in range(chunk_range.horizontal.x, chunk_range.horizontal.y):
		for y in range(chunk_range.vertical.x, chunk_range.vertical.y):
			chunks_to_load[Vector2i(x, y)] = true;

	# If player moved away, do nothing. The data is cached for later.
	if not chunks_to_load.has(chunk_coord):
		return;

	# 4. Player is still nearby, instantiate the chunk
	_instantiate_chunk(chunk_coord, chunk_data);
#}


##
##	Triggers a water tile update for chunks adjacent to the given coordinate.
##
##	This is crucial for fixing autotile seams when a new chunk
##	is loaded or an old one is unloaded.
##
func _update_water_neighbors(chunk_coord: Vector2i) -> void:
	var neighbors_chunks: Array[Vector2i] = [
		chunk_coord + Vector2i.LEFT,
		chunk_coord + Vector2i.RIGHT,
		chunk_coord + Vector2i.UP,
		chunk_coord + Vector2i.DOWN
	];

	for n_coord in neighbors_chunks:
		# Only update neighbors that are currently active
		if _active_chunks.has(n_coord):
			if _world_data.has(n_coord):
				# Re-prepare the neighbor's water tiles
				_prepare_water_tiles(n_coord, _world_data[n_coord].water_tiles);
#}

##
##	Instantiates a WorldChunk scene, initializes it with data,
##	and adds it to the scene tree and `_active_chunks`.
##
func _instantiate_chunk(chunk_coord: Vector2i, chunk_data: Dictionary):

	var new_chunk_node: WorldChunk;
	# A key used to cancel a pending "unload" operation if we load and unload quickly
	var chunk_to_unload_key = "unload_%s_%s" % [chunk_coord.x, chunk_coord.y];

	if _water_changeset_chunks.has(chunk_to_unload_key):
		_water_changeset_chunks.erase(chunk_to_unload_key);

	# Instantiate the chunk scene
	new_chunk_node = WORLD_CHUNK_SCENE.instantiate();
	new_chunk_node.name = "Chunk_%s_%s" % [chunk_coord.x, chunk_coord.y];
	add_child(new_chunk_node);

	# The WorldChunk script should have an `initialize` function
	new_chunk_node.initialize(chunk_data);
	new_chunk_node.position = _get_world_pos_from_chunk_coords(chunk_coord);
	_active_chunks[chunk_coord] = new_chunk_node; # Add to active list

	# If this chunk has water, prepare its tiles and update neighbors
	if chunk_data.water_tiles:
		_prepare_water_tiles(chunk_coord, chunk_data.water_tiles);
		_update_water_neighbors(chunk_coord);
	#}
#}


##
##	[NOVA FUNÇÃO]
##	Checks the generation queue and starts new threads
##	if there are free slots.
##
func _process_generation_queue() -> void:

	# Continua pegando itens da fila enquanto houver slots de thread livres
	# E enquanto a fila não estiver vazia
	while _chunks_in_generation.size() < MAX_GENERATION_THREADS and not _chunks_to_generate_queue.is_empty():

		# Pega o próximo chunk da fila
		var chunk_coord: Vector2i = _chunks_to_generate_queue.keys().front();
		_chunks_to_generate_queue.erase(chunk_coord); # Remove da fila

		# Verificação de segurança:
		# O chunk já foi gerado enquanto estava na fila? (muito raro)
		# O chunk ainda está na área de carregamento? (o jogador pode ter se movido rápido)

		if _world_data.has(chunk_coord) or _chunks_in_generation.has(chunk_coord):
			continue; # Já foi ou está sendo processado, pule.

		# Verifica se o jogador se moveu para longe enquanto o chunk estava na fila
		var chunk_range = _get_current_chunk_range();
		var is_in_range = (
			chunk_coord.x >= chunk_range.horizontal.x and
			chunk_coord.x < chunk_range.horizontal.y and
			chunk_coord.y >= chunk_range.vertical.x and
			chunk_coord.y < chunk_range.vertical.y
		);

		if not is_in_range:
			continue; # O jogador se moveu, não precisamos mais gerar este chunk.

		# --- Se passou em tudo, inicie a thread ---
		var thread: Thread = Thread.new();
		_chunks_in_generation[chunk_coord] = thread;
		thread.start(_generate_chunk_data_thread.bind(chunk_coord));
	#}
#}


##
##	Creates a 'changeset' for the BetterTerrain autotiler
##	using the chunk's water data and queues it for painting.
##
func _prepare_water_tiles(chunk_coord: Vector2i, water_tiles: Dictionary) -> void:

	var coords = "%s_%s" % [chunk_coord.x, chunk_coord.y];
	# This changeset will be processed by _paint_water_tiles()
	_water_changeset_chunks[coords] = BetterTerrain.create_terrain_changeset(water_layer, water_tiles);
#}


##
##	Called every frame in `_process`.
##
##	It checks all pending water changesets. If a changeset is
##	ready (calculated by BetterTerrain), it applies it to the TileMap.
##
func _paint_water_tiles() -> void:

	var applied_keys = [];
	var changeset: Dictionary = {};

	for key in _water_changeset_chunks:
		changeset = _water_changeset_chunks[key];

		# Skip if changeset is empty
		if changeset.is_empty():
			applied_keys.append(key);
			continue;

		# Ask BetterTerrain if this changeset is ready to be applied
		if BetterTerrain.is_terrain_changeset_ready(changeset):
			BetterTerrain.apply_terrain_changeset(changeset);
			applied_keys.append(key); # Mark for removal
		#} endif is_terrain_ready

	# Clean up applied changesets from the queue
	for key in applied_keys:
		_water_changeset_chunks.erase(key);
#}


##
##	Converts chunk coordinates back into a global world position (pixels)
##	for placing the chunk node.
##
func _get_world_pos_from_chunk_coords(chunk_coord: Vector2i) -> Vector2:

	return chunk_coord * CHUNK_SIZE_TILES * TILE_SIZE_PIXELS;
#}

##
##	Removes a chunk node from the scene, removes it from `_active_chunks`,
##	and queues a changeset to erase its water tiles from the TileMap.
##
func _unload_chunk(chunk_coord: Vector2i):

	var chunk_node: WorldChunk = null;
	var chunk_to_load_key: String = "%s_%s" % [chunk_coord.x, chunk_coord.y];
	var chunk_to_unload_key = "unload_%s_%s" % [chunk_coord.x, chunk_coord.y];
	var tiles_to_clear: Dictionary = {};

	# 1. Remove the node from the scene
	if _active_chunks.has(chunk_coord):
		chunk_node = _active_chunks[chunk_coord];
		chunk_node.queue_free();
		_active_chunks.erase(chunk_coord);

	# 2. Cancel any pending "load" changeset for this chunk
	chunk_to_load_key = "%s_%s" % [chunk_coord.x, chunk_coord.y];

	if _water_changeset_chunks.has(chunk_to_load_key):
		_water_changeset_chunks.erase(chunk_to_load_key);

	# 3. If the chunk had water, create a changeset to *remove* it
	if _world_data.has(chunk_coord) and _world_data[chunk_coord].water_tiles:
		tiles_to_clear = {};

		# Create a dictionary of tiles to set to "no terrain" (-1)
		for global_tile_coord in _world_data[chunk_coord].water_tiles:
			tiles_to_clear[global_tile_coord] = -1; # -1 means "no terrain"

		# Use a unique key for the unload operation
		chunk_to_unload_key = "unload_%s_%s" % [chunk_coord.x, chunk_coord.y];
		_water_changeset_chunks[chunk_to_unload_key] = BetterTerrain.create_terrain_changeset(water_layer, tiles_to_clear);

		# 4. Update neighbors to fix seams
		_update_water_neighbors(chunk_coord);
#}


##
##	Utility function.
##	Selects a random item from an array of dictionaries
##	based on their "weight" key.
##
func _pick_weighted_random(array: Array[Dictionary], rng: RandomNumberGenerator) -> Dictionary:

	var total_weight: float = 0.0;
	var random_pick: float = 0.0;

	# Sum total weight
	for item in array:
		total_weight += item.weight;

	# Pick a random value within the total weight
	random_pick = rng.randf() * total_weight;

	# Find the item corresponding to the random value
	for item in array:
		random_pick -= item.weight;
		if random_pick <= 0.0:
			# Return a duplicate to prevent modifying the original constant
			return item.duplicate();

	return array.back(); # Fallback
#}


##
##	Utility function.
##	Calculates the sum of "weight" from an array of POI dictionaries.
##
func _get_total_poi_weight(poi_array: Array[Dictionary]) -> float:
	var total: float = 0.0;
	for item in poi_array:
		total += item.weight;
	return total;
#}


""" ============== JUST FOR DEBUG PURPOSES ============== """
#region

@onready var camera_2d: Camera2D = $"../____DEGUB_PURPOSES____/CharacterBody2D/Camera2D"

func _input(_event: InputEvent) -> void:
	var zoom_val: float = 0.0;

	if Input.is_action_just_pressed("zoom_in"):
		zoom_val = camera_2d.zoom.x + 0.1;
		camera_2d.zoom = Vector2(zoom_val, zoom_val)
	if Input.is_action_just_pressed("zoom_out"):
		zoom_val = camera_2d.zoom.x - 0.1;
		camera_2d.zoom = Vector2(zoom_val, zoom_val)
#}

#endregion
