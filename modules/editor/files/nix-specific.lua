-- Regular Nix-managed editor profile, loaded after shared.lua.
-- All profiles are Nix-managed; this one owns file-editing plugins and music.
vim.opt.number = true
vim.opt.relativenumber = false
vim.opt.signcolumn = "yes"
vim.opt.scrolloff = 8
vim.opt.wrap = true
vim.opt.linebreak = true

-- Bootstrap lazy.nvim only in the regular editor, never in the tree menu.
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.uv.fs_stat(lazypath) then
  vim.fn.system({ "git", "clone", "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git", "--branch=stable", lazypath })
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup({
  { "nvim-treesitter/nvim-treesitter", build = ":TSUpdate" },
  { "nvim-telescope/telescope.nvim", branch = "0.1.x",
    dependencies = { "nvim-lua/plenary.nvim" },
    keys = {
      { "<leader>ff", "<cmd>Telescope find_files<cr>" },
      { "<leader>fg", "<cmd>Telescope live_grep<cr>" },
      { "<leader>fb", "<cmd>Telescope buffers<cr>" },
    },
  },
  { "lewis6991/gitsigns.nvim",
    config = function() require("gitsigns").setup() end,
  },
  { "stevearc/oil.nvim",
    lazy = false,
    config = function()
      require("oil").setup({
        default_file_explorer = true,
        view_options = { show_hidden = true },
        keymaps = {
          ["gp"] = { desc = "Music: play under cursor",
            callback = function() require("music").play_under_cursor() end },
          ["<CR>"] = { desc = "Open item; play audio files",
            callback = function() require("music").open_or_play_under_cursor() end },
        },
      })
    end,
    keys = {
      { "-", "<cmd>Oil<cr>", desc = "Open parent directory" },
    },
  },
}, { checker = { enabled = false } })

-- Music player global controls remain exclusive to the regular editor.
local function m(fn) return function() require("music")[fn]() end end
vim.keymap.set("n", "<leader>mm", m("resume"),         { desc = "Music: resume last" })
vim.keymap.set("n", "<leader>m<space>", m("pause"),    { desc = "Music: pause" })
vim.keymap.set("n", "<leader>mn", m("next_track"),     { desc = "Music: next" })
vim.keymap.set("n", "<leader>mN", m("prev_track"),     { desc = "Music: prev" })
vim.keymap.set("n", "<leader>ms", m("toggle_shuffle"), { desc = "Music: shuffle" })
vim.keymap.set("n", "<leader>mr", m("cycle_loop"),     { desc = "Music: loop mode" })
vim.keymap.set("n", "<leader>mx", m("stop"),           { desc = "Music: stop" })
vim.keymap.set("n", "<leader>mf", m("seek_fwd"),       { desc = "Music: +5s" })
vim.keymap.set("n", "<leader>mb", m("seek_back"),      { desc = "Music: -5s" })

vim.api.nvim_create_user_command("Music", function(opts)
  require("music").start(opts.args)
end, { nargs = "?", complete = "dir" })
