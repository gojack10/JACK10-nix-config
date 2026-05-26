-- music: oil-driven mpv frontend
-- entry: require("music").start(cwd)

local M = {}

local state_dir = vim.fn.stdpath("state") .. "/music"
local state_file = state_dir .. "/state.json"
local socket = state_dir .. "/mpv.sock"

local AUDIO_EXT = {
  mp3 = true, flac = true, wav = true, ogg = true,
  m4a = true, opus = true, aac = true, wma = true, mka = true,
}

local state = {
  cwd = vim.fn.expand("~/Music"),
  current = nil,
  shuffle = true,
  loop_mode = "folder", -- "off" | "one" | "folder"
  stopped = false,      -- explicit stops should not prompt on next launch
}

local mpv_job = nil
local playback_generation = 0

-- ── HUD state ────────────────────────────────────────────────────────────────

local hud = {
  visible = false,
  paused = false,
  pos = 0,
  duration = 0,
  title = "",
}

local ipc_client = nil
local ipc_buf = ""

local hud_buf = nil
local hud_win = nil

local function reset_hud()
  hud.visible = false
  hud.paused = false
  hud.pos = 0
  hud.duration = 0
  hud.title = ""
end

-- ── State persistence ────────────────────────────────────────────────────────

local function ensure_dir()
  vim.fn.mkdir(state_dir, "p")
end

local function save_state()
  ensure_dir()
  local f = io.open(state_file, "w")
  if f then
    f:write(vim.fn.json_encode(state))
    f:close()
  end
end

local function load_state()
  local f = io.open(state_file, "r")
  if not f then return end
  local content = f:read("*a")
  f:close()
  local ok, loaded = pcall(vim.fn.json_decode, content)
  if ok and type(loaded) == "table" then
    for k, v in pairs(loaded) do state[k] = v end
  end
end

-- ── Filesystem helpers ───────────────────────────────────────────────────────

local function is_audio(path)
  local ext = path:match("%.([^.]+)$")
  return ext and AUDIO_EXT[ext:lower()] or false
end

local function scan_folder(folder)
  local files = {}
  local handle = vim.loop.fs_scandir(folder)
  if not handle then return files end
  while true do
    local name, t = vim.loop.fs_scandir_next(handle)
    if not name then break end
    if t == "file" and is_audio(name) then
      table.insert(files, folder .. "/" .. name)
    end
  end
  table.sort(files)
  return files
end

local function shuffle_inplace(t)
  for i = #t, 2, -1 do
    local j = math.random(i)
    t[i], t[j] = t[j], t[i]
  end
end

-- ── HUD formatting ───────────────────────────────────────────────────────────

local PARTIAL_BLOCKS = {
  [1] = "\u{258F}", [2] = "\u{258E}", [3] = "\u{258D}", [4] = "\u{258C}",
  [5] = "\u{258B}", [6] = "\u{258A}", [7] = "\u{2589}",
}

local function build_bar(filled, total, width)
  width = width or 20
  if not total or total <= 0 then return string.rep("\u{2591}", width) end
  local pct = math.max(0, math.min(filled / total, 1))
  local eighths = math.floor(pct * width * 8 + 0.5)
  local full = math.floor(eighths / 8)
  local rem = eighths % 8
  local empty = width - full - (rem > 0 and 1 or 0)
  return string.rep("\u{2588}", full)
    .. (rem > 0 and PARTIAL_BLOCKS[rem] or "")
    .. string.rep("\u{2591}", empty)
end

local function fmt_time(s)
  if not s or s < 0 then return "0:00" end
  local m = math.floor(s / 60)
  local sec = math.floor(s % 60)
  return string.format("%d:%02d", m, sec)
end

local function leader_name()
  local l = vim.g.mapleader
  if l == nil or l == "" or l == "\\" then return "\\" end
  if l == " " then return "space" end
  return l
end

local function truncate(s, max)
  if not s then return "" end
  if #s <= max then return s end
  return s:sub(1, max - 1) .. "\u{2026}"
end

-- Nerd Font Material Design icons (requires a nerd font in the terminal)
local ICONS = {
  playing  = "\u{F0759}", -- nf-md-music_note
  paused   = "\u{F03E4}", -- nf-md-pause
  shuffle  = "\u{F049D}", -- nf-md-shuffle
  loop     = "\u{F0456}", -- nf-md-repeat
  loop_one = "\u{F0457}", -- nf-md-repeat_once
}

local function loop_glyph()
  if state.loop_mode == "one" then return ICONS.loop_one end
  if state.loop_mode == "folder" then return ICONS.loop end
  return ""
end

local function bindings_items()
  local L = leader_name()
  local mp = L .. "-m+"
  return {
    "<CR>:play",
    "-:up",
    "gp:folder",
    mp .. "space:pause",
    mp .. "n:next",
    mp .. "N:prev",
    mp .. "s:shuffle",
    mp .. "r:loop",
    mp .. "x:stop",
    mp .. "f/b:seek",
  }
end

local function wrap_items(items, width, sep)
  sep = sep or "  "
  local lines, current = {}, ""
  for _, item in ipairs(items) do
    if current == "" then
      current = item
    elseif vim.fn.strdisplaywidth(current .. sep .. item) <= width then
      current = current .. sep .. item
    else
      table.insert(lines, current)
      current = item
    end
  end
  if current ~= "" then table.insert(lines, current) end
  if #lines == 0 then lines = { "" } end
  return lines
end

local function now_playing_line(width)
  local icon = hud.paused and ICONS.paused or ICONS.playing
  local flags = {}
  if state.shuffle then table.insert(flags, ICONS.shuffle) end
  local lg = loop_glyph()
  if lg ~= "" then table.insert(flags, lg) end
  local flagstr = #flags > 0 and ("  " .. table.concat(flags, " ")) or ""
  local times = string.format("%s / %s", fmt_time(hud.pos), fmt_time(hud.duration))
  -- reserve space for icon + bar + times + flags, give rest to title
  local bar_w = math.min(20, math.max(8, math.floor(width / 4)))
  local bar = build_bar(hud.pos, hud.duration, bar_w)
  local fixed = vim.fn.strdisplaywidth(string.format("%s   %s  %s%s", icon, bar, times, flagstr)) + 2
  local title_max = math.max(8, width - fixed)
  local title = truncate(hud.title ~= "" and hud.title or "(untitled)", title_max)
  return string.format("%s %s  %s  %s%s", icon, title, bar, times, flagstr)
end

local function ensure_hud_window()
  if hud_buf == nil or not vim.api.nvim_buf_is_valid(hud_buf) then
    hud_buf = vim.api.nvim_create_buf(false, true)
    vim.bo[hud_buf].bufhidden = "hide"
    vim.bo[hud_buf].buftype = "nofile"
    vim.bo[hud_buf].swapfile = false
    vim.bo[hud_buf].filetype = "music_hud"
  end
  if hud_win and vim.api.nvim_win_is_valid(hud_win) then return end
  local cur = vim.api.nvim_get_current_win()
  vim.cmd("noautocmd topleft 1split")
  hud_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(hud_win, hud_buf)
  vim.wo[hud_win].number = false
  vim.wo[hud_win].relativenumber = false
  vim.wo[hud_win].cursorline = false
  vim.wo[hud_win].signcolumn = "no"
  vim.wo[hud_win].statuscolumn = ""
  vim.wo[hud_win].winfixheight = true
  vim.wo[hud_win].wrap = false
  vim.wo[hud_win].list = false
  vim.wo[hud_win].foldcolumn = "0"
  vim.wo[hud_win].statusline = "%#NonText#" .. string.rep("\u{2500}", 200)
  if vim.api.nvim_win_is_valid(cur) then
    vim.api.nvim_set_current_win(cur)
  end
end

local function render_hud()
  ensure_hud_window()
  if not (hud_buf and vim.api.nvim_buf_is_valid(hud_buf)) then return end
  local width = math.max(20, vim.o.columns - 2)
  local lines = wrap_items(bindings_items(), width)
  if hud.visible and hud.duration > 0 then
    table.insert(lines, now_playing_line(width))
  end
  vim.bo[hud_buf].modifiable = true
  vim.api.nvim_buf_set_lines(hud_buf, 0, -1, false, lines)
  vim.bo[hud_buf].modifiable = false
  if hud_win and vim.api.nvim_win_is_valid(hud_win) then
    vim.api.nvim_win_set_height(hud_win, #lines)
  end
end

local function redraw_hud()
  vim.schedule(render_hud)
end

-- ── mpv IPC ──────────────────────────────────────────────────────────────────

local function close_pipe(pipe)
  pcall(function()
    if pipe and not pipe:is_closing() then pipe:close() end
  end)
end

local function mpv_send(cmd)
  -- Talk to the socket even when mpv_job is nil: after :luafile/reload, or when
  -- a previous Neovim died, the process may still be controllable via IPC.
  if not vim.loop.fs_stat(socket) then return false end
  local payload = vim.fn.json_encode({ command = cmd }) .. "\n"
  local client = vim.loop.new_pipe(false)
  client:connect(socket, function(err)
    if err then close_pipe(client); return end
    client:write(payload, function() close_pipe(client) end)
  end)
  return true
end

local function ere_escape(s)
  return (s:gsub("([][(){}.^$*+?\\|])", "\\%1"))
end

local function kill_orphan_mpv()
  if vim.fn.executable("pkill") ~= 1 then return end
  local pattern = "mpv.*" .. ere_escape("--input-ipc-server=" .. socket)
  vim.fn.jobstart({ "pkill", "-TERM", "-f", pattern }, { detach = true })
end

local function handle_ipc_event(line)
  local ok, ev = pcall(vim.fn.json_decode, line)
  if not ok or type(ev) ~= "table" then return end
  if ev.event == "property-change" then
    if ev.name == "time-pos" and type(ev.data) == "number" then
      hud.pos = ev.data
      hud.visible = true
    elseif ev.name == "duration" and type(ev.data) == "number" then
      hud.duration = ev.data
    elseif ev.name == "media-title" and type(ev.data) == "string" then
      hud.title = ev.data
    elseif ev.name == "pause" then
      hud.paused = (ev.data == true)
    elseif ev.name == "path" and type(ev.data) == "string" then
      state.current = ev.data
      state.stopped = false
      save_state()
    end
    redraw_hud()
  elseif ev.event == "end-file" or ev.event == "shutdown" then
    if ev.event == "shutdown" then
      hud.visible = false
      redraw_hud()
    end
  end
end

local function stop_ipc()
  if ipc_client then
    pcall(function() ipc_client:read_stop() end)
    pcall(function() ipc_client:close() end)
    ipc_client = nil
  end
  ipc_buf = ""
end

local SUB_PAYLOAD = table.concat({
  '{"command":["observe_property",1,"time-pos"]}',
  '{"command":["observe_property",2,"duration"]}',
  '{"command":["observe_property",3,"media-title"]}',
  '{"command":["observe_property",4,"pause"]}',
  '{"command":["observe_property",5,"path"]}',
}, "\n") .. "\n"

local function start_ipc()
  stop_ipc()
  ipc_client = vim.loop.new_pipe(false)
  ipc_client:connect(socket, function(err)
    if err then
      pcall(function() ipc_client:close() end)
      ipc_client = nil
      return
    end
    ipc_client:write(SUB_PAYLOAD)
    ipc_client:read_start(function(rerr, data)
      if rerr or not data then return end
      vim.schedule(function()
        ipc_buf = ipc_buf .. data
        while true do
          local nl = ipc_buf:find("\n")
          if not nl then break end
          local line = ipc_buf:sub(1, nl - 1)
          ipc_buf = ipc_buf:sub(nl + 1)
          if line ~= "" then handle_ipc_event(line) end
        end
      end)
    end)
  end)
end

-- ── Playback ─────────────────────────────────────────────────────────────────

local function stop_mpv(opts)
  opts = opts or {}
  if opts.cancel_pending ~= false then
    playback_generation = playback_generation + 1
  end

  local had_socket = vim.loop.fs_stat(socket) ~= nil
  stop_ipc()
  if had_socket then
    mpv_send({ "quit" })
  end
  if mpv_job then
    pcall(vim.fn.jobstop, mpv_job)
    mpv_job = nil
  end
  if opts.kill_orphans and had_socket then
    kill_orphan_mpv()
  end
  vim.fn.delete(socket)
  reset_hud()
  if opts.mark_stopped then
    state.stopped = true
    save_state()
  end
  redraw_hud()
end

local function spawn_mpv(playlist)
  ensure_dir()
  vim.fn.delete(socket)
  reset_hud()
  hud.visible = true
  local args = {
    "mpv",
    "--no-config",                 -- ignore ~/.config/mpv keep-open/resume settings
    "--no-video",
    "--input-terminal=no",
    "--keep-open=no",
    "--resume-playback=no",
    "--save-position-on-quit=no",
    "--input-ipc-server=" .. socket,
    "--msg-level=all=no",
    "--really-quiet",
  }
  if state.loop_mode == "one" then
    table.insert(args, "--loop-file=inf")
  end
  if state.loop_mode == "folder" then
    table.insert(args, "--loop-playlist=inf")
  end
  for _, p in ipairs(playlist) do table.insert(args, p) end
  local job_id
  job_id = vim.fn.jobstart(args, {
    detach = false,
    on_exit = function(_, code)
      if mpv_job ~= job_id then return end
      mpv_job = nil
      stop_ipc()
      reset_hud()
      if code == 0 then
        state.stopped = true
        save_state()
      end
      redraw_hud()
    end,
  })
  mpv_job = job_id
  if mpv_job <= 0 then
    mpv_job = nil
    reset_hud()
    vim.notify("failed to start mpv", vim.log.levels.ERROR)
    redraw_hud()
    return
  end
  -- give mpv a moment to create the socket
  vim.defer_fn(start_ipc, 300)
  redraw_hud()
end

local function start_mpv(playlist)
  playback_generation = playback_generation + 1
  local generation = playback_generation
  stop_mpv({ cancel_pending = false, kill_orphans = true })
  -- Starting immediately after replacing a track can leave the old mpv alive
  -- with an unlinked socket; delay slightly so quit/jobstop/pkill wins first.
  vim.defer_fn(function()
    if generation == playback_generation then
      spawn_mpv(playlist)
    end
  end, 450)
end

local function play_file(path)
  if not is_audio(path) then
    vim.notify("not an audio file: " .. vim.fn.fnamemodify(path, ":t"), vim.log.levels.WARN)
    return false
  end
  local folder = vim.fn.fnamemodify(path, ":h")
  local files = scan_folder(folder)
  if #files == 0 then
    vim.notify("no audio in " .. folder, vim.log.levels.WARN)
    return false
  end
  local rest = {}
  for _, f in ipairs(files) do
    if f ~= path then table.insert(rest, f) end
  end
  if state.shuffle then shuffle_inplace(rest) end
  local playlist = { path }
  for _, f in ipairs(rest) do table.insert(playlist, f) end
  state.current = path
  state.stopped = false
  save_state()
  start_mpv(playlist)
  return true
end

local function play_folder(folder)
  local files = scan_folder(folder)
  if #files == 0 then
    vim.notify("no audio in " .. folder, vim.log.levels.WARN)
    return false
  end
  if state.shuffle then shuffle_inplace(files) end
  state.current = files[1]
  state.stopped = false
  save_state()
  start_mpv(files)
  return true
end

local function cursor_target()
  local ok, oil = pcall(require, "oil")
  if ok then
    local entry = oil.get_cursor_entry()
    local dir = oil.get_current_dir()
    if entry and dir then
      return dir .. entry.name, entry.type
    end
  end
  local f = vim.fn.expand("<cfile>")
  if f == "" then return nil, nil end
  local abs = vim.fn.fnamemodify(f, ":p")
  return abs, vim.fn.isdirectory(abs) == 1 and "directory" or "file"
end

-- ── Public API ───────────────────────────────────────────────────────────────

function M.play_under_cursor()
  local path, kind = cursor_target()
  if not path then return end
  if kind == "directory" then
    play_folder(path:gsub("/$", ""))
  else
    play_file(path)
  end
end

function M.open_or_play_under_cursor()
  local path, kind = cursor_target()
  if not path then return end
  if kind == "file" and is_audio(path) then
    play_file(path)
    return
  end
  local ok, actions = pcall(function() return require("oil.actions") end)
  if ok then
    actions.select.callback()
  else
    vim.cmd("edit " .. vim.fn.fnameescape(path))
  end
end

function M.pause() mpv_send({ "cycle", "pause" }) end
function M.next_track() mpv_send({ "playlist-next" }) end
function M.prev_track() mpv_send({ "playlist-prev" }) end
function M.seek_fwd() mpv_send({ "seek", 5 }) end
function M.seek_back() mpv_send({ "seek", -5 }) end

function M.stop()
  stop_mpv({ mark_stopped = true, kill_orphans = true })
end

function M.toggle_shuffle()
  state.shuffle = not state.shuffle
  save_state()
  redraw_hud()
end

function M.cycle_loop()
  local next_mode = ({ off = "one", one = "folder", folder = "off" })[state.loop_mode] or "off"
  state.loop_mode = next_mode
  mpv_send({ "set_property", "loop-file", next_mode == "one" and "inf" or "no" })
  mpv_send({ "set_property", "loop-playlist", next_mode == "folder" and "inf" or "no" })
  save_state()
  redraw_hud()
end

function M.resume()
  load_state()
  if state.current and vim.fn.filereadable(state.current) == 1 then
    play_file(state.current)
  else
    vim.notify("nothing to resume", vim.log.levels.WARN)
  end
end

function M.start(cwd)
  load_state()
  math.randomseed(os.time())
  if cwd and cwd ~= "" then
    state.cwd = vim.fn.fnamemodify(cwd, ":p")
  end

  local ok = pcall(function() require("oil").open(state.cwd) end)
  if not ok then
    vim.cmd("edit " .. vim.fn.fnameescape(state.cwd))
  end

  local group = vim.api.nvim_create_augroup("MusicPlayer", { clear = true })

  vim.api.nvim_create_autocmd("FileType", {
    group = group,
    pattern = { "oil", "netrw" },
    callback = function(ev)
      local opts = { buffer = ev.buf, silent = true, nowait = true }
      vim.keymap.set("n", "gp", M.play_under_cursor, opts)
    end,
  })

  vim.api.nvim_create_autocmd("VimResized", {
    group = group,
    callback = render_hud,
  })

  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = function()
      save_state()
      stop_mpv({ kill_orphans = true })
    end,
  })

  render_hud()

  if state.current and not state.stopped and vim.fn.filereadable(state.current) == 1 then
    vim.defer_fn(function()
      local name = vim.fn.fnamemodify(state.current, ":t")
      local choice = vim.fn.confirm("resume " .. name .. "?", "&Yes\n&No", 1)
      if choice == 1 then M.resume() end
    end, 100)
  end
end

return M
