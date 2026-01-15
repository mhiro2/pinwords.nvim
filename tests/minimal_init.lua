local cwd = vim.fn.getcwd()
local mini_path = vim.env.MINI_PATH or (cwd .. "/deps/mini.nvim")
local telescope_path = vim.env.TELESCOPE_PATH or (cwd .. "/deps/telescope.nvim")
local plenary_path = vim.env.PLUG_PATH or (cwd .. "/deps/plenary.nvim")

vim.opt.runtimepath:append(cwd)
vim.opt.runtimepath:append(mini_path)
vim.opt.runtimepath:append(plenary_path)
vim.opt.runtimepath:append(telescope_path)

package.path = table.concat({
  cwd .. "/?.lua",
  cwd .. "/?/init.lua",
  package.path,
}, ";")

vim.opt.swapfile = false
vim.opt.writebackup = false
vim.opt.shortmess:append("W")

local MiniTest = require("mini.test")
MiniTest.setup({
  execute = {
    reporter = MiniTest.gen_reporter.stdout(),
  },
})
