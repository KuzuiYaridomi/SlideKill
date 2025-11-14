extends Area3D

@export var node_path: NodePath
@export var enter_method: String
@export var exit_method: String

func _ready() -> void:
	# connect body signals if not done in the editor
	if not is_connected("body_entered", Callable(self, "_on_body_entered")):
		connect("body_entered", Callable(self, "_on_body_entered"))
	if not is_connected("body_exited", Callable(self, "_on_body_exited")):
		connect("body_exited", Callable(self, "_on_body_exited"))

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"): # safer than 'body is Player' unless you have a class
		if node_path == NodePath(""):
			push_error("Trigger node path empty")
			return
		var node = get_node_or_null(node_path)
		if node == null:
			push_error("Trigger couldn't get node")
			return
		if node.has_method(enter_method):
			node.call(enter_method)
		else:
			push_error("Trigger node missing method: %s" % enter_method)

func _on_body_exited(body: Node) -> void:
	if body.is_in_group("player"):
		if node_path == NodePath(""):
			push_error("Trigger node path empty")
			return
		var node = get_node_or_null(node_path)
		if node == null:
			push_error("Trigger couldn't get node")
			return
		if node.has_method(exit_method):
			node.call(exit_method)
		else:
			push_error("Trigger node missing method: %s" % exit_method)
