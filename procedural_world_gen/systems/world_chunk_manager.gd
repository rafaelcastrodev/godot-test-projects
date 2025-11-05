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

#region WORLD & SYSTEM PARAMETERS
const CHUNK_LOAD_RADIUS: int = 1; # Load radius in chunks (e.g., 1 = 3x3 grid)
const TILE_SIZE_PIXELS: int = 16; # Pixel size of a single tile
const CHUNK_SIZE_TILES: int = 32; # Tile dimensions of a single chunk (e.g., 32x32 tiles)
const MAX_GENERATION_THREADS: int = 4; # Max concurrent chunk generation threads
#endregion

#region GENERATION PARAMETERS
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
const POI_MIN_DISTANCE_TILES: int = 16;
const MAX_POI_PLACEMENT_ATTEMPTS: int = 50;
#endregion

#region TILE & POI DEFINITIONS
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
	{ "scene": preload("res://scenes/poi_village.tscn"), "coords": Vector2i.ZERO, "weight": 0.5 },
	{ "scene": preload("res://scenes/poi_castle.tscn"), "coords": Vector2i.ZERO, "weight": 0.1 },
	{ "scene": preload("res://scenes/poi_fortress.tscn"), "coords": Vector2i.ZERO, "weight": 0.3 },
];
#endregion

#region PRIVATE VARIABLES
var _noise: Noise = null; # The main noise generator for terrain
var _world_data: Dictionary = {}; # Caches all generated chunk data. {Vector2i: Dictionary}
var _active_chunks: Dictionary = {}; # Stores currently instantiated chunk nodes. {Vector2i: WorldChunk}
var _chunks_in_generation: Dictionary = {}; # Tracks chunks being generated in threads. {Vector2i: Thread}
var _chunks_to_generate_queue: Array[Vector2i] = [];
var _current_player_chunk: Vector2i = Vector2i.ZERO; # The player's current chunk coordinate
var _water_changeset_chunks: Dictionary = {}; # Pending autotile updates for the water layer. {String: Dictionary}
var _needs_water_refresh_hack: bool = false;
#endregion

@onready var water_layer: TileMapLayer = $LayerWater;


#region NODE LIFECYCLE
##
##	Initializes the noise, sets up layers, and performs the initial chunk load.
##
func _ready() -> void:
	randomize();

	_noise = FastNoiseLite.new();
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH;
	_noise.seed = randi();

	water_layer.z_index = -1;

	_current_player_chunk = _get_chunk_coords_from_world(player.global_position);
	_update_chunks();
#}


##
##	Main game loop. Checks for player movement, updates chunks,
##	and applies pending water tile updates.
##
func _process(_delta: float) -> void:

	var new_player_chunk: Vector2i = _get_chunk_coords_from_world(player.global_position);

	if new_player_chunk != _current_player_chunk:
		_current_player_chunk = new_player_chunk;
		_update_chunks();

	# --- INÍCIO DA GAMBIARRA ---
	# Verifica se a gambiarra está armada E se todas as filas estão ociosas
	if _needs_water_refresh_hack:

		var is_generation_idle = _chunks_to_generate_queue.is_empty() and _chunks_in_generation.is_empty();
		var is_water_idle = _water_changeset_chunks.is_empty();

		# Se a geração e a primeira onda de água terminaram
		if is_generation_idle and is_water_idle:

			# 1. Desarma a gambiarra (para não rodar 60x por segundo)
			_needs_water_refresh_hack = false;

			# 2. Executa a atualização forçada
			_force_refresh_all_active_water();
	# --- FIM DA GAMBIARRA ---

	_process_generation_queue();
	_paint_water_tiles();
#}
#endregion


#region WORLD MANAGEMENT
##
##	The core chunk loading/unloading logic.
##
func _update_chunks():

	var chunks_to_load = {};
	var chunks_to_unload: Array[Vector2i] = [];
	var chunk_range = _get_current_chunk_range();
	var chunk_coord: Vector2i = Vector2i.ZERO;

	# 1. Identify all chunks that should be loaded
	for x in range(chunk_range.horizontal.x, chunk_range.horizontal.y):
		for y in range(chunk_range.vertical.x, chunk_range.vertical.y):
			chunk_coord = Vector2i(x, y);
			chunks_to_load[chunk_coord] = true;

			if not _active_chunks.has(chunk_coord) and not _chunks_in_generation.has(chunk_coord):
				_load_chunk(chunk_coord);

	# 2. Identify active chunks that are no longer in the load radius
	for coord in _active_chunks.keys():
		if not chunks_to_load.has(coord):
			chunks_to_unload.append(coord);

	# 3. Unload all chunks marked for removal
	for chunk in chunks_to_unload:
		_unload_chunk(chunk);
#}

##
##	Calculates the rectangular range of chunks that should be loaded.
##
func _get_current_chunk_range() -> Dictionary:

	var x_coords: Vector2i = Vector2i(_current_player_chunk.x - CHUNK_LOAD_RADIUS, _current_player_chunk.x + CHUNK_LOAD_RADIUS + 1);
	var y_coords: Vector2i = Vector2i(_current_player_chunk.y - CHUNK_LOAD_RADIUS, _current_player_chunk.y + CHUNK_LOAD_RADIUS + 1);

	return { "horizontal": x_coords, "vertical": y_coords };
#}

##
##	Converts a global world position (pixels) into chunk coordinates.
##
func _get_chunk_coords_from_world(world_pos: Vector2) -> Vector2i:

	var tile_coord: Vector2 = (world_pos / TILE_SIZE_PIXELS).floor();
	var chunk_coord: Vector2 = (tile_coord / CHUNK_SIZE_TILES).floor();
	return chunk_coord as Vector2i;
#}
#endregion


#region GENERATION QUEUE & THREADING
##
##	Loads a chunk, either from cache or by starting a generation task.
##
func _load_chunk(chunk_coord: Vector2i):
	if _world_data.has(chunk_coord):
		_instantiate_chunk(chunk_coord, _world_data[chunk_coord]);
	else:
		if not _chunks_to_generate_queue.has(chunk_coord):
			_chunks_to_generate_queue.append(chunk_coord);
#}

##
##	Checks the queue and starts new generation threads if slots are free.
##
func _process_generation_queue() -> void:

	if not _chunks_to_generate_queue.is_empty() and _chunks_in_generation.size() < MAX_GENERATION_THREADS:
		_chunks_to_generate_queue.sort_custom(_sort_chunks_by_distance);

	while _chunks_in_generation.size() < MAX_GENERATION_THREADS and not _chunks_to_generate_queue.is_empty():

		var chunk_coord: Vector2i = _chunks_to_generate_queue.pop_front();

		if _world_data.has(chunk_coord) or _chunks_in_generation.has(chunk_coord):
			continue;

		var chunk_range = _get_current_chunk_range();
		var is_in_range = (
			chunk_coord.x >= chunk_range.horizontal.x and
			chunk_coord.x < chunk_range.horizontal.y and
			chunk_coord.y >= chunk_range.vertical.x and
			chunk_coord.y < chunk_range.vertical.y
		);

		if not is_in_range:
			continue;

		var thread: Thread = Thread.new();
		_chunks_in_generation[chunk_coord] = thread;
		thread.start(_generate_chunk_data_thread.bind(chunk_coord, _noise.seed, _noise.noise_type));
	#}
#}

##
##	[RUNS ON A THREAD]
##	Entry point for the thread. Calls the main generation function.
##
func _generate_chunk_data_thread(chunk_coord: Vector2i, noise_seed: int, noise_type: FastNoiseLite.NoiseType):
	var chunk_data: Dictionary = {};

	# Create a new, local noise generator for this thread
	var thread_noise = FastNoiseLite.new();
	thread_noise.seed = noise_seed;
	thread_noise.noise_type = noise_type;

	chunk_data = _generate_chunk_data(chunk_coord, thread_noise);
	_on_chunk_data_generated.call_deferred(chunk_coord, chunk_data);
#}

##
##	[MAIN THREAD CALLBACK]
##	Receives data from a finished thread, caches it, and instantiates the chunk.
##
func _on_chunk_data_generated(chunk_coord: Vector2i, chunk_data: Dictionary):

	var finished_thread: Thread = null;
	var chunks_to_load: Dictionary = {};
	var chunk_range: Dictionary = _get_current_chunk_range();

	_world_data[chunk_coord] = chunk_data;

	if _chunks_in_generation.has(chunk_coord):
		finished_thread = _chunks_in_generation[chunk_coord];
		finished_thread.wait_to_finish();
		_chunks_in_generation.erase(chunk_coord);

	for x in range(chunk_range.horizontal.x, chunk_range.horizontal.y):
		for y in range(chunk_range.vertical.x, chunk_range.vertical.y):
			chunks_to_load[Vector2i(x, y)] = true;

	if not chunks_to_load.has(chunk_coord):
		return;

	_instantiate_chunk(chunk_coord, chunk_data);
#}
#endregion


#region CORE GENERATION LOGIC
##
##	[RUNS ON A THREAD]
##	The main procedural generation algorithm coordinator.
##
func _generate_chunk_data(chunk_coord: Vector2i, noise_gen: FastNoiseLite) -> Dictionary:

	var data: Dictionary = {
		"water_tiles": {}, # {global_coord: terrain_id}
		"ground_tiles": [], # [local_coord]
		"grass_tiles": {}, # {local_coord: atlas_coord}
		"trees_tiles": {}, # {local_coord: atlas_coord}
		"poi": [] # [Dictionary]
	}

	var rng = RandomNumberGenerator.new();
	rng.seed = hash(Vector2i(noise_gen.seed, chunk_coord.x * 1000 + chunk_coord.y));

	# --- 1. Generate Base Terrain and Foliage ---
	var local_tile_coords: Vector2i = Vector2i.ZERO;
	var global_tile_x: int = 0;
	var global_tile_y: int = 0;
	var global_tile_coords: Vector2i = Vector2i.ZERO;
	var noise_value: float = 0.0;
	var is_ground_filled: bool = false;
	var chosen_tree: Dictionary = {};
	var chosen_grass: Dictionary = {};

	for x in range(CHUNK_SIZE_TILES):
		for y in range(CHUNK_SIZE_TILES):
			global_tile_x = chunk_coord.x * CHUNK_SIZE_TILES + x;
			global_tile_y = chunk_coord.y * CHUNK_SIZE_TILES + y;
			global_tile_coords = Vector2i(global_tile_x, global_tile_y);
			noise_value = noise_gen.get_noise_2d(global_tile_x,global_tile_y);
			local_tile_coords = Vector2i(x, y);

			if noise_value >= GROUND_NOISE_VALUE_THRESHOLD:
				is_ground_filled = false;

				if noise_value >= TREES_NOISE_VALUE_THRESHOLD and rng.randf() < TREES_PLACEMENT_DENSITY:
					chosen_tree = _pick_weighted_random(TREES_ATLAS_OPTIONS, rng);
					data["trees_tiles"][local_tile_coords] = chosen_tree.coords;
					is_ground_filled = true;

				if not is_ground_filled and noise_value >= GRASS_NOISE_VALUE_THRESHOLD and rng.randf() < GRASS_PLACEMENT_DENSITY:
					chosen_grass = _pick_weighted_random(GRASS_ATLAS_OPTIONS, rng);
					data["grass_tiles"][local_tile_coords] = chosen_grass.coords;
					is_ground_filled = true;

				if not is_ground_filled:
					data["ground_tiles"].append(local_tile_coords);
			else:
				data["water_tiles"][global_tile_coords] = 0;

	# --- 2. Place POIs ---
	# (Passa o dicionário 'data' e o 'rng' para a função de POI)
	_place_pois_in_chunk(data, rng, chunk_coord);

	return data;
#}


##
##	Iterates and places Points of Interest using a random attempt method.
##	Modifies the 'data' dictionary directly.
##
func _place_pois_in_chunk(data: Dictionary, rng: RandomNumberGenerator, chunk_coord: Vector2i) -> void:

	# 1. Criar cópias mutáveis das opções de POI
	var current_poi_options: Array[Dictionary] = [];
	for poi_option in POI_OPTIONS:
		current_poi_options.append(poi_option.duplicate(true));

	# (Novo) Lista para rastrear locais de POIs já colocados neste chunk
	var placed_poi_locations: Array[Vector2i] = [];

	# 2. Determinar quantos POIs tentar colocar
	var poi_count_to_place = rng.randi_range(MIN_POI_PER_CHUNK, MAX_POI_PER_CHUNK);

	for i in range(poi_count_to_place):
		# 3. Parar se não houver mais POIs válidos
		var total_weight = _get_total_poi_weight(current_poi_options);
		if total_weight <= 0.0:
			break;

		# 4. Escolher um tipo de POI
		var chosen_poi_copy: Dictionary = _pick_weighted_random(current_poi_options, rng);

		# 5. (Novo) Tentar encontrar um local válido
		var poi_chosen_location: Vector2i = Vector2i.MIN; # Flag "não encontrado"

		for attempt in range(MAX_POI_PLACEMENT_ATTEMPTS):
			var random_local_coord: Vector2i = Vector2i(
				rng.randi_range(0, CHUNK_SIZE_TILES - 1),
				rng.randi_range(0, CHUNK_SIZE_TILES - 1)
			);

			# --- Verificações de Validade ---

			# Verificação 1: É uma árvore?
			if data["trees_tiles"].has(random_local_coord):
				continue; # Tente outro local

			if data["grass_tiles"].has(random_local_coord):
				continue; # Tente outro local

			# Verificação 2: É água? (Precisa converter para global)
			var global_x = chunk_coord.x * CHUNK_SIZE_TILES + random_local_coord.x;
			var global_y = chunk_coord.y * CHUNK_SIZE_TILES + random_local_coord.y;
			var global_coord = Vector2i(global_x, global_y);

			if data["water_tiles"].has(global_coord):
				continue; # Tente outro local

			# Verificação 3: Está muito perto de outro POI *neste chunk*?
			var too_close: bool = false;
			for placed_loc in placed_poi_locations:
				if random_local_coord.distance_to(placed_loc) < float(POI_MIN_DISTANCE_TILES):
					too_close = true;
					break;

			if too_close:
				continue; # Tente outro local

			# --- Sucesso! ---
			poi_chosen_location = random_local_coord;
			break; # Para o loop de "attempt"

		# 6. Se não encontramos local após X tentativas, pule para o próximo POI
		if poi_chosen_location == Vector2i.MIN:
			continue; # Para o loop "i"

		# 7. Salvar o POI
		var pixel_position = (poi_chosen_location * TILE_SIZE_PIXELS);
		chosen_poi_copy.coords = pixel_position;
		data["poi"].append(chosen_poi_copy);

		# (Novo) Adiciona à lista para a Verificação 3
		placed_poi_locations.append(poi_chosen_location);

		# 8. Aplicar a penalidade de repetição
		for poi_option in current_poi_options:
			if poi_option.scene == chosen_poi_copy.scene:
				poi_option.weight = poi_option.weight * POI_ANTI_REPETITION_PENALTY;
				break;

		# (A remoção da "zona de exclusão" foi substituída pela Verificação 3)
	#}
#}
#endregion


#region SCENE & NODE MANAGEMENT
##
##	Instantiates a WorldChunk scene and initializes it with data.
##
func _instantiate_chunk(chunk_coord: Vector2i, chunk_data: Dictionary):

	var new_chunk_node: WorldChunk;
	var chunk_to_unload_key = "unload_%s_%s" % [chunk_coord.x, chunk_coord.y];

	if _water_changeset_chunks.has(chunk_to_unload_key):
		_water_changeset_chunks.erase(chunk_to_unload_key);

	new_chunk_node = WORLD_CHUNK_SCENE.instantiate();
	new_chunk_node.name = "Chunk_%s_%s" % [chunk_coord.x, chunk_coord.y];
	add_child(new_chunk_node);

	new_chunk_node.initialize(chunk_data);
	new_chunk_node.position = _get_world_pos_from_chunk_coords(chunk_coord);
	_active_chunks[chunk_coord] = new_chunk_node;

	if chunk_data.water_tiles:
		_prepare_water_tiles(chunk_coord, chunk_data.water_tiles);
		_update_water_neighbors(chunk_coord);
		_needs_water_refresh_hack = true;
	#}
#}

##
##	Removes a chunk node from the scene and queues water tile removal.
##
func _unload_chunk(chunk_coord: Vector2i):

	var chunk_node: WorldChunk = null;
	var chunk_to_load_key: String = "%s_%s" % [chunk_coord.x, chunk_coord.y];
	var chunk_to_unload_key = "unload_%s_%s" % [chunk_coord.x, chunk_coord.y];
	var tiles_to_clear: Dictionary = {};

	if _active_chunks.has(chunk_coord):
		chunk_node = _active_chunks[chunk_coord];
		chunk_node.queue_free();
		_active_chunks.erase(chunk_coord);

	chunk_to_load_key = "%s_%s" % [chunk_coord.x, chunk_coord.y];

	if _water_changeset_chunks.has(chunk_to_load_key):
		_water_changeset_chunks.erase(chunk_to_load_key);

	if _world_data.has(chunk_coord) and _world_data[chunk_coord].water_tiles:
		tiles_to_clear = {};
		for global_tile_coord in _world_data[chunk_coord].water_tiles:
			tiles_to_clear[global_tile_coord] = -1;

		chunk_to_unload_key = "unload_%s_%s" % [chunk_coord.x, chunk_coord.y];
		_water_changeset_chunks[chunk_to_unload_key] = BetterTerrain.create_terrain_changeset(water_layer, tiles_to_clear);

		_update_water_neighbors(chunk_coord);
#}

##
##	Converts chunk coordinates back into a global world position (pixels).
##
func _get_world_pos_from_chunk_coords(chunk_coord: Vector2i) -> Vector2:
	return chunk_coord * CHUNK_SIZE_TILES * TILE_SIZE_PIXELS;
#}
#endregion


#region WATER AUTOTILE SUBSYSTEM
##
##	Triggers a water tile update for chunks adjacent to this one.
##
func _update_water_neighbors(chunk_coord: Vector2i) -> void:
	var neighbors_chunks: Array[Vector2i] = [
		chunk_coord + Vector2i.LEFT,
		chunk_coord + Vector2i.RIGHT,
		chunk_coord + Vector2i.UP,
		chunk_coord + Vector2i.DOWN
	];

	for n_coord in neighbors_chunks:
		if _active_chunks.has(n_coord):
			if _world_data.has(n_coord):
				_prepare_water_tiles(n_coord, _world_data[n_coord].water_tiles);
#}

##
##	Creates a 'changeset' for the BetterTerrain autotiler.
##
func _prepare_water_tiles(chunk_coord: Vector2i, water_tiles: Dictionary) -> void:
	var coords = "%s_%s" % [chunk_coord.x, chunk_coord.y];
	_water_changeset_chunks[coords] = BetterTerrain.create_terrain_changeset(water_layer, water_tiles);
#}

##
##	Called every frame. Applies any ready water changesets.
##
func _paint_water_tiles() -> void:
	var applied_keys = [];
	var changeset: Dictionary = {};

	for key in _water_changeset_chunks:
		changeset = _water_changeset_chunks[key];

		if changeset.is_empty():
			applied_keys.append(key);
			continue;

		if BetterTerrain.is_terrain_changeset_ready(changeset):
			BetterTerrain.apply_terrain_changeset(changeset);
			applied_keys.append(key);

	for key in applied_keys:
		_water_changeset_chunks.erase(key);
#}

##
##	[GAMBIARRA]
##	Força o re-processamento de 'changeset' de água para
##	TODOS os chunks atualmente ativos na cena.
##
func _force_refresh_all_active_water() -> void:

	# (CORREÇÃO) Remove a tipagem "Array[Vector2i]"
	var active_coords = _active_chunks.keys();

	for chunk_coord in active_coords:

		# Verifica se o chunk (ainda) tem dados cacheados
		if _world_data.has(chunk_coord):
			var chunk_data: Dictionary = _world_data[chunk_coord];

			# Se esse chunk tiver dados de água,
			# chama _prepare_water_tiles para ele novamente.
			if chunk_data.water_tiles:
				_prepare_water_tiles(chunk_coord, chunk_data.water_tiles);
#}

#endregion


#region UTILITIES
##
##	Selects a random item from an array of dictionaries based on "weight".
##
func _pick_weighted_random(array: Array[Dictionary], rng: RandomNumberGenerator) -> Dictionary:
	var total_weight: float = 0.0;
	var random_pick: float = 0.0;

	for item in array:
		total_weight += item.weight;

	random_pick = rng.randf() * total_weight;

	for item in array:
		random_pick -= item.weight;
		if random_pick <= 0.0:
			return item.duplicate();

	return array.back();
#}

##
##	Calculates the sum of "weight" from an array of POI dictionaries.
##
func _get_total_poi_weight(poi_array: Array[Dictionary]) -> float:
	var total: float = 0.0;
	for item in poi_array:
		total += item.weight;
	return total;
#}


##
##	Função de callback para ordenar a fila de geração.
##	Ordena por distância (menor primeiro) do chunk atual do jogador.
##
func _sort_chunks_by_distance(a: Vector2i, b: Vector2i) -> bool:
	var dist_a: float = a.distance_squared_to(_current_player_chunk);
	var dist_b: float = b.distance_squared_to(_current_player_chunk);
	return dist_a < dist_b;
#}

#endregion


#region DEBUG
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
