-- OBS Lua Script: VT Scene Switcher
-- Watches /tmp/vt-capture-scene for scene name changes and switches automatically.
-- Add via OBS: Tools > Scripts > + > select this file

obs = obslua

local SCENE_FILE = "/tmp/vt-capture-scene"
local last_scene = ""
local check_interval = 500 -- ms

function script_description()
    return "Auto-switches OBS scenes based on /tmp/vt-capture-scene file content.\nUsed with vt-capture.sh for VT/Sway recording."
end

function switch_scene()
    local f = io.open(SCENE_FILE, "r")
    if not f then return end

    local scene_name = f:read("*l")
    f:close()

    if not scene_name or scene_name == "" or scene_name == last_scene then
        return
    end

    local source = obs.obs_get_source_by_name(scene_name)
    if source then
        obs.obs_frontend_set_current_scene(source)
        obs.obs_source_release(source)
        last_scene = scene_name
    end
end

function script_load(settings)
    obs.timer_add(switch_scene, check_interval)
end

function script_unload()
    obs.timer_remove(switch_scene)
end
