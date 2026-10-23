local MiniTest = require("mini.test")
local helpers = require("tests.test_helpers")
local selection = require("pinwords.commands.selection")

local T = helpers.create_test_set()

T["selection matches only aligned visual ranges"] = function()
  helpers.setup_buffer({ "foo", "bar" })
  helpers.set_visual_marks(2, 1, 2, 3)

  MiniTest.expect.equality(selection.matches_range({ range = 0, line1 = 2, line2 = 2 }), false)
  MiniTest.expect.equality(selection.matches_range({ range = 1, line1 = 1, line2 = 1 }), false)
  MiniTest.expect.equality(selection.matches_range({ range = 1, line1 = 2, line2 = 2 }), true)
end

T["PinWord pins a Visual selection but not the same lines typed as a range"] = function()
  helpers.setup_buffer({ "foo bar baz" })
  local pinwords = require("pinwords")

  helpers.feed_keys("vll:PinWord 1<CR>")
  MiniTest.expect.equality(pinwords.list()[1].raw, "foo")
  MiniTest.expect.equality(pinwords.list()[1].pattern, "\\V\\cfoo")

  -- The marks still cover line 1, but this range was typed, not taken from Visual mode.
  vim.api.nvim_win_set_cursor(0, { 1, 8 })
  helpers.feed_keys(":1,1PinWord 2<CR>")
  MiniTest.expect.equality(pinwords.list()[2].raw, "baz")
  MiniTest.expect.equality(pinwords.list()[2].pattern, "\\V\\c\\<baz\\>")

  -- A Visual-mode mapping that enters the command line behaves like typing ':'.
  -- Only part of "bar" is selected, so falling back to <cword> would be visible.
  vim.keymap.set("x", "<Plug>(pinwords-test)", ":PinWord 3<CR>")
  helpers.feed_keys("0wlvl<Plug>(pinwords-test)")
  vim.keymap.del("x", "<Plug>(pinwords-test)")
  MiniTest.expect.equality(pinwords.list()[3].raw, "ar")
end

T["PinWord keeps the Visual selection behind modifiers and nested commands"] = function()
  helpers.setup_buffer({ "foo bar baz" })
  local pinwords = require("pinwords")

  -- A helper that pins the selection from inside another command.
  package.loaded["pinwords_test_selection"] = {
    pin = function(slot)
      vim.cmd("'<,'>PinWord " .. slot)
    end,
  }

  local ok, err = pcall(function()
    -- Each case selects "ar" inside "bar" and then rewrites the command line.
    helpers.feed_keys("0wlvl:<C-u>silent '<,'>PinWord 1<CR>")
    helpers.feed_keys([[0wlvl:<C-u>lua vim.cmd("'<,'>PinWord 2")<CR>]])
    helpers.feed_keys([[0wlvl:<C-u>lua require("pinwords_test_selection").pin(3)<CR>]])
    -- Replacing the Visual range with a line range asks for the word under the cursor.
    helpers.feed_keys("0wlvl:<C-u>1,1PinWord 4<CR>")
  end)
  package.loaded["pinwords_test_selection"] = nil
  if not ok then
    error(err)
  end

  local slots = pinwords.list()
  MiniTest.expect.equality({ slots[1].raw, slots[2].raw, slots[3].raw, slots[4].raw }, { "ar", "ar", "ar", "bar" })
end

T["selection normalizes reversed marks"] = function()
  helpers.setup_buffer({ "foo bar baz" })
  helpers.set_visual_marks(1, 7, 1, 5)

  MiniTest.expect.equality(selection.get(), "bar")
end

T["selection handles multibyte byte ranges"] = function()
  helpers.setup_buffer({ "あいうえお" })
  helpers.set_visual_marks(1, 1, 1, 7)

  MiniTest.expect.equality(selection.get(), "あいう")
end

T["selection honors exclusive selection"] = function()
  helpers.setup_buffer({ "abc" })
  helpers.set_visual_marks(1, 1, 1, 3)

  local saved = vim.o.selection
  vim.o.selection = "exclusive"
  local ok, result = pcall(selection.get)
  vim.o.selection = saved

  MiniTest.expect.equality(ok, true)
  MiniTest.expect.equality(result, "ab")
end

T["selection extracts blockwise regions"] = function()
  helpers.setup_buffer({ "abcde", "fghij" })
  helpers.feed_normal([[ggl\<C-v>jll\<Esc>]])

  MiniTest.expect.equality(selection.get(), "bcd\nghi")
end

T["selection extracts linewise regions"] = function()
  helpers.setup_buffer({ "abcde", "fghij", "klmno" })
  helpers.feed_normal([[ggVj\<Esc>]])

  MiniTest.expect.equality(selection.get(), "abcde\nfghij")
end

return T
