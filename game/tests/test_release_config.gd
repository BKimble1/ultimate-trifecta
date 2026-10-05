extends RefCounted
## Final release sweep: what ships in the App Store build.
## - The export preset ships res://config/*.cfg (service endpoints, links):
##   they aren't Godot resources, so without the include filter the game
##   would run with the service off even after the owner configures it.
##   (tools/export_ios.sh also checks the exported pack.)
## - Development and test code stays out of the export.
## - One marketing version everywhere (workflow, project, export preset).
## - The privacy and support links come from the bundled config/links.cfg
##   (https only), falling back to the service; nothing is invented.
var t


func _preset() -> ConfigFile:
	var cf := ConfigFile.new()
	t.eq(cf.load("res://export_presets.cfg"), OK, "export preset loads")
	return cf


func test_config_files_ship_and_dev_code_does_not() -> void:
	var cf := _preset()
	var inc := String(cf.get_value("preset.0", "include_filter", ""))
	var exc := String(cf.get_value("preset.0", "exclude_filter", ""))
	t.eq(String(cf.get_value("preset.0", "platform", "")), "iOS", "preset 0 is the iOS export")
	t.check("config/*.cfg" in inc.split(","), "config/*.cfg ships (include_filter %s)" % inc)
	for d in ["tests/*", "tools/*", "src/dev/*"]:
		t.check(d in exc.split(","), "%s is excluded from the export" % d)
	for f in ["res://config/service.cfg", "res://config/links.cfg"]:
		var c := ConfigFile.new()
		t.eq(c.load(f), OK, "%s parses" % f)


func test_one_marketing_version_everywhere() -> void:
	var proj := String(ProjectSettings.get_setting("application/config/version", ""))
	var cf := _preset()
	var preset := String(cf.get_value("preset.0.options", "application/short_version", ""))
	var yml := FileAccess.get_file_as_string("res://../.github/workflows/ios.yml")
	var m := RegEx.create_from_string("MARKETING_VERSION: \"([0-9.]+)\"").search(yml)
	t.check(m != null, "the workflow sets MARKETING_VERSION")
	t.eq(preset, proj, "export preset short_version matches the project version")
	if m != null:
		t.eq(m.get_string(1), proj, "workflow MARKETING_VERSION matches the project version")


func test_links_are_bundled_https_only_and_never_invented() -> void:
	var c := ConfigFile.new()
	c.load("res://config/links.cfg")
	for k in ["privacy_url", "support_url"]:
		var v := String(c.get_value("links", k, ""))
		t.check(v == "" or v.begins_with("https://"), "%s is empty or an https link" % k)
	AppLinks.override({"privacy_url": "https://example.org/privacy", "support_url": "http://insecure.example"})
	t.eq(AppLinks.get_link("privacy_url"), "https://example.org/privacy", "a bundled https link is used")
	t.eq(AppLinks.get_link("support_url"), Cloud.link("support_url"), "a non-https value is ignored (service fallback)")
	AppLinks.override({})
	t.eq(AppLinks.get_link("privacy_url"), Cloud.link("privacy_url"), "unset: the service's link or nothing")
	AppLinks.reset()
