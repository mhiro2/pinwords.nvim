local MiniTest = require("mini.test")
local helpers = require("tests.test_helpers")

local T = helpers.create_test_set()

T["highlight blends with Normal background"] = function()
  local highlight = require("pinwords.highlight")

  -- Save original Normal highlight
  local orig_normal = vim.api.nvim_get_hl(0, { name = "Normal", link = false })

  vim.api.nvim_set_hl(0, "Normal", { bg = 0x000000 })
  helpers.clear_hl("PinWord1")
  highlight.apply(1)
  local dark_hl = vim.api.nvim_get_hl(0, { name = "PinWord1", link = false })

  vim.api.nvim_set_hl(0, "Normal", { bg = 0xffffff })
  helpers.clear_hl("PinWord1")
  highlight.apply(1)
  local light_hl = vim.api.nvim_get_hl(0, { name = "PinWord1", link = false })

  -- Restore original Normal highlight
  vim.api.nvim_set_hl(0, "Normal", orig_normal)

  MiniTest.expect.equality(type(dark_hl.bg) == "number", true)
  MiniTest.expect.equality(type(light_hl.bg) == "number", true)
  MiniTest.expect.equality(dark_hl.bg ~= light_hl.bg, true)
end

T["highlight does not overwrite user-defined PinWord groups"] = function()
  local highlight = require("pinwords.highlight")

  -- Set a custom highlight before applying
  local custom_color = 0xff0000 -- Red
  vim.api.nvim_set_hl(0, "PinWord1", { bg = custom_color, fg = 0x00ff00 })

  highlight.apply(3)

  -- Check that the custom highlight is preserved
  local hl = vim.api.nvim_get_hl(0, { name = "PinWord1", link = false })
  MiniTest.expect.equality(hl.bg, custom_color)
  MiniTest.expect.equality(hl.fg, 0x00ff00)

  -- Check that other PinWord groups were created
  local hl2 = vim.api.nvim_get_hl(0, { name = "PinWord2", link = false })
  MiniTest.expect.equality(type(hl2.bg) == "number", true)

  local hl3 = vim.api.nvim_get_hl(0, { name = "PinWord3", link = false })
  MiniTest.expect.equality(type(hl3.bg) == "number", true)

  -- Clean up custom highlight
  helpers.clear_hl("PinWord1")
  helpers.clear_hl("PinWord2")
  helpers.clear_hl("PinWord3")
end

T["highlight does not overwrite user-defined PinWordCword"] = function()
  local highlight = require("pinwords.highlight")

  -- Set a custom highlight for PinWordCword
  local custom_color = 0x00ff00 -- Green
  vim.api.nvim_set_hl(0, "PinWordCword", { bg = custom_color, underline = true })

  highlight.apply(1)

  -- Check that the custom highlight is preserved
  local hl = vim.api.nvim_get_hl(0, { name = "PinWordCword", link = false })
  MiniTest.expect.equality(hl.bg, custom_color)
  MiniTest.expect.equality(hl.underline, true)

  -- Clean up custom highlight
  helpers.clear_hl("PinWordCword")
end

T["highlight applies user-specified hex color"] = function()
  local highlight = require("pinwords.highlight")

  helpers.clear_hl("PinWord1")
  highlight.apply(1, { [1] = "#ff0000" })

  local hl = vim.api.nvim_get_hl(0, { name = "PinWord1", link = false })
  MiniTest.expect.equality(type(hl.bg) == "number", true)
  -- The color is blended with Normal bg, so we can't check exact value
  -- but it should be set

  helpers.clear_hl("PinWord1")
end

T["highlight applies user-specified table with bg"] = function()
  local highlight = require("pinwords.highlight")

  helpers.clear_hl("PinWord1")
  highlight.apply(1, { [1] = { bg = "#00ff00" } })

  local hl = vim.api.nvim_get_hl(0, { name = "PinWord1", link = false })
  MiniTest.expect.equality(type(hl.bg) == "number", true)

  helpers.clear_hl("PinWord1")
end

T["highlight applies user-specified bg and fg"] = function()
  local highlight = require("pinwords.highlight")

  helpers.clear_hl("PinWord1")
  -- When fg is specified, bg is not blended
  highlight.apply(1, { [1] = { bg = "#ff0000", fg = "#ffffff" } })

  local hl = vim.api.nvim_get_hl(0, { name = "PinWord1", link = false })
  MiniTest.expect.equality(hl.bg, 0xff0000)
  MiniTest.expect.equality(hl.fg, 0xffffff)

  helpers.clear_hl("PinWord1")
end

T["highlight applies style attributes"] = function()
  local highlight = require("pinwords.highlight")

  helpers.clear_hl("PinWord1")
  highlight.apply(1, { [1] = { bg = "#ff0000", bold = true, italic = true } })

  local hl = vim.api.nvim_get_hl(0, { name = "PinWord1", link = false })
  MiniTest.expect.equality(hl.bold, true)
  MiniTest.expect.equality(hl.italic, true)

  helpers.clear_hl("PinWord1")
end

T["highlight applies underline and strikethrough"] = function()
  local highlight = require("pinwords.highlight")

  helpers.clear_hl("PinWord1")
  highlight.apply(1, { [1] = { bg = "#ff0000", underline = true, strikethrough = true } })

  local hl = vim.api.nvim_get_hl(0, { name = "PinWord1", link = false })
  MiniTest.expect.equality(hl.underline, true)
  MiniTest.expect.equality(hl.strikethrough, true)

  helpers.clear_hl("PinWord1")
end

T["highlight applies cword color"] = function()
  local highlight = require("pinwords.highlight")

  helpers.clear_hl("PinWordCword")
  highlight.apply(1, { cword = "#00ffff" })

  local hl = vim.api.nvim_get_hl(0, { name = "PinWordCword", link = false })
  MiniTest.expect.equality(type(hl.bg) == "number", true)

  helpers.clear_hl("PinWordCword")
end

T["highlight applies cword with table spec"] = function()
  local highlight = require("pinwords.highlight")

  helpers.clear_hl("PinWordCword")
  highlight.apply(1, { cword = { bg = "#00ffff", fg = "#000000", bold = true } })

  local hl = vim.api.nvim_get_hl(0, { name = "PinWordCword", link = false })
  MiniTest.expect.equality(hl.bg, 0x00ffff)
  MiniTest.expect.equality(hl.fg, 0x000000)
  MiniTest.expect.equality(hl.bold, true)

  helpers.clear_hl("PinWordCword")
end

T["highlight defines PinWordFlash by default"] = function()
  local highlight = require("pinwords.highlight")

  helpers.clear_hl("PinWordFlash")
  highlight.apply(1)

  local hl = vim.api.nvim_get_hl(0, { name = "PinWordFlash", link = false })
  MiniTest.expect.equality(type(hl), "table")
  MiniTest.expect.equality(next(hl) ~= nil, true)

  helpers.clear_hl("PinWordFlash")
end

T["highlight applies sp (special color)"] = function()
  local highlight = require("pinwords.highlight")

  helpers.clear_hl("PinWord1")
  highlight.apply(1, { [1] = { sp = "#ff0000", underline = true } })

  local hl = vim.api.nvim_get_hl(0, { name = "PinWord1", link = false })
  MiniTest.expect.equality(hl.sp, 0xff0000)
  MiniTest.expect.equality(hl.underline, true)
  -- bg should not be set
  MiniTest.expect.equality(hl.bg, nil)

  helpers.clear_hl("PinWord1")
end

T["highlight applies undercurl style"] = function()
  local highlight = require("pinwords.highlight")

  helpers.clear_hl("PinWord1")
  highlight.apply(1, { [1] = { sp = "#54a0ff", undercurl = true } })

  local hl = vim.api.nvim_get_hl(0, { name = "PinWord1", link = false })
  MiniTest.expect.equality(hl.sp, 0x54a0ff)
  MiniTest.expect.equality(hl.undercurl, true)

  helpers.clear_hl("PinWord1")
end

T["highlight applies underdouble style"] = function()
  local highlight = require("pinwords.highlight")

  helpers.clear_hl("PinWord1")
  highlight.apply(1, { [1] = { sp = "#feca57", underdouble = true } })

  local hl = vim.api.nvim_get_hl(0, { name = "PinWord1", link = false })
  MiniTest.expect.equality(hl.sp, 0xfeca57)
  MiniTest.expect.equality(hl.underdouble, true)

  helpers.clear_hl("PinWord1")
end

T["highlight applies underdotted style"] = function()
  local highlight = require("pinwords.highlight")

  helpers.clear_hl("PinWord1")
  highlight.apply(1, { [1] = { sp = "#1dd1a1", underdotted = true } })

  local hl = vim.api.nvim_get_hl(0, { name = "PinWord1", link = false })
  MiniTest.expect.equality(hl.sp, 0x1dd1a1)
  MiniTest.expect.equality(hl.underdotted, true)

  helpers.clear_hl("PinWord1")
end

T["highlight applies underdashed style"] = function()
  local highlight = require("pinwords.highlight")

  helpers.clear_hl("PinWord1")
  highlight.apply(1, { [1] = { sp = "#5f27cd", underdashed = true } })

  local hl = vim.api.nvim_get_hl(0, { name = "PinWord1", link = false })
  MiniTest.expect.equality(hl.sp, 0x5f27cd)
  MiniTest.expect.equality(hl.underdashed, true)

  helpers.clear_hl("PinWord1")
end

T["highlight applies sp with bg combined"] = function()
  local highlight = require("pinwords.highlight")

  helpers.clear_hl("PinWord1")
  highlight.apply(1, { [1] = { bg = "#5f27cd", sp = "#ff6b6b", undercurl = true } })

  local hl = vim.api.nvim_get_hl(0, { name = "PinWord1", link = false })
  MiniTest.expect.equality(hl.sp, 0xff6b6b)
  MiniTest.expect.equality(hl.undercurl, true)
  MiniTest.expect.equality(type(hl.bg) == "number", true)

  helpers.clear_hl("PinWord1")
end

T["highlight uses default for unspecified slots"] = function()
  local highlight = require("pinwords.highlight")

  helpers.clear_hl("PinWord1")
  helpers.clear_hl("PinWord2")
  helpers.clear_hl("PinWord3")

  -- Only specify slot 2
  highlight.apply(3, { [2] = { bg = "#123456", fg = "#ffffff" } })

  -- Slot 2 should have custom color (not blended because fg is specified)
  local hl2 = vim.api.nvim_get_hl(0, { name = "PinWord2", link = false })
  MiniTest.expect.equality(hl2.bg, 0x123456)
  MiniTest.expect.equality(hl2.fg, 0xffffff)

  -- Slots 1 and 3 should have default (blended) colors
  local hl1 = vim.api.nvim_get_hl(0, { name = "PinWord1", link = false })
  local hl3 = vim.api.nvim_get_hl(0, { name = "PinWord3", link = false })
  MiniTest.expect.equality(type(hl1.bg) == "number", true)
  MiniTest.expect.equality(type(hl3.bg) == "number", true)

  helpers.clear_hl("PinWord1")
  helpers.clear_hl("PinWord2")
  helpers.clear_hl("PinWord3")
end

return T
