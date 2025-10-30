## SaveManager.gd
## Autoload Singleton para gerenciar todas as operações de save/load.
#extends Node
#
## Sinaliza o início e o fim das operações para a UI.
#signal save_started;
#signal save_complete(slot_num, status);
#signal load_complete(slot_num, status, data);
#
#const SAVE_PATH_TEMPLATE = "user://save.sav";
#
#func save_game(data: Dictionary) -> void:
	#save_started.emit();
	#var file = FileAccess.open(SAVE_PATH_TEMPLATE, FileAccess.WRITE);
#
	#if file:
		#file.store_var(data);
		#file.close();
		#save_complete.emit();
##}
#
#func load_game() -> Dictionary:
#
	#if not FileAccess.file_exists(SAVE_PATH_TEMPLATE):
		#return {};
#
	#var file = FileAccess.open(SAVE_PATH_TEMPLATE, FileAccess.READ);
	#if file:
		#var data = file.get_var();
		#file.close();
		#load_complete.emit();
		#return data;
#
	#return {};
##}
#
##func save_game_settings() -> void:
	##pass
###}
##
##func load_game_settings() -> Dictionary:
	##return {};
###}
