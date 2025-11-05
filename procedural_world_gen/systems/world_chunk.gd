##
##	WORLD CHUNK (Corrigido)
##
class_name WorldChunk
extends Node2D

const TILE_SOURCE_ID: int = 0;
const TILES_TO_PAINT_PER_FRAME = 50;

##@ Node References
@onready var ground_layer: TileMapLayer = $LayerGround;
@onready var grass_layer: TileMapLayer = $LayerGrass;
@onready var trees_layer: TileMapLayer = $LayerTrees;
@onready var poi_layer: Node2D = $LayerPOI;

##@ Variáveis de estado para pintura
# (Modificado) Listas de coordenadas para pintar
var _grass_to_paint: Array = [];
var _trees_to_paint: Array = [];

# (Modificado) Dicionários de dados *apenas* para pintura
var _grass_tiles_data: Dictionary = {};
var _trees_tiles_data: Dictionary = {};


func _ready() -> void:
	ground_layer.z_index = -1;
	grass_layer.z_index = -1;
	set_process(false);
#}


##
##	(Modificado) Recebe os dados, copia apenas o que precisa, e ativa o _process.
##
func initialize(chunk_data: Dictionary) -> void:

	# 1. Copia os dados de que precisamos (não armazena o chunk_data inteiro)
	if chunk_data.grass_tiles:
		_grass_tiles_data = chunk_data.grass_tiles;
		_grass_to_paint = _grass_tiles_data.keys();

	if chunk_data.trees_tiles:
		_trees_tiles_data = chunk_data.trees_tiles;
		_trees_to_paint = _trees_tiles_data.keys();

	# 2. Instancia POIs
	if not chunk_data.poi.is_empty():
		for poi in chunk_data.poi:
			var poi_instance = poi.scene.instantiate();
			poi_layer.add_child(poi_instance);
			poi_instance.position = poi.coords;

	# 3. Ativa o _process se houver algo para pintar
	if not _grass_to_paint.is_empty() or not _trees_to_paint.is_empty():
		set_process(true);
#}


##
##	(Modificado) Pinta usando os dados locais
##
func _process(_delta: float) -> void:

	var painted_count = 0;

	while painted_count < TILES_TO_PAINT_PER_FRAME:

		# 1. Tenta pintar grama
		if not _grass_to_paint.is_empty():
			var coords: Vector2i = _grass_to_paint.pop_front();
			# (Modificado) Usa o dicionário de dados local
			var atlas_coords: Vector2i = _grass_tiles_data[coords];

			grass_layer.set_cell(coords, TILE_SOURCE_ID, atlas_coords);
			painted_count += 1;

		# 2. Tenta pintar árvores
		elif not _trees_to_paint.is_empty():
			var coords: Vector2i = _trees_to_paint.pop_front();
			# (Modificado) Usa o dicionário de dados local
			var atlas_coords: Vector2i = _trees_tiles_data[coords];

			trees_layer.set_cell(coords, TILE_SOURCE_ID, atlas_coords);
			painted_count += 1;

		# 3. Se ambos acabaram, pare
		else:
			break;
	#} end while

	# Se ambas as filas estiverem vazias, desative o _process
	if _grass_to_paint.is_empty() and _trees_to_paint.is_empty():
		set_process(false);

		# (Modificado) Limpa apenas as referências locais.
		# Isso NÃO afeta os dados no WorldChunkManager.
		_grass_tiles_data = {};
		_trees_tiles_data = {};
#}
