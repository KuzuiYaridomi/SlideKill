# PathFollowMover.gd (attach to PathFollow3D)
extends PathFollow3D

@export var speed: float = 2.0  # world units / second

func _process(delta):
	var parent = get_parent()
	var baked_len := 1.0
	if parent and parent is Path3D and parent.curve:
		baked_len = parent.curve.get_baked_length()
		if baked_len <= 0.0:
			baked_len = 1.0

	if "offset" in self:
		# offset is distance along curve
		self.offset = (self.offset + speed * delta) % baked_len
	elif "unit_offset" in self:
		# unit_offset is 0..1 along curve
		var inc = (speed * delta) / baked_len
		self.unit_offset = fmod(self.unit_offset + inc, 1.0)
	else:
		# fallback: move a little in world space if neither prop exists
		translate(Vector3(0, 0, speed * delta))
