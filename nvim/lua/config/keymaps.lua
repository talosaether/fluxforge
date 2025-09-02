-- yank to clipboard
vim.keymap.set({"n", "v"}, "<leader>y", [["+y]], { desc = "Yank to Clipboard" })

-- black python formatting
vim.keymap.set("n", "<leader>fmp", ":silent !black %<cr>")

-- Center screen when jumping
vim.keymap.set("n", "n", "nzzzv", { desc = "Next search result (centered)" })
vim.keymap.set("n", "N", "Nzzzv", {  desc = "Previous search result (centered)" })
vim.keymap.set("n", "<C-d>", "<C-d>zz", {  desc = "Half page down (centered)" })
vim.keymap.set("n", "<C-u>", "<C-u>zz", {  desc = "Half page up (centered)" })

-- Buffer navigation
vim.keymap.set("n", "<leader>n", ":bn<CR>", { desc = "Buffer Next" })
vim.keymap.set("n", "<leader>p", ":bp<CR>", { desc = "Buffer Previous" })
vim.keymap.set("n", "<leader>x", ":bd<CR>", { desc = "Buffer Delete" })

-- Better window navigation
vim.keymap.set("n", "<C-h>", ":wincmd h<CR>", {  desc = "Move to left window" })
vim.keymap.set("n", "<C-j>", ":wincmd j<CR>", {  desc = "Move to bottom window" })
vim.keymap.set("n", "<C-k>", ":wincmd k<CR>", {  desc = "Move to top window" })
vim.keymap.set("n", "<C-l>", ":wincmd l<CR>", {  desc = "Move to right window" })

-- Splitting & Resizing
vim.keymap.set("n", "<leader>sv", "<Cmd>vsplit<CR>", {  desc = "Split window vertically" })
vim.keymap.set("n", "<leader>sh", "<Cmd>split<CR>", {  desc = "Split window horizontally" })
vim.keymap.set("n", "<C-up>", "<Cmd>resize +2<CR>", {  desc = "Increase window height" })
vim.keymap.set("n", "<C-Down>", "<Cmd>resize -2<CR>", {  desc = "Decrease window height" })
vim.keymap.set("n", "<C-Left>", "<Cmd>vertical resize -2<CR>", {  desc = "Decrease window width" })
vim.keymap.set("n", "<C-Right>", "<Cmd>vertical resize +2<CR>", {  desc = "Increase window width" })

-- Better indenting in visual mode
vim.keymap.set("v", "<", "<gv", {  desc = "Indent left and reselect" })
vim.keymap.set("v", ">", ">gv", {  desc = "Indent right and reselect" })

-- Better J behavior
vim.keymap.set("n", "J", "mzJ`z", {  desc = "Join lines and keep cursor position" })

-- Quick config editing
vim.keymap.set("n", "<leader>rc", "<Cmd>e ~/.config/nvim/init.lua<CR>", {  desc = "Edit config" })

-- File Explorer
vim.keymap.set("n", "<leader>m", "<Cmd>NvimTreeFocus<CR>", { desc="Focus on File Explorer" })
vim.keymap.set("n", "<leader>e", "<Cmd>NvimTreeToggle<CR>", { desc="Toggle File Explorer" })

