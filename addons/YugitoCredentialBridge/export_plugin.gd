@tool
extends EditorPlugin

var export_plugin: AndroidExportPlugin

func _enter_tree():
    export_plugin = AndroidExportPlugin.new()
    add_export_plugin(export_plugin)

func _exit_tree():
    if export_plugin != null:
        remove_export_plugin(export_plugin)
    export_plugin = null

class AndroidExportPlugin extends EditorExportPlugin:
    var _plugin_name = "YugitoCredentialBridge"

    func _supports_platform(platform):
        return platform is EditorExportPlatformAndroid

    func _get_android_libraries(platform, debug):
        return PackedStringArray([_plugin_name + "/bin/release/YugitoCredentialBridge-release.aar"])

    func _get_android_dependencies(platform, debug):
        return PackedStringArray([
            "androidx.credentials:credentials:1.6.0",
            "androidx.credentials:credentials-play-services-auth:1.6.0",
            "com.google.android.libraries.identity.googleid:googleid:1.2.0"
        ])

    func _get_name():
        return _plugin_name
