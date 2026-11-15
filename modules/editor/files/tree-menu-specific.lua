-- Tree-menu-specific profile, applied to the session buffer after shared.lua.
-- The launcher keeps regular-editor plugins out; scripts/tmux-oil owns session
-- identity, editing, save reconciliation, polling, and navigation callbacks.
vim.bo.buftype = "acwrite"
vim.bo.filetype = "tmux-oil"
vim.bo.swapfile = false
vim.bo.undofile = false
vim.bo.modified = false
vim.wo.wrap = false
vim.wo.cursorline = true
vim.wo.cursorlineopt = "line"
vim.opt.laststatus = 0

local hl = vim.api.nvim_set_hl
hl(0, "CursorLine", { bg = "#4f5258", ctermbg = 8 })
hl(0, "TmuxOilMeta", { fg = "#e4e4e4", ctermfg = 7 })
hl(0, "TmuxOilGreen", { fg = "#5fff87", ctermfg = 10 })
hl(0, "TmuxOilYellow", { fg = "#ffff00", ctermfg = 11 })
hl(0, "TmuxOilRed", { fg = "#ff5f5f", ctermfg = 9 })
hl(0, "TmuxOilClaude", { fg = "#d77757", ctermfg = 173 })
