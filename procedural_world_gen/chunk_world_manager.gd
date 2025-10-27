"""
CHUNK WORLD MANAGER
"""
extends Node

@export var player: Node2D;
@export var noise_texture: NoiseTexture2D;

const WORLD_CHUNK_SCENE := preload("res://world_chunk.tscn");
const CHUNK_SIZE_TILES: int = 32;

const CHUNK_LOAD_RADIUS: int = 1;
const TILE_PIXELS: int = 16;

var chunks_in_generation: Dictionary = {}; # Rastreia chunks em geração
var world_data: Dictionary = {};
var active_chunks: Dictionary = {};
var current_player_chunk = Vector2i.ZERO;
var noise: Noise;
var grass_placement_density: float = 0.2;
var trees_placement_density: float = 0.1;
var water_tiles_array: Array[Vector2i] = [];
var ground_tiles_array: Array[Vector2i] = [];
var grass_tiles_array: Array[Vector2i] = [];
var trees_tiles_array: Array[Vector2i] = [];
var water_noise_value_threshold: float = 0.0;
var ground_noise_value_threshold: float = 0.0;
var trees_noise_value_threshold: float = 0.2;
var grass_noise_value_threshold: float = 0.03;

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


func _ready() -> void:

	randomize();

	noise = FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.seed = randi();

	current_player_chunk = get_chunk_coords_from_world(player.global_position);

	update_chunks();
#}


func _process(_delta: float) -> void:

	var new_player_chunk = get_chunk_coords_from_world(player.global_position);

	if new_player_chunk != current_player_chunk:
		current_player_chunk = new_player_chunk;
		update_chunks();
#}


func update_chunks():
	var desired_chunks = {};
	var chunk_range = _get_current_chunk_range();
	for x in range(chunk_range.horizontal.x, chunk_range.horizontal.y):
		for y in range(chunk_range.vertical.x, chunk_range.vertical.y):

			var chunk_coord = Vector2i(x, y);
			desired_chunks[chunk_coord] = true;

			# MODIFICADO: Só carrega se não estiver ativo E não estiver sendo gerado
			if not active_chunks.has(chunk_coord) and not chunks_in_generation.has(chunk_coord):
				load_chunk(chunk_coord)
			#if not active_chunks.has(chunk_coord):
				#load_chunk(chunk_coord);
		#} endfor y
	#} endfor x

	var chunks_to_unload = [];
	for chunk_coord in active_chunks.keys():
		if not desired_chunks.has(chunk_coord):
			chunks_to_unload.append(chunk_coord);


	for chunk_coord in chunks_to_unload:
		unload_chunk(chunk_coord);
#}

# MODIFICADO: Agora decide se gera dados (thread) ou se instancia (imediato)
func load_chunk(chunk_coord: Vector2i):
	#var chunk_data: Dictionary;

	if world_data.has(chunk_coord):
		# Dados já existem, apenas instancie (rápido)
		_instantiate_chunk(chunk_coord, world_data[chunk_coord]);
		#chunk_data = world_data[chunk_coord];
	else:
		# Dados não existem, inicie um thread para gerar (lento)
		chunks_in_generation[chunk_coord] = true; # Marca como "em geração"

		var thread = Thread.new();
		# Inicia o thread, chamando a função _generate_data_thread
		# e passando chunk_coord como argumento
		thread.start(_generate_data_thread.bind(chunk_coord));

	#var new_chunk_node: WorldChunk = WORLD_CHUNK_SCENE.instantiate();
	#new_chunk_node.name = "Chunk_%s_%s" % [chunk_coord.x, chunk_coord.y];
	#add_child(new_chunk_node);
	#new_chunk_node.initialize(chunk_data);
#
	#new_chunk_node.position = get_world_pos_from_chunk_coords(chunk_coord);
#
	#active_chunks[chunk_coord] = new_chunk_node
#}


# NOVO: Esta função roda no Thread
func _generate_data_thread(chunk_coord: Vector2i):
	# 1. O trabalho pesado é feito aqui, fora da thread principal
	var chunk_data = generate_chunk_data(chunk_coord);

	# 2. Quando terminar, chama a função de callback na thread principal
	# call_deferred() é essencial para garantir que o código rode
	# de volta na thread principal de forma segura.
	_on_data_generated.call_deferred(chunk_coord, chunk_data);
#}


# NOVO: Esta função roda de volta na Thread Principal
func _on_data_generated(chunk_coord: Vector2i, chunk_data: Dictionary):
	# 1. Salva os dados gerados
	world_data[chunk_coord] = chunk_data;
	# 2. Remove do rastreamento
	chunks_in_generation.erase(chunk_coord);

	# 3. VERIFICAÇÃO CRÍTICA: O jogador ainda quer este chunk?
	# Ele pode ter se movido para longe enquanto o thread trabalhava.
	var desired_chunks = {};
	var chunk_range = _get_current_chunk_range();

	for x in range(chunk_range.horizontal.x, chunk_range.horizontal.y):
		for y in range(chunk_range.vertical.x, chunk_range.vertical.y):
			desired_chunks[Vector2i(x, y)] = true;

	if not desired_chunks.has(chunk_coord):
		# Jogador se moveu. Não fazemos nada.
		# Os dados ficam salvos em world_data para uso futuro.
		return;

	# 4. Se o chunk ainda é desejado, instanciamos ele.
	_instantiate_chunk(chunk_coord, chunk_data);
#}


# NOVO: Função separada para instanciação (roda na thread principal)
func _instantiate_chunk(chunk_coord: Vector2i, chunk_data: Dictionary):
	# Este código é o conteúdo original de load_chunk
	var new_chunk_node: WorldChunk = WORLD_CHUNK_SCENE.instantiate();
	new_chunk_node.name = "Chunk_%s_%s" % [chunk_coord.x, chunk_coord.y];
	add_child(new_chunk_node);
	new_chunk_node.initialize(chunk_data);

	new_chunk_node.position = get_world_pos_from_chunk_coords(chunk_coord);

	active_chunks[chunk_coord] = new_chunk_node;
#}


func get_world_pos_from_chunk_coords(chunk_coord: Vector2i) -> Vector2:
	return chunk_coord * CHUNK_SIZE_TILES * TILE_PIXELS;
#}


func get_chunk_coords_from_world(world_pos: Vector2) -> Vector2i:
	var tile_coord = (world_pos / TILE_PIXELS).floor()
	var chunk_coord = (tile_coord / CHUNK_SIZE_TILES).floor()
	return chunk_coord as Vector2i
#}


func unload_chunk(chunk_coord: Vector2i):
	if active_chunks.has(chunk_coord):
		var chunk_node = active_chunks[chunk_coord];
		chunk_node.queue_free();
		active_chunks.erase(chunk_coord);
#}


func generate_chunk_data(chunk_coord: Vector2i) -> Dictionary:
	var data = {
		"water_terrain": {},
		"water_tiles": [],  # is an array cause use terrain
		"ground_tiles": [], # is an array cause use terrain
		"grass_tiles": {},
		"trees_tiles": {},
		"poi": ""
	}

	for x in range(CHUNK_SIZE_TILES):
		for y in range(CHUNK_SIZE_TILES):

			var global_tile_x := chunk_coord.x * CHUNK_SIZE_TILES + x;
			var global_tile_y := chunk_coord.y * CHUNK_SIZE_TILES + y;
			var noise_value := noise.get_noise_2d(global_tile_x,global_tile_y);
			var local_tile_coords: Vector2i = Vector2i(x, y);

			if noise_value >= ground_noise_value_threshold:
				var is_ground_filled : bool = false;

				if noise_value >= trees_noise_value_threshold:
					if randf() < trees_placement_density:
						var chosen_tree: Dictionary = _pick_weighted_random(trees_atlas_coord_array);

						data["trees_tiles"][local_tile_coords] = chosen_tree.coords;
						is_ground_filled = true
				#} endif treenoise

				if not is_ground_filled:
					if randf() < grass_placement_density:
						var chosen_grass: Dictionary = _pick_weighted_random(grass_atlas_coord_array);
						data["grass_tiles"][local_tile_coords] = chosen_grass.coords;
						is_ground_filled = true;
				#} endif grass not is_ground_filled

				if not is_ground_filled:
					data["ground_tiles"].append(local_tile_coords);
				#} endif not is_ground_filled

			else:
				data["water_terrain"][local_tile_coords] = 0;
				data["water_tiles"].append(local_tile_coords);
			#} endif ground_noise_value

		#} endfor y
	#} endfor x

	var poi_noise_val = noise.get_noise_2d(chunk_coord.x, chunk_coord.y)
	if poi_noise_val > 0.6:
		var chosen_poi: Dictionary = _pick_weighted_random(poi_options);
		data["poi"] = chosen_poi.path;

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
