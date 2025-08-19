extends Node2D

const FACTOR_PLAYER_SIZE_SCALE: float = 0.9;
const GRAVITY: float = 1000;
const JUMP_VELOCITY: float = 550;
const PLAYER_FORWARD_VELOCITY: float = 125;

const PIPES_FIRST_LOAD_QUANTITY: int = 5;
const PIPE_SPACING_HORIZONTAL: float = 450.0  # Distância horizontal entre os canos
const VERTICAL_OFFSET_RANGE: Vector2 = Vector2(-310, 310); # Faixa de variação da altura Y

var score: int = 0;
var best_score: int = 0;
var is_game_on: bool = false;
var is_game_over: bool = false;

var _player: FlapbirdPlayer;
var _pipes_loaded: Array[FlapbirdPipes] = [];
var _last_spawn_pipe_position: Vector2 = Vector2.ZERO;
var _next_spawn_x_position: float = 0.0;
var _camera_rect_zoomed: Vector2 = Vector2.ZERO;

@onready var PLAYER_SCENE: Resource = preload("res://flapbird/player.tscn");
@onready var PIPES_SCENE: Resource = preload("res://flapbird/pipes.tscn");
@onready var camera_2d: Camera2D = $Camera2D;
@onready var ui_game_on: CanvasLayer = $UI/UI_Game_On;
@onready var ui_game_over: CanvasLayer = $UI/UI_Game_Over;
@onready var score_label: Label = $UI/UI_Game_On/HBoxContainer/ScoreLabel;
@onready var current_score_label: Label = $UI/UI_Game_Over/HBoxContainer/VBoxContainer/FinalScoreLabel;
@onready var best_score_label: Label = $UI/UI_Game_Over/HBoxContainer/VBoxContainer/BestScoreLabel;
@onready var replay_button: Button = $UI/UI_Game_Over/HBoxContainer/VBoxContainer/HBoxContainer/ReplayButton;

func _ready() -> void:
	_camera_rect_zoomed = _get_camera_rect();
	replay_button.pressed.connect(_on_replay_pressed.bind());
	start_game();
#}


func _physics_process(delta: float) -> void:

	if not _player:
		return;

	_handle_player_process(delta);

	camera_2d.position.x = _player.position.x;
#}

func _handle_player_process(delta: float) -> void:
	_handle_movement(delta);
	_handle_input();

	_player.move_and_slide();
#}


func _handle_input() -> void:
	if Input.is_action_just_pressed("ui_accept"):
		_player.velocity.y = JUMP_VELOCITY * (-1);
#}


func _handle_movement(delta: float) -> void:

	_handle_gravity(delta);

	_handle_forward_movement(delta);
#}


func _handle_gravity(delta: float) -> void:
	_player.velocity.y += GRAVITY * delta;
#}


func _handle_forward_movement(delta: float) -> void:
	_player.velocity.x = PLAYER_FORWARD_VELOCITY;
#}


func start_game() -> void:
	current_score_label.text = str(0);
	ui_game_over.hide();
	ui_game_on.show();

	var player_size: Vector2;

	if not _player:
		_player = PLAYER_SCENE.instantiate();
		_player.scale = Vector2(FACTOR_PLAYER_SIZE_SCALE,FACTOR_PLAYER_SIZE_SCALE);
		add_child(_player);
		player_size = _player.get_size();
	else:
		_player.position = Vector2(0,0);
		for i in _pipes_loaded.size():
			_pipes_loaded[i].queue_free();
		_pipes_loaded = [];

	camera_2d.offset.x = player_size.x;
	_last_spawn_pipe_position = Vector2.ZERO;

	for i in PIPES_FIRST_LOAD_QUANTITY:
		_spawn_pipe(i);

	is_game_over = false;
	is_game_on = true;
#}

func _spawn_pipe(index_pipe: int) -> void:

	var pipes: FlapbirdPipes = _create_pipe_for_spawn(index_pipe);

	_pipes_loaded.append(pipes);
	add_child(pipes);
	pipes.global_position = _get_pipe_new_position(_last_spawn_pipe_position);
#}


func _get_pipe_new_position(current_pos: Vector2) -> Vector2:
	var spawn_position: Vector2 = Vector2();

	if _last_spawn_pipe_position.x == 0:
		spawn_position.x = _camera_rect_zoomed.x;
	else:
		spawn_position.x = _last_spawn_pipe_position.x + PIPE_SPACING_HORIZONTAL;

	spawn_position.y = randf_range(VERTICAL_OFFSET_RANGE.x, VERTICAL_OFFSET_RANGE.y)
	_last_spawn_pipe_position = spawn_position;

	return spawn_position;
#}


func _create_pipe_for_spawn(index: int = 0) -> FlapbirdPipes:

	var pipes: FlapbirdPipes = PIPES_SCENE.instantiate();
	pipes.pipe_touched.connect(_on_pipe_touched.bind());
	pipes.pipe_entered_screen.connect(_on_pipes_entered_screen.bind());
	pipes.pipe_exited_screen.connect(_on_pipes_exited_screen.bind(index));
	pipes.scored.connect(_on_scored_on_pipe.bind());

	return pipes;
#}


func _get_camera_rect() -> Vector2:
	var camera_rect: Rect2 = camera_2d.get_viewport_rect();

	var x = camera_rect.end.x / camera_2d.zoom.x;
	var y = camera_rect.end.y  / camera_2d.zoom.y;

	return Vector2(x, y);
#}


func _on_scored_on_pipe() -> void:
	score += 1;
	score_label.text = str(score);
#}


func _on_pipe_touched(pipe_position: String) -> void:
	is_game_on = false;
	is_game_over = true;
	current_score_label.text = str("Score ",score);
	best_score_label.text = str("Best ",best_score);
	ui_game_on.hide();
	ui_game_over.show();
	get_tree().paused = true;
#}

func _on_replay_pressed() -> void:
	get_tree().paused = false;
	start_game();
#}


func _on_pipes_entered_screen(pipes_entering_screen: FlapbirdPipes) -> void:
	pass
#}


func _on_pipes_exited_screen(pipes_exiting_screen: FlapbirdPipes, pipe_index: int) -> void:
	_pipes_loaded[pipe_index].global_position = _get_pipe_new_position(_pipes_loaded[pipe_index].global_position);
#}
