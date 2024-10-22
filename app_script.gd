extends VBoxContainer

var dir:DirAccess
#var origin_dir_access:DirAccess
var origin_dir:String 
var destination_dir:String
var material_folders:PackedStringArray
var materials_for_sending:PackedStringArray
@onready var preview_mesh:MeshInstance3D = $SplitContainer/AspectRatioContainer/SubViewportContainer/SubViewport/Node3D/PreviewMesh
var material_processing_started := false
var material_sending_started := false
@onready var import_progress_bar := $HBoxContainer2/HBoxContainer/ImportProgressBar
@onready var sending_progress_bar := $HBoxContainer2/HBoxContainer3/SendingProgressBar
@onready var material_container := load("res://material_container.tscn")
@onready var material_containers_area := $SplitContainer/ScrollContainer/HFlowContainer
var all_selected:bool = false

var key_words:Dictionary = {
	"basecolor": "albedo_texture",
	"-color": "albedo_texture",
	"_color": "albedo_texture",
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
	"ambientocclusion": "ao_texture"
}

@onready var mutex := Mutex.new()
var threads:Array

#@onready var thread := Thread.new()



class MyThread:
	
	var thread : Thread
	var semaphore : Semaphore
	var inner_mutex : Mutex
	var stop_thread := false
	var function:Callable
	var result
	var task_completed := false
	
	
	func _init(mutex:Mutex = null) -> void:
		thread = Thread.new()
		semaphore = Semaphore.new()
		thread.start(thread_cycle.bind(semaphore))
		inner_mutex = Mutex.new()
		
	
	func thread_cycle(semaphore:Semaphore): # inner code should probably not have await
		while true:
			semaphore.wait()
			if stop_thread:break
			
			inner_mutex.lock()
			result = self.function.call()
			inner_mutex.unlock()
			
			task_completed = true
	
	
	func get_result():
		if task_completed:
			task_completed = false
			return result
		else:
			print("Task is not completed.")
			
	func kill() -> void:
		stop_thread = true
		semaphore.post()
	
	func give_task(task:Callable):
		function = task
		semaphore.post()
		
		

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	for i in range(0, OS.get_processor_count()/2):
		threads.append(MyThread.new())
		
	#thread.start(prnti)

func give_task_to_a_thread(task:Callable):
	for t in threads:
		if !t.is_alive():
			if t.is_started():
				t.wait_to_finish()
			t.start(task)
			
			
func load_preview_image(folder_name, material_array):
	var image := Image.load_from_file(origin_dir + "/.preview_images/" + folder_name + ".jpg")
	mutex.lock()
	material_array[1] = ImageTexture.create_from_image(image)
	mutex.unlock()
	

var materials:Array[Array]
var current_material := ""


func _process(delta: float) -> void:
	
	materials = materials.filter(func(e):return e != [null])
	
	if material_processing_started and material_folders.size() != 0:
		var folder_name:String
		var preview_texture
		var material_to_render
		var directory:String
		await RenderingServer.frame_post_draw
		for mat in materials:
			if mat == [null]:
				continue
			mutex.lock()
			folder_name = mat[0]
			preview_texture = mat[1]
			material_to_render = mat[2]
			mutex.unlock()
			
			directory = origin_dir + "/" + folder_name
			var files := DirAccess.get_files_at(directory)
			
			if is_preview_image_exists(folder_name):
				if preview_texture == null:
					give_task_to_a_thread(load_preview_image.bind(folder_name, mat))
					mat[1] = 1
				elif preview_texture is int and preview_texture == 1:# rendering
					pass
				else:
					create_material_node(preview_texture, folder_name)
					mat = [null]
			
			else:
				
				if material_to_render == null:
					give_task_to_a_thread(import_material.bind(folder_name, directory, files, mat))
					
					mat[2] = 1
				elif material_to_render is int and material_to_render == 1: # rendering
					pass
				else:
					
					preview_mesh.mesh.surface_set_material(0, material_to_render)
					preview_texture = await get_pbr_material_texture()
					
					
					mat[1] = preview_texture
					give_task_to_a_thread(save_image_in_a_folder.bind(folder_name, preview_texture.get_image()))
					
					
			
		
		#folder_name = material_folders[import_progress_bar.value]
		#directory = origin_dir + "/" + folder_name
		#var files := DirAccess.get_files_at(directory)
		#
		#
		#
		#if is_folder_has_albedo(files, folder_name):
			#if !is_preview_image_exists(folder_name):
				#import_material(folder_name, directory, files, [])
				#save_pbr_material_image(folder_name)
			#else:
				#var image := Image.load_from_file(origin_dir + "/.preview_images/" + folder_name + ".jpg")
				#create_material_node(ImageTexture.create_from_image(image), folder_name)
		#import_progress_bar.value += 1
		#if import_progress_bar.value == import_progress_bar.max_value:
			#material_processing_started = false
			#enable_buttons()


	elif material_sending_started and materials_for_sending.size() != 0:
		var material_name := materials_for_sending[sending_progress_bar.value]
		DirAccess.make_dir_absolute(destination_dir+ '/' + material_name)
		var files_for_sending := DirAccess.get_files_at(origin_dir + '/' + material_name )
		
		for file in files_for_sending:
			DirAccess.copy_absolute(origin_dir + '/' + material_name + '/' + file, destination_dir + '/' + material_name + '/' + file)
		#print(files_for_sending)
		
		
		sending_progress_bar.value += 1
		if sending_progress_bar.value == sending_progress_bar.max_value:
			material_sending_started = false
			enable_buttons()

func _on_open_origin_button_up() -> void:
	$OriginFileDialog.popup()
	#var s = OS.shell_open(OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS))
	#print(dir.get_directories())
func _on_origin_dir_selected(dir: String) -> void:
	origin_dir = dir
	$HBoxContainer/OriginLineEdit.text = origin_dir
	material_folders = DirAccess.get_directories_at(origin_dir)
	materials.clear()
	await DirAccess.make_dir_absolute(origin_dir + "/.preview_images")
	for folder_name in material_folders:
		var directory:String = origin_dir + "/" + folder_name
		var files := DirAccess.get_files_at(directory)
		if is_folder_has_albedo(files, folder_name):
			materials.append([folder_name, null, null])
	import_progress_bar.value = 0
	import_progress_bar.max_value = materials.size()
	for c in $SplitContainer/ScrollContainer/HFlowContainer.get_children():
		c.queue_free()
	disable_buttons()
	material_processing_started = true
	
		

func disable_buttons():
	$HBoxContainer/OriginButton.disabled = true
	$HBoxContainer2/HBoxContainer3/SendingButton.disabled = true
	
func enable_buttons():
	$HBoxContainer/OriginButton.disabled = false
	$HBoxContainer2/HBoxContainer3/SendingButton.disabled = false

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
	
func import_material(folder_name:String, directory:String, files:PackedStringArray, array:Array):
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
	for file in files:
		map_type = find_map_type(file.replace(folder_name, "-"))
		if map_type != '':
			maps[map_type] = file
	
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
					
				"heightmap_texture":
					#preview_material.heightmap_enabled = true
					#preview_material.heightmap_scale = 10
					#preview_material.heightmap_texture = ImageTexture.create_from_image(image)
					pass # height does not work with triplanar mapping

	
	preview_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS_ANISOTROPIC
	preview_material.uv1_triplanar = true
	preview_material.uv1_scale = Vector3(0.5, 0.5, 0.5)
	array[2] = preview_material

func save_image_in_a_folder(folder_name, image:Image):
	image.save_jpg(origin_dir+"/.preview_images/" + folder_name + ".jpg" )

func get_pbr_material_texture():
	await RenderingServer.frame_post_draw
	return $SplitContainer/AspectRatioContainer/SubViewportContainer/SubViewport.get_texture()

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
	material_containers_area.add_child(container)
	container.find_child("ColorRect").texture = new_texture
	container.find_child("Label").text = folder_name
	container.custom_minimum_size = Vector2($GridContainer/HSlider.value,0)
	
	


func _on_size_slider_value_changed(value: float) -> void:
	
	var material_containers = $SplitContainer/ScrollContainer/HFlowContainer.get_children()
	if material_containers.size() > 0:
		for c in material_containers:
			c.custom_minimum_size = Vector2(value, 0)
	pass # Replace with function body.
	
func select_material(container:PanelContainer):
	var material_name:String = container.find_child("Label").text
	var directory := origin_dir + "/" + material_name
	var files := DirAccess.get_files_at(directory)
	import_material(material_name, directory, files, [])


func _on_all_select_button_up() -> void:
	if !all_selected:
		all_selected = true
		for child in $SplitContainer/ScrollContainer/HFlowContainer.get_children():
			child.find_child("CheckBox").button_pressed = true
	elif all_selected:
		all_selected = false
		for child in $SplitContainer/ScrollContainer/HFlowContainer.get_children():
			child.find_child("CheckBox").button_pressed = false
			


func _on_sending_button_up() -> void:
	if DirAccess.dir_exists_absolute(destination_dir) and \
	DirAccess.dir_exists_absolute(origin_dir) and destination_dir != "" and \
	$SplitContainer/ScrollContainer/HFlowContainer.get_children().size() > 0:
	
		materials_for_sending.clear()
		for child in $SplitContainer/ScrollContainer/HFlowContainer.get_children():
			if child.find_child("CheckBox").button_pressed == true:
				materials_for_sending.append(child.find_child("Label").text)
		if materials_for_sending.size() > 0:
			material_sending_started = true
			sending_progress_bar.value = 0
			sending_progress_bar.max_value = materials_for_sending.size()
			disable_buttons()


func _on_stop_importing_button_up() -> void:
	material_processing_started = false
	enable_buttons()


func _on_stop_sending_button_up() -> void:
	material_sending_started = false
	enable_buttons()


func _on_search_text_edit_text_changed() -> void:
	if $GridContainer/SearchTextEdit.text != "":
		for child in $SplitContainer/ScrollContainer/HFlowContainer.get_children():
			if child.find_child("Label").text.containsn($GridContainer/SearchTextEdit.text):
				child.visible = true
				
			else:
				child.visible = false
	else:
		for child in $SplitContainer/ScrollContainer/HFlowContainer.get_children():
			child.visible = true
			
			
func _exit_tree() -> void:
	for t in threads:
		t.kill()
