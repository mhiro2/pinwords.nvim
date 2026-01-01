local MiniTest = require("mini.test")
local helpers = require("tests.test_helpers")

local T = helpers.create_test_set()

T["pattern with whole_word true uses word boundaries"] = function()
  helpers.setup_buffer({ "foo bar", "foobar" })

  require("pinwords").set(1, { whole_word = true })

  local match = helpers.find_match("PinWord1")
  MiniTest.expect.equality(match ~= nil, true)
  MiniTest.expect.equality(match.pattern:match("\\<") ~= nil, true)
  MiniTest.expect.equality(match.pattern:match("\\>") ~= nil, true)
end

T["pattern with whole_word false does not use word boundaries"] = function()
  helpers.setup_buffer({ "foo bar", "foobar" })

  require("pinwords").set(1, { whole_word = false })

  local match = helpers.find_match("PinWord1")
  MiniTest.expect.equality(match ~= nil, true)
  MiniTest.expect.equality(match.pattern:match("\\<"), nil)
end

T["pattern with case_sensitive true is case sensitive"] = function()
  helpers.setup_buffer({ "Foo bar", "foo baz" })

  require("pinwords").set(1, { case_sensitive = true })

  local match = helpers.find_match("PinWord1")
  MiniTest.expect.equality(match ~= nil, true)
  MiniTest.expect.equality(match.pattern:match("\\C") ~= nil, true)
end

T["pattern with case_sensitive false is case insensitive"] = function()
  helpers.setup_buffer({ "Foo bar", "foo baz" })

  require("pinwords").set(1, { case_sensitive = false })

  local match = helpers.find_match("PinWord1")
  MiniTest.expect.equality(match ~= nil, true)
  MiniTest.expect.equality(match.pattern:match("\\c") ~= nil, true)
end

T["pattern escapes special characters"] = function()
  helpers.setup_buffer({ "foo.bar", "foo*bar" })

  require("pinwords").set(1, { raw = "foo.bar" })

  local match = helpers.find_match("PinWord1")
  MiniTest.expect.equality(match ~= nil, true)
  -- Pattern should escape the dot
  MiniTest.expect.equality(match.pattern:match("foo%.bar") ~= nil, true)
end

T["pattern escapes newlines in multi-line text"] = function()
  helpers.setup_buffer({ "foo bar", "baz" })

  require("pinwords").set(1, { raw = "foo\nbar", whole_word = false })

  local match = helpers.find_match("PinWord1")
  MiniTest.expect.equality(match ~= nil, true)
  -- Pattern should escape newline
  MiniTest.expect.equality(match.pattern:match("\\n") ~= nil, true)
end

return T
