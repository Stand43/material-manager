extends PanelContainer

@onready var app := get_tree().get_root().get_node("App")
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


var waiting_for_image = false
var image_loading_thread: Thread
var new_material

func _process(delta: float) -> void:
	
	if waiting_for_image:
		if !image_loading_thread.is_alive() and image_loading_thread.is_started():
			new_material = image_loading_thread.wait_to_finish()
			app.preview_mesh.mesh.surface_set_material(0, new_material.duplicate())
			app.viewport_container.modulate = Color(1, 1, 1, 1)
			app.enable_buttons()
			waiting_for_image = false
			new_material = null # fixing memory leak by removing reference
			image_loading_thread = null # fixing memory leak by removing reference



func _on_focus_entered() -> void:
	if !app.material_sending_started and !app.material_processing_started:
		image_loading_thread = Thread.new()
		var mat = app.MaterialStatusTracker.new($VBoxContainer/Label.text) # dummy
		var directory: String = app.origin_dir + "/" + mat.folder_name
		var files := DirAccess.get_files_at(directory)
		
		image_loading_thread.start(app.import_material.bind(mat, directory, files))
		app.viewport_container.modulate = Color(1, 1, 1, 0.6)
		app.disable_buttons()
		waiting_for_image = true
		

	
	
