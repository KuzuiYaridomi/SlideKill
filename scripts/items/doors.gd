extends Node3D

func open():
	$AnimationPlayer.play("doors_open")
	
func close():
	$AnimationPlayer.play_backwards("doors_open")
