extends SceneTree

const MaterialCatalogSupport = preload("res://tools/material_catalog_support.gd")
const FIXTURE_MANIFEST := "res://tests/fixtures/material_catalog/manifest.json"
const EXPECTED_MATERIAL_NAME := "dspre_mat_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
const EXPECTED_ASSET_PATH := "res://tests/fixtures/material_catalog/synthetic.glb"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var expectation_result := MaterialCatalogSupport.collect_expectations([FIXTURE_MANIFEST])
	if not bool(expectation_result.get("ok", false)):
		_fail(String(expectation_result.get("error", "Fixture expectations failed.")))
		return
	var expected_materials := expectation_result.get("expected_materials", {}) as Dictionary
	var asset_materials := expectation_result.get("asset_materials", {}) as Dictionary
	if not expected_materials.has(EXPECTED_MATERIAL_NAME):
		_fail("Fixture material key was not collected.")
		return
	if not asset_materials.has(EXPECTED_ASSET_PATH):
		_fail("Fixture GLB path was not collected.")
		return
	var expected_asset_materials := asset_materials[EXPECTED_ASSET_PATH] as Dictionary
	if expected_asset_materials.size() != 1 or not expected_asset_materials.has(EXPECTED_MATERIAL_NAME):
		_fail("Fixture GLB material bindings are incorrect.")
		return

	var expected_material := _make_material(Color(1.0, 0.5, 0.25, 1.0))
	var matching_material := expected_material.duplicate(false) as StandardMaterial3D
	if not MaterialCatalogSupport.materials_equivalent(expected_material, matching_material):
		_fail("Equivalent material resources were rejected.")
		return
	matching_material.albedo_color = Color(0.5, 0.5, 0.25, 1.0)
	if MaterialCatalogSupport.materials_equivalent(expected_material, matching_material):
		_fail("A material property mismatch was accepted.")
		return
	matching_material = expected_material.duplicate(false) as StandardMaterial3D
	var mismatched_image := Image.create_empty(2, 2, false, Image.FORMAT_RGBA8)
	mismatched_image.fill(Color.BLUE)
	matching_material.albedo_texture = ImageTexture.create_from_image(mismatched_image)
	if MaterialCatalogSupport.materials_equivalent(expected_material, matching_material):
		_fail("A material texture mismatch was accepted.")
		return
	matching_material = expected_material.duplicate(false) as StandardMaterial3D
	var compressed_image := (expected_material.albedo_texture as Texture2D).get_image()
	if compressed_image.compress(Image.COMPRESS_S3TC) != OK:
		_fail("The compressed-texture regression fixture could not be created.")
		return
	matching_material.albedo_texture = ImageTexture.create_from_image(compressed_image)
	var stored_compressed_image := (matching_material.albedo_texture as Texture2D).get_image()
	if not stored_compressed_image.is_compressed():
		_fail("The compressed-texture regression fixture lost its compressed format.")
		return
	if not MaterialCatalogSupport.materials_equivalent(expected_material, matching_material):
		_fail("Equivalent compressed and uncompressed textures were rejected.")
		return

	var root_node := Node3D.new()
	var mesh_instance := MeshInstance3D.new()
	var mesh := QuadMesh.new()
	mesh_instance.mesh = mesh
	root_node.add_child(mesh_instance)
	var null_surface_result := MaterialCatalogSupport.collect_scene_materials(root_node, true)
	if bool(null_surface_result.get("ok", false)):
		root_node.free()
		_fail("A null mesh surface material was accepted.")
		return
	mesh.material = expected_material
	var populated_surface_result := MaterialCatalogSupport.collect_scene_materials(root_node, true)
	root_node.free()
	if not bool(populated_surface_result.get("ok", false)):
		_fail(String(populated_surface_result.get("error", "Material-bearing mesh was rejected.")))
		return
	var populated_materials := populated_surface_result.get("materials", {}) as Dictionary
	if not populated_materials.has(EXPECTED_MATERIAL_NAME):
		_fail("Material-bearing mesh did not report its material key.")
		return

	print("MATERIAL_CATALOG_SUPPORT_OK ", JSON.stringify({
		"expected_materials": expected_materials.size(),
		"assets": asset_materials.size(),
		"null_surface_rejected": true,
		"content_mismatch_rejected": true,
		"compressed_texture_compared": true,
	}))
	quit(0)


func _make_material(color: Color) -> StandardMaterial3D:
	var image := Image.create_empty(2, 2, false, Image.FORMAT_RGBA8)
	image.fill(Color.RED)
	var material := StandardMaterial3D.new()
	material.resource_name = EXPECTED_MATERIAL_NAME
	material.albedo_color = color
	material.albedo_texture = ImageTexture.create_from_image(image)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
