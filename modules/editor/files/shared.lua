-- Shared Neovim preferences. Both the regular Nix editor and tree menu load
-- this first; plugins and session-management behavior belong to their profiles.
vim.g.mapleader = " "
vim.opt.clipboard = "unnamedplus"
vim.opt.expandtab = true
vim.opt.shiftwidth = 2
vim.opt.tabstop = 2
vim.opt.smartindent = true
vim.opt.termguicolors = true
vim.opt.updatetime = 250
vim.opt.ignorecase = true
vim.opt.smartcase = true

vim.keymap.set("n", "<leader>p", "0P")

-- Expand the command token only, not a filename or search containing W.
-- Using native :w preserves its arguments, bang, and buffer-specific save hooks.
vim.cmd([[cnoreabbrev <expr> W getcmdtype() == ':' && getcmdline() ==# 'W' ? 'w' : 'W']])

-- Common theme; each profile owns its context-specific display overrides.
vim.cmd.colorscheme("default")
local hl = vim.api.nvim_set_hl
hl(0, "Normal", { bg = "#000000", fg = "#e4e4e4", ctermbg = 0, ctermfg = 7 })
hl(0, "NormalFloat", { bg = "#0a0a0a", fg = "#e4e4e4", ctermbg = 0, ctermfg = 7 })
hl(0, "CursorLine", { bg = "#0a0a0a" })
hl(0, "LineNr", { fg = "#808080" })
hl(0, "Comment", { fg = "#808080", italic = true })
hl(0, "String", { fg = "#5fff87" })
hl(0, "Keyword", { fg = "#ffffff", bold = true })
