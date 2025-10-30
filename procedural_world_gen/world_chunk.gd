class_name WorldChunk
extends Node2D

const TILE_SOURCE_ID: int = 0;

@onready var ground_layer: TileMapLayer = $LayerGround;
@onready var grass_layer: TileMapLayer = $LayerGrass;
@onready var trees_layer: TileMapLayer = $LayerTrees;
@onready var poi_layer: Node2D = $LayerPOI;

func _ready() -> void:
	ground_layer.z_index = -1;
	grass_layer.z_index = -1;
#}


func initialize(chunk_data: Dictionary) -> void:

	## -- PLACE GRASS --
	if chunk_data.grass_tiles:
		for coords in chunk_data.grass_tiles:
			grass_layer.set_cell(
				coords,
				TILE_SOURCE_ID,
				chunk_data.grass_tiles[coords]
			);
	#}

	## -- PLACE TREES --
	if chunk_data.trees_tiles:
		for coords in chunk_data.trees_tiles:
			trees_layer.set_cell(
				coords,
				TILE_SOURCE_ID,
				chunk_data.trees_tiles[coords]
			);
	#}

	## -- PLACE POI --

	if not chunk_data.poi.is_empty():
		for poi in chunk_data.poi:
			var poi_scene: PackedScene = load(poi.scene);
			var poi_instance = poi_scene.instantiate();
			poi_layer.add_child(poi_instance);
			poi_instance.position = poi.coords;
			print(poi.coords)
	#}



#}
