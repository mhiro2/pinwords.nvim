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

T["whole_word keeps matching text that starts or ends with a symbol"] = function()
  helpers.setup_buffer({ "x -foo y foo- z", "foobar" })

  local pinwords = require("pinwords")
  pinwords.set(1, { raw = "-foo", whole_word = true })
  pinwords.set(2, { raw = "foo-", whole_word = true })

  local m1 = helpers.find_match("PinWord1")
  MiniTest.expect.equality(m1.pattern, "\\V\\c-foo\\>")
  MiniTest.expect.equality(vim.fn.match("x -foo y", m1.pattern), 2)
  MiniTest.expect.equality(vim.fn.match("-foobar", m1.pattern), -1)

  local m2 = helpers.find_match("PinWord2")
  MiniTest.expect.equality(m2.pattern, "\\V\\c\\<foo-")
  MiniTest.expect.equality(vim.fn.match("y foo- z", m2.pattern), 2)
  MiniTest.expect.equality(vim.fn.match("xfoo-", m2.pattern), -1)
end

T["boundaries_of distinguishes a literal backslash-gt from a boundary marker"] = function()
  local pattern = require("pinwords.pattern")

  local with_boundary = pattern.build("foo", { whole_word = true, case_sensitive = true })
  local left, right = pattern.boundaries_of("foo", with_boundary)
  MiniTest.expect.equality({ left, right }, { true, true })

  -- Pinning `foo\>` ends the escaped body in `\\>`, which must not be read as a
  -- trailing boundary marker.
  local literal = pattern.build("foo\\>", { whole_word = true, case_sensitive = true })
  left, right = pattern.boundaries_of("foo\\>", literal)
  MiniTest.expect.equality({ left, right }, { true, false })

  -- Same in the other direction for a leading `\<`.
  local literal_left = pattern.build("\\<foo", { whole_word = true, case_sensitive = true })
  left, right = pattern.boundaries_of("\\<foo", literal_left)
  MiniTest.expect.equality({ left, right }, { false, true })
end

return T
