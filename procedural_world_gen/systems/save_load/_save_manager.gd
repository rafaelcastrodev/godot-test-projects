# SaveManager.gd
# Autoload Singleton para gerenciar todas as operações de save/load.
extends Node

# Sinaliza o início e o fim das operações para a UI.
signal save_started
signal save_complete(slot_num, status)
signal load_complete(slot_num, status, data)

enum Status { SUCCESS, ERROR_NO_FILE, ERROR_CORRUPT, ERROR_FAILED_TO_WRITE }

const SAVE_PATH_TEMPLATE_BIN = "user://save_slot_%d.sav"
const SAVE_PATH_TEMPLATE_JSON = "user://save_slot_%d.json"
const METADATA_PATH = "user://save_meta.dat"
const ENCRYPTION_KEY = "your_super_secret_key_here" # Mude isso para o seu jogo!

var save_metadata: Dictionary = {}
var save_thread: Thread
var save_mutex: Mutex = Mutex.new()

func _ready():
	load_all_metadata()

# Carrega os metadados de todos os slots de uma vez no início.
func load_all_metadata():
	var file = FileAccess.open(METADATA_PATH, FileAccess.READ)
	if file:
		# Acesso aos metadados não precisa de mutex aqui, pois ocorre antes de qualquer thread.
		save_metadata = file.get_var()
		file.close()

# Salva os metadados. Deve ser chamado após uma operação de save bem-sucedida.
func _save_all_metadata():
	var file = FileAccess.open(METADATA_PATH, FileAccess.WRITE)
	if file:
		file.store_var(save_metadata)
		file.close()

# Função pública para iniciar o processo de salvamento.
func save_game(slot_num: int, data: Dictionary, playtime: float, thumbnail: Image):
	if save_thread and save_thread.is_alive():
		print("Save operation already in progress.")
		return

	emit_signal("save_started")
	save_thread = Thread.new()

	# Usamos bind para passar argumentos para a função da thread.
	var callable = Callable(self, "_thread_save_game").bind(slot_num, data, playtime, thumbnail)
	save_thread.start(callable)

# Função pública para iniciar o processo de carregamento.
func load_game(slot_num: int):
	if save_thread and save_thread.is_alive():
		print("Another operation already in progress.")
		return

	save_thread = Thread.new()
	var callable = Callable(self, "_thread_load_game").bind(slot_num)
	save_thread.start(callable)

# --- Funções executadas na Thread de Trabalho ---

func _thread_save_game(slot_num: int, data: Dictionary, playtime: float, thumbnail: Image):
	save_mutex.lock()

	var use_json = OS.is_debug_build()
	var file_path = (SAVE_PATH_TEMPLATE_JSON if use_json else SAVE_PATH_TEMPLATE_BIN) % slot_num

	# 1. Preparar dados com metadados e checksum
	var data_to_save = data.duplicate(true)
	var metadata = {
		"save_timestamp": Time.get_datetime_string_from_system(),
		"playtime_seconds": playtime,
		"version": "1.0.0"
	}
	data_to_save["metadata"] = metadata

	# 2. Serializar e calcular checksum
	var bytes: PackedByteArray
	if use_json:
		bytes = JSON.stringify(data_to_save).to_utf8_buffer()
	else:
		#bytes = Marshalls.variant_to_bytes(data_to_save)
		#TODO
		pass

	var checksum = bytes.sha256_buffer().hex_encode()

	# 3. Escrever no arquivo com criptografia
	var file = FileAccess.open_encrypted_with_pass(file_path, FileAccess.WRITE, ENCRYPTION_KEY)
	if not file:
		save_mutex.unlock()
		call_deferred("emit_signal", "save_complete", slot_num, Status.ERROR_FAILED_TO_WRITE)
		return

	file.store_string(checksum) # Armazena o checksum primeiro
	file.store_buffer(bytes)    # Armazena os dados
	file.close()

	# 4. Atualizar e salvar metadados globais
	save_metadata[slot_num] = metadata
	_save_all_metadata()

	# (Opcional) Salvar miniatura como arquivo separado
	if thumbnail:
		thumbnail.save_png("user://save_thumb_%d.png" % slot_num)

	save_mutex.unlock()
	call_deferred("emit_signal", "save_complete", slot_num, Status.SUCCESS)

func _thread_load_game(slot_num: int):
	save_mutex.lock()

	var use_json = OS.is_debug_build()
	var file_path = (SAVE_PATH_TEMPLATE_JSON if use_json else SAVE_PATH_TEMPLATE_BIN) % slot_num

	if not FileAccess.file_exists(file_path):
		save_mutex.unlock()
		call_deferred("emit_signal", "load_complete", slot_num, Status.ERROR_NO_FILE, null)
		return

	# 1. Ler arquivo criptografado
	var file = FileAccess.open_encrypted_with_pass(file_path, FileAccess.READ, ENCRYPTION_KEY)
	if not file:
		save_mutex.unlock()
		call_deferred("emit_signal", "load_complete", slot_num, Status.ERROR_CORRUPT, null)
		return

	var stored_checksum = file.get_line()
	var bytes = file.get_buffer(file.get_length() - file.get_position())
	file.close()

	# 2. Verificar integridade com checksum
	var calculated_checksum = bytes.sha256_buffer().hex_encode()
	if stored_checksum!= calculated_checksum:
		save_mutex.unlock()
		call_deferred("emit_signal", "load_complete", slot_num, Status.ERROR_CORRUPT, null)
		return

	# 3. Desserializar dados
	var data: Variant
	if use_json:
		data = JSON.parse_string(bytes.get_string_from_utf8())
	else:
		data = Marshalls.bytes_to_variant(bytes)

	save_mutex.unlock()
	call_deferred("emit_signal", "load_complete", slot_num, Status.SUCCESS, data)
