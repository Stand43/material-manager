extends VBoxContainer

var dir:DirAccess
var origin_dir:String 
var destination_dir:String
var origin_folders:PackedStringArray
var materials_for_sending:Array[MaterialStatusTracker]
@onready var preview_mesh:MeshInstance3D = $SplitContainer.find_child('PreviewMesh')
var is_processing_materials := false
var is_sending_materials := false
@onready var import_progress_bar := $HBoxContainer2/HBoxContainer/ImportProgressBar
@onready var sending_progress_bar := $HBoxContainer2/HBoxContainer3/SendingProgressBar
@onready var material_container := load("res://material_container.tscn")
@onready var material_containers_parent := $SplitContainer/ScrollContainer/HFlowContainer
var all_selected:bool = false
@onready var viewport_container := $SplitContainer.find_child('SubViewportContainer')
@onready var uv_slider := $SplitContainer/VSplitContainer/MarginContainer/VBoxContainer/UVScaleContainer/UVScaleSlider

var key_words:Dictionary = {
	"basecolor": "albedo_texture",
	"_col": "albedo_texture",
	"-col": "albedo_texture",
	"albedo": "albedo_texture",
	"basemap": "albedo_texture",
	"diffuse": "albedo_texture",
	"-diff": "albedo_texture",
	"_diff": "albedo_texture",
	" diff": "albedo_texture",
	
	"-emit": "emission_texture",
	"_emit": "emission_texture",
	" emit": "emission_texture",
	"emission": "emission_texture",
	"emissive": "emission_texture",
	
	"-normal": "normal_texture",
	"_normal": "normal_texture",
	" normal": "normal_texture",
	"normalgl": "normal_texture",
	"-nor": "normal_texture",
	"_nor": "normal_texture",
	"-nrm": "normal_texture",
	"_nrm": "normal_texture",
	"normalmap": "normal_texture",
	
	"-orm": "orm_texture",
	"-arm": "orm_texture",
	"_orm": "orm_texture",
	"_arm": "orm_texture",
	" orm": "orm_texture",
	" arm": "orm_texture",
	
	"_height": "heightmap_texture",
	"-height": "heightmap_texture",
	"heightmap": "heightmap_texture",
	"displacement": "heightmap_texture",
	"_disp": "heightmap_texture",
	"-disp": "heightmap_texture",
	
	"roughness": "roughness_texture",
	"-rough": "roughness_texture",
	"_rough": "roughness_texture",
	" rough": "roughness_texture",
	"specular": "roughness_texture",
	
	"metallic": "metallic_texture",
	"metalness": "metallic_texture",
	"-metal": "metallic_texture",
	"_metal": "metallic_texture",
	" metal": "metallic_texture",
	
	"-ao": "ao_texture",
	"_ao": "ao_texture",
	" ao": "ao_texture",
	"ambientocclusion": "ao_texture",
}

@onready var mutex := Mutex.new()
var threads:Array

class MyThread:
	
	var thread : Thread
	var semaphore : Semaphore
	var inner_mutex : Mutex
	var stop_thread := false
	var function:Callable
	var result
	var task_completed := true
	
	func _init(mutex:Mutex = null) -> void:
		thread = Thread.new()
		semaphore = Semaphore.new()
		thread.start(thread_cycle.bind())
		inner_mutex = Mutex.new()
		

	func thread_cycle(): # inner code should probably not have await
		while true:
			semaphore.wait()
			if stop_thread:break
			
			
			inner_mutex.lock()
			result = self.function.call()
			inner_mutex.unlock()
			task_completed = true
	
	func is_not_busy():
		return task_completed
	
	func get_result():
		if task_completed:
			task_completed = false
			return result
		else:
			print("Task is not completed.")
			
	func kill() -> void:
		stop_thread = true
		semaphore.post()
		thread.wait_to_finish()
	
	func give_task(task:Callable):
		function = task
		task_completed = false
		semaphore.post()


enum {
	IMPORTING_MATERIAL,
	LOADING_PREVIEW_IMAGE,
	IMAGE_EXISTS_AND_PREVIEW_IMAGE_LOADED,
	MATERIAL_READY,
	SAVING_IMAGE,
	NEW_PREVIEW_IMAGE_CREATED,
	DONE
}

class MaterialStatusTracker:
	
	var status: int = -1
	var folder_name: String
	var material_to_render: StandardMaterial3D
	var preview_texture
	
	func _init(folder:String = '') -> void:
		folder_name = folder



func give_task_to_a_thread(task:Callable) -> bool:
	for t in threads:
		if t.is_not_busy():
			t.give_task(task)
			return true
	return false
			
func is_free_threads_available() -> bool:
	for t in threads:
		if t.is_not_busy():
			return true
	return false



var materials:Array
const MAX_PROCESSED_MATERIALS_PER_FRAME = 20
var processed_materials_count := 0


func _process(delta: float) -> void:
	
	if is_processing_materials:
		var object_to_remove = null
		var directory: String
		var files: PackedStringArray
		
		# making size of preview window fixed to 512px
		$SplitContainer.split_offset = $SplitContainer.size.x - 512
		
		for mat in materials:
			directory = origin_dir + "/" + mat.folder_name
			files = DirAccess.get_files_at(directory)
			match mat.status:
				-1:
					if is_preview_image_exists(mat.folder_name):
						var success := give_task_to_a_thread(load_preview_image.bind(mat))
						if success:
							mat.status = LOADING_PREVIEW_IMAGE
				
					else:
						var success = give_task_to_a_thread(
									import_material.bind(mat, directory, files)
									)
						if success:
							mat.status = IMPORTING_MATERIAL
				
				IMPORTING_MATERIAL: continue
				LOADING_PREVIEW_IMAGE: continue
					
				IMAGE_EXISTS_AND_PREVIEW_IMAGE_LOADED:
					create_material_node(mat.preview_texture, mat.folder_name)
					mat.status = DONE
				
				MATERIAL_READY:
					preview_mesh.mesh.surface_set_material(0, mat.material_to_render)
					mat.preview_texture = ImageTexture.create_from_image(
								(await get_pbr_material_texture()).get_image()
								)
					create_material_node(mat.preview_texture, mat.folder_name)
					mat.status = NEW_PREVIEW_IMAGE_CREATED
					break # to do a cycle
					
				NEW_PREVIEW_IMAGE_CREATED:
					var success = give_task_to_a_thread(save_image_in_a_folder.bind(mat))
					if success:
						mat.status = SAVING_IMAGE
				DONE:
					object_to_remove = mat
					import_progress_bar.value += 1
					break
			
			processed_materials_count += 1
			if processed_materials_count == MAX_PROCESSED_MATERIALS_PER_FRAME:
				processed_materials_count = 0
				break
						
		materials.erase(object_to_remove)
		
		
		# importing finished
		if import_progress_bar.value >= import_progress_bar.max_value:
			is_processing_materials = false
			sort_containers()
			enable_buttons()
			clear_threads()
		

	elif is_sending_materials:
		var object_to_remove = null
		for mat in materials_for_sending:
			match mat.status:
				-1:
					DirAccess.make_dir_absolute(destination_dir+ '/' + mat.folder_name)
					var files_for_sending := DirAccess.get_files_at(origin_dir + '/' + mat.folder_name )
					var success = give_task_to_a_thread(copy_files.bind(files_for_sending, mat))
					mat.status = SAVING_IMAGE
				
				SAVING_IMAGE: continue
				
				DONE:
					object_to_remove = mat
					sending_progress_bar.value += 1
					break
				
		materials_for_sending.erase(object_to_remove)
		
		# sending finished
		if sending_progress_bar.value == sending_progress_bar.max_value:
			is_sending_materials = false
			sort_containers()
			enable_buttons()
			clear_threads()


func clear_threads():
	for t in threads:
		t.kill()
	threads.clear()

func sort_containers(): # sort material preview containers
	var containers := material_containers_parent.get_children()
	var labels: PackedStringArray
	for c in containers:
		labels.append(c.find_child("Label").text)
	labels.sort()
	for l in labels:
		for c in containers:
			if c.find_child("Label").text == l:
				material_containers_parent.move_child(c, -1)
				break
		

func copy_files(files_for_sending, mat):
	for file in files_for_sending:
		DirAccess.copy_absolute(origin_dir + '/' + mat.folder_name + '/' + file, 
			destination_dir + '/' + mat.folder_name + '/' + file)
	mat.status = DONE


func load_preview_image(mat_object):
	var image := Image.load_from_file(origin_dir + "/.preview_images/" + mat_object.folder_name + ".jpg")
	mat_object.preview_texture = ImageTexture.create_from_image(image)
	mat_object.status = IMAGE_EXISTS_AND_PREVIEW_IMAGE_LOADED


func _on_open_origin_button_up() -> void:
	$OriginFileDialog.popup()


var no_albedo_folders := ''
func check_origin_folder_for_materials():
	$HBoxContainer/OriginLineEdit.text = origin_dir
	if origin_dir == '':
		OS.alert('Origin folder path is empty.')
		return
	
	origin_folders = DirAccess.get_directories_at(origin_dir)
	if origin_folders.size() > 0:
		materials.clear()
		await DirAccess.make_dir_absolute(origin_dir + "/.preview_images")
		
		no_albedo_folders = ''
		for folder_name in origin_folders:
			var files := DirAccess.get_files_at(origin_dir + "/" + folder_name)
			if is_folder_has_albedo(files, folder_name):
				materials.append(MaterialStatusTracker.new(folder_name))
			elif folder_name != '.preview_images':
				no_albedo_folders +='- ' + folder_name + '\n'
	


func _on_origin_dir_selected(dir: String) -> void:
	origin_dir = dir
	
	check_origin_folder_for_materials()

	if no_albedo_folders != '':
		var text := "Could not find color texture in these folders:\n\n"
		OS.alert(text + no_albedo_folders)
				
		
	


func disable_buttons():
	$HBoxContainer/OriginButton.disabled = true
	$HBoxContainer2/HBoxContainer3/SendingButton.disabled = true
	$HBoxContainer2/HBoxContainer/StartImporting.disabled = true
	
func enable_buttons():
	$HBoxContainer/OriginButton.disabled = false
	$HBoxContainer2/HBoxContainer3/SendingButton.disabled = false
	$HBoxContainer2/HBoxContainer/StartImporting.disabled = false


func _on_open_destination_button_up() -> void:
	$DestinationFileDialog.popup()


func _on_destination_dir_selected(dir: String) -> void:
	destination_dir = dir
	$HBoxContainer/DestinationLineEdit.text = destination_dir


func is_folder_has_albedo(files:PackedStringArray, origin_folder_name: String):
	for file in files:
		if find_map_type(file.replace(origin_folder_name, "-")) == "albedo_texture":
			return true
	return false


func import_material(mat_object:MaterialStatusTracker, directory:String, files:PackedStringArray):
	var map_type:String
	var preview_material := StandardMaterial3D.new()
	var image:Image
	var maps := {
		"albedo_texture":"",
		"normal_texture":"",
		"metallic_texture":"",
		"ao_texture":"",
		"roughness_texture":"",
		"emission_texture":"",
		"orm_texture":"",
		"heightmap_texture":"",
	}
	# find all texture maps of a material
	for file in files:
		map_type = find_map_type(file.replace(mat_object.folder_name, ""))
		if map_type != '':
			maps[map_type] = file
	
	# assign found maps to a material
	for map in maps:
		if maps[map] != "":
			image = Image.load_from_file(directory+ "/" +maps[map])
			match map:
				"": pass
				"albedo_texture":
					preview_material.albedo_texture = ImageTexture.create_from_image(image)
				"normal_texture":
					preview_material.normal_enabled = true
					preview_material.normal_texture = ImageTexture.create_from_image(image)
				"metallic_texture":
					preview_material.metallic = 1
					preview_material.metallic_texture = ImageTexture.create_from_image(image)
				"ao_texture":
					preview_material.ao_enabled = true
					preview_material.ao_texture = ImageTexture.create_from_image(image)
				"roughness_texture":
					preview_material.roughness_texture = ImageTexture.create_from_image(image)
				"emission_texture":
					preview_material.emission_enabled = true
					preview_material.emission_texture = ImageTexture.create_from_image(image)
				"orm_texture":
					var texture = ImageTexture.create_from_image(image)
					preview_material.ao_enabled = true
					preview_material.metallic = 1
					preview_material.ao_texture = texture
					preview_material.roughness_texture = texture
					preview_material.metallic_texture = texture
					
					preview_material.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
					preview_material.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
					preview_material.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_BLUE
					
				"heightmap_texture":# heightmaps do not work with triplanar mapping
					
					#preview_material.heightmap_enabled = true
					#preview_material.heightmap_scale = 10
					#preview_material.heightmap_texture = ImageTexture.create_from_image(image)
					pass 

	
	preview_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS_ANISOTROPIC
	preview_material.uv1_triplanar = true
	preview_material.uv1_scale = Vector3(0.5, 0.5, 0.5)
	mat_object.material_to_render = preview_material
	mat_object.status = MATERIAL_READY
	return preview_material


func save_image_in_a_folder(mat:MaterialStatusTracker):
	mat.preview_texture.get_image().save_jpg(
		origin_dir+"/.preview_images/" + mat.folder_name + ".jpg" 
		)
	mat.status = DONE


func get_pbr_material_texture():
	await RenderingServer.frame_post_draw
	return $SplitContainer/VSplitContainer/AspectRatioContainer/SubViewportContainer/SubViewport.get_texture()


func save_pbr_material_image(folder_name):
	await RenderingServer.frame_post_draw
	var rendered_image = $SplitContainer/AspectRatioContainer/SubViewportContainer/SubViewport.get_texture().get_image()
	create_material_node(ImageTexture.create_from_image(rendered_image), folder_name)
	rendered_image.save_jpg(origin_dir+"/.preview_images/" + folder_name + ".jpg" )
	

func find_map_type(file_name:String) -> String:
	for word in key_words:
		if file_name.findn(word) != -1:
			return key_words[word]
	return ""


func is_preview_image_exists(folder_name) -> bool:
	for file in DirAccess.get_files_at(origin_dir + "/.preview_images"):
		if file == folder_name + ".jpg":
			return true
	return false


func create_material_node(new_texture:Texture2D, folder_name:String):
	var container:PanelContainer = material_container.instantiate()
	container.find_child("Label").tooltip_text = folder_name
	material_containers_parent.add_child(container)
	container.find_child("ColorRect").texture = new_texture 
	container.find_child("Label").text = folder_name
	container.custom_minimum_size = Vector2($GridContainer/HSlider.value,0)


func _on_size_slider_value_changed(value: float) -> void:
	
	var material_containers = material_containers_parent.get_children()
	if material_containers.size() > 0:
		for c in material_containers:
			c.custom_minimum_size = Vector2(value, 0)
			


func _on_all_select_button_up() -> void:
	if !all_selected:
		all_selected = true
		for child in material_containers_parent.get_children():
			child.find_child("CheckBox").button_pressed = true
	elif all_selected:
		all_selected = false
		for child in material_containers_parent.get_children():
			child.find_child("CheckBox").button_pressed = false



func _on_sending_button_up() -> void:
	if DirAccess.dir_exists_absolute(destination_dir) and \
	DirAccess.dir_exists_absolute(origin_dir) and destination_dir != "" and \
	material_containers_parent.get_children().size() > 0:
		materials_for_sending.clear()
		for i in range(0, OS.get_processor_count()):
				threads.append(MyThread.new())
		
		for child in material_containers_parent.get_children():
			if child.find_child("CheckBox").button_pressed == true:
				materials_for_sending.append(MaterialStatusTracker.new(
					child.find_child("Label").text)
					)
				
		is_sending_materials = true
		sending_progress_bar.value = 0
		sending_progress_bar.max_value = materials_for_sending.size()
		disable_buttons()


func _on_stop_importing_button_up() -> void:
	is_processing_materials = false
	clear_threads()
	enable_buttons()


func _on_stop_sending_button_up() -> void:
	is_sending_materials = false
	clear_threads()
	enable_buttons()


func _on_search_text_edit_text_changed() -> void:
	if $GridContainer/SearchTextEdit.text != "":
		for child in material_containers_parent.get_children():
			if child.find_child("Label").text.containsn($GridContainer/SearchTextEdit.text):
				child.visible = true
			else:
				child.visible = false
	else:
		for child in material_containers_parent.get_children():
			child.visible = true
			

func _exit_tree() -> void: # closing program
	for t in threads:
		t.kill()


@onready var original_rotation := preview_mesh.rotation
func _on_rotation_slider_value_changed(value: float) -> void:
	preview_mesh.rotation.y = original_rotation.y + value


func _on_uv_scale_slider_value_changed(value: float) -> void:
	preview_mesh.mesh.surface_get_material(0).uv1_scale = Vector3(value, value, value)

#normal map type switch
func _on_toggle_nm_button_button_up() -> void:
	var mat := preview_mesh.mesh.surface_get_material(0)
	mat.normal_scale = -(mat.normal_scale)


func _on_start_importing_button_up() -> void:
	if origin_dir == '': return
	check_origin_folder_for_materials()
	
	if materials.size() > 0:
		for i in range(0, OS.get_processor_count()):
			threads.append(MyThread.new())
		import_progress_bar.value = 0
		import_progress_bar.max_value = materials.size()
		for c in material_containers_parent.get_children():
			c.queue_free()
		disable_buttons()
		is_processing_materials = true
	else:
		OS.alert('No materials to import.')
