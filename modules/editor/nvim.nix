{ config, pkgs, ... }:

{
  home.file.".config/nvim/init.lua".text = ''
    vim.g.mapleader = " "
    vim.opt.clipboard = "unnamedplus"
    vim.opt.number = true
    vim.opt.relativenumber = false
    vim.opt.expandtab = true
    vim.opt.shiftwidth = 2
    vim.opt.tabstop = 2
    vim.opt.smartindent = true
    vim.opt.termguicolors = true
    vim.opt.signcolumn = "yes"
    vim.opt.updatetime = 250
    vim.opt.scrolloff = 8
    vim.opt.ignorecase = true
    vim.opt.smartcase = true
    vim.opt.wrap = true
    vim.opt.linebreak = true

    -- Keymaps
    vim.keymap.set("n", "<leader>p", "0P")

    -- Bootstrap lazy.nvim
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
    }, { checker = { enabled = false } })

    -- Colorscheme
    vim.cmd.colorscheme("default")
    local hl = vim.api.nvim_set_hl
    hl(0, "Normal", { bg = "#000000", fg = "#e4e4e4" })
    hl(0, "NormalFloat", { bg = "#0a0a0a", fg = "#e4e4e4" })
    hl(0, "CursorLine", { bg = "#0a0a0a" })
    hl(0, "LineNr", { fg = "#808080" })
    hl(0, "Comment", { fg = "#808080", italic = true })
    hl(0, "String", { fg = "#5fff87" })
    hl(0, "Keyword", { fg = "#ffffff", bold = true })
  '';
}
