local MiniTest = require("mini.test")
local helpers = require("tests.test_helpers")

local T = helpers.create_test_set()

T["pattern matches special characters literally"] = function()
  helpers.setup_buffer({ "foo.bar" })

  local pinwords = require("pinwords")
  local cases = {
    { raw = "foo.bar", hit = "x foo.bar y", misses = { "x fooXbar y" } },
    { raw = "foo*bar", hit = "x foo*bar y", misses = { "x foobar y", "x fooobar y" } },
    { raw = "a\\b", hit = "x a\\b y", misses = { "x ab y", "x a\bb y" } },
    { raw = "foo\rbar", hit = "x foo\rbar y", misses = { "x foorbar y", "x foo\\rbar y" } },
  }

  for slot, case in ipairs(cases) do
    pinwords.set(slot, { raw = case.raw })

    local match = helpers.find_match("PinWord" .. slot)
    MiniTest.expect.equality(vim.fn.match(case.hit, match.pattern), 2)
    for _, miss in ipairs(case.misses) do
      MiniTest.expect.equality(vim.fn.match(miss, match.pattern), -1)
    end
  end
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
