extends PanelContainer

@onready var app := get_tree().get_root().get_node("App")
@onready var uv_slider = app.uv_slider
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


var waiting_for_image = false
var image_loading_thread: Thread
var new_material

func _process(delta: float) -> void:
	
	if waiting_for_image: # when this container was pressed
		# if processing completed       and      loading was started
		if !image_loading_thread.is_alive() and image_loading_thread.is_started():
			new_material = image_loading_thread.wait_to_finish()
			new_material.uv1_scale = Vector3(uv_slider.value, uv_slider.value, uv_slider.value)
			app.preview_mesh.mesh.surface_set_material(0, new_material.duplicate())
			app.viewport_container.modulate = Color(1, 1, 1, 1) # full color
			app.enable_buttons()
			waiting_for_image = false
			new_material = null # fixing memory leak by removing reference
			image_loading_thread = null # fixing memory leak by removing reference



func _on_focus_entered() -> void:
	if !app.is_sending_materials and !app.is_processing_materials:
		image_loading_thread = Thread.new()
		var mat = app.MaterialStatusTracker.new($VBoxContainer/Label.text) # dummy
		var directory: String = app.origin_dir + "/" + mat.folder_name
		var files := DirAccess.get_files_at(directory)
		
		image_loading_thread.start(app.import_material.bind(mat, directory, files))
		app.viewport_container.modulate = Color(1, 1, 1, 0.6) # a bit transparent while loading
		app.disable_buttons()
		waiting_for_image = true
		

	
	
