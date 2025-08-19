class_name FlapbirdPipes
extends Node2D

signal scored;
signal pipe_entered_screen(FlapbirdPipes);
signal pipe_exited_screen(FlapbirdPipes);
signal pipe_touched(pipe_position: String);

@onready var top_pipe: FlapbirdPipe = $TopPipe;
@onready var bottom_pipe: FlapbirdPipe = $BottomPipe;
@onready var score_detection: Area2D = $ScoreDetection;
@onready var visible_on_screen_notifier_2d: VisibleOnScreenNotifier2D = $VisibleOnScreenNotifier2D;

func _ready() -> void:
	top_pipe.pipe_touched.connect(_on_pipe_touched_pipe.bind('top'));
	bottom_pipe.pipe_touched.connect(_on_pipe_touched_pipe.bind('bottom'));
	score_detection.body_exited.connect(_on_body_exited_score_detection.bind());
	visible_on_screen_notifier_2d.screen_entered.connect(_on_screen_entered_notifier.bind());
	visible_on_screen_notifier_2d.screen_exited.connect(_on_screen_exited_notifier.bind());
#}

func get_size() -> Vector2:
	return Vector2(top_pipe.get_size().x, top_pipe.get_size().y * 2) * self.scale;
#}

func _on_pipe_touched_pipe(pipe_position: String) -> void:
	#print_debug("Pipe Touched: ",pipe_position)
	pipe_touched.emit(pipe_position);
#}


func _on_body_exited_score_detection(body: Node2D) -> void:
	#print_debug("Score +1")
	scored.emit();
#}


func _on_screen_entered_notifier() -> void:
	pipe_entered_screen.emit(self);
	#print_debug("Pipes left the screen")
#}


func _on_screen_exited_notifier() -> void:
	pipe_exited_screen.emit(self);
	#print_debug("Pipes left the screen")
#}
