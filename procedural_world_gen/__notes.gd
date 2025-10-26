extends Node

"""
1. Criar uma export variable NoiseTexture2D
2. No atributo Noise, criar um novo FastNoiseLite
3. Color Ramp para melhor visualização dos valores (Interpolation > Mode constant)
4. Ajustar o valor de frequency = zoom in/out do noise, aumentando/diminuindo as land masses (menos é mais land)
5. Ajustar o z-index das layers (Ordering > Z Index)
6. Novo Noise apenas para árvores
"""


"""
To-Do List:
Design the "Overworld" Scene:

Treat this as your main game scene.

This scene will be responsible for procedural generation and chunk management.

Add your Player node to this scene.

Implement the Chunking System for the Overworld:

Create a WorldManager script.

Decide on a chunk size (e.g., 32x32 tiles).

Define a "load radius" around the player (e.g., a 3x3 chunk grid).

Create a Dictionary (e.g., world_data) to store the data for all visited chunks.

Create the Overworld Generation Logic:

Implement your procedural generation algorithm (e.g., using FastNoiseLite).

This algorithm must generate two things for each chunk:

The basic terrain (e.g., grass, mountains, forest).

What POI, if any, exists on that chunk (e.g., "Cave Entrance", "Town Gate", "Dungeon").

Implement the Chunk Load/Unload Logic:

On Load:

Check world_data for the chunk.

If it doesn't exist: run your generation algorithm, save the new data to world_data, and build the chunk TileMap node.

If it does exist: load the saved data from world_data and build the chunk TileMap node.

On Unload:

(Optional: Save any changes, like a dug-up tree, to world_data).

Call queue_free() on the chunk's TileMap node to remove it from the scene.

Handle POIs (Points of Interest):

When loading a chunk, check its saved data for a POI.

If a POI exists, instance a separate, simple scene for its overworld representation (e.g., a "CaveEntrance.tscn" that is just an Area2D node with a sprite).

This Area2D will be the "door" or transition point.

Create the Scene Transition Logic:

Connect the body_entered signal from your POI's Area2D (the "door").

When the player enters, call a global function (e.g., SceneManager.change_scene("path/to/LocalMap.tscn")).

This function should handle the screen fade-out, switch the scenes, and fade back in.

Build Your "Local Map" Scenes:

Create new, separate scenes for each type of POI (e.g., TownScene.tscn, DungeonLevel1.tscn).

These scenes are not part of the chunking system. They are fixed-size, self-contained maps (which can still be procedurally generated when they first load, if you want).

Add an "Exit" Area2D in these scenes to transition the player back to the overworld.
"""
