class_name WorldChunk
extends Node2D

var tile_source_id: int = 0;
var water_layer_terrain_set_index: int = 0;
var water_layer_terrain_index: int = 0;
var water_changeset: Dictionary;

@onready var water_layer: TileMapLayer = $LayerWater;
@onready var ground_layer: TileMapLayer = $LayerGround;
@onready var grass_layer: TileMapLayer = $LayerGrass;
@onready var trees_layer: TileMapLayer = $LayerTrees;
@onready var poi_layer: Node2D = $LayerPOI;

func _ready() -> void:
	water_layer.z_index = -1;
	ground_layer.z_index = -1;
	grass_layer.z_index = -1;
#}

func _process(_delta: float) -> void:
	if BetterTerrain.is_terrain_changeset_ready(water_changeset):
		BetterTerrain.apply_terrain_changeset(water_changeset);
		water_changeset = {};
#}

func initialize(chunk_data: Dictionary) -> void:

	for coords in chunk_data.grass_tiles:
		grass_layer.set_cell(
			coords,
			tile_source_id,
			chunk_data.grass_tiles[coords]
		);
	#}

	for coords in chunk_data.trees_tiles:
		trees_layer.set_cell(
			coords,
			tile_source_id,
			chunk_data.trees_tiles[coords]
		);
	#}

	# var poi_options: Array[Dictionary] = [
	#	{ "path": "res://poi_village.tscn", "weight": 1},
	#];
	#for poi in chunk_data.poi:
		#var poi_scene := load(chunk_data.poi.path);
		#var poi_instance = poi_scene.instantiate();
		#poi_layer.add_child(poi_instance);
		#poi_instance.position = poi;
	##}

	if not chunk_data.water_tiles:
		return;

	water_changeset = BetterTerrain.create_terrain_changeset(water_layer, chunk_data.water_terrain);
	#for coords in chunk_data.water_tiles:
		#BetterTerrain.set_cell(water_layer, coords, 0);
	#BetterTerrain.update_terrain_cells(water_layer, chunk_data.water_tiles, false);
	#var top_left: Vector2i = chunk_data.water_tiles[0];
	#var bottom_right: Vector2i = chunk_data.water_tiles[chunk_data.water_tiles.size() - 1];
	#var size: Vector2i = bottom_right - top_left + Vector2i(1, 1);
	#var my_rect: Rect2i = Rect2i(top_left, size);
	#BetterTerrain.update_terrain_area(water_layer, my_rect);

	#water_layer.set_cells_terrain_connect(
		#chunk_data.water_tiles,
		#water_layer_terrain_set_index,
		#water_layer_terrain_index
	#);
#}
