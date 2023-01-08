local util = require('neotest-haskell.util')
local lib = require('neotest.lib')

local M = {}

-- @param test_name: The name of the test for which to query for a parent
-- @return a treesitter query for a 'describe'
-- with a child test that matches 'test_name'
-- @type string
-- NOTE: This query does not detect parent 'describe's defined in another function thatn the child (TODO?)
local function mk_parent_query(test_name)
  local test_name_escaped = vim.fn.escape(test_name, '"')
  return string.format(
    [[
  ;; describe (unqualified) with child that matches test_name (multiple queries)
  ((exp_apply
    (exp_name (variable) @func_name)
    (exp_literal) @test.name
  ) (_ (_ (_ (exp_apply
    (exp_literal) @child_name
  ))))
  (#eq? @func_name "describe")
  (#eq? @child_name "%s")
  ) @test.definition

  ((exp_apply
    (exp_name (variable) @func_name)
    (exp_literal) @test.name
  ) (_ (_ (_ (_ (exp_apply
    (exp_literal) @child_name
  )))))
  (#eq? @func_name "describe")
  (#eq? @child_name "%s")
  ) @test.definition

  ((exp_apply
    (exp_name (variable) @func_name)
    (exp_literal) @test.name
  ) (_ (_ (_ (_ (_ (exp_apply
    (exp_literal) @child_name
  ))))))
  (#eq? @func_name "describe")
  (#eq? @child_name "%s")
  ) @test.definition

  ; describe (unqualified, no do notation) with child that matches test_name
  ((exp_apply
    (exp_name (variable) @func_name)
    (exp_literal) @test.name
  ) (exp_apply
    (exp_literal) @child_name
  )
  (#eq? @func_name "describe")
  (#eq? @child_name "%s")
  ) @test.definition

  ;; describe (qualified) with child that matches test_name (multiple queries)
  ((exp_apply
    (exp_name (qualified_variable (variable) @func_name))
    (exp_literal) @test.name
  ) (_ (_ (_ (exp_apply
    (exp_literal) @child_name
  ))))
  (#eq? @func_name "describe")
  (#eq? @child_name "%s")
  ) @test.definition

  ((exp_apply
    (exp_name (qualified_variable (variable) @func_name))
    (exp_literal) @test.name
  ) (_ (_ (_ (_ (exp_apply
    (exp_literal) @child_name
  )))))
  (#eq? @func_name "describe")
  (#eq? @child_name "%s")
  ) @test.definition


  ((exp_apply
    (exp_name (qualified_variable (variable) @func_name))
    (exp_literal) @test.name
  ) (_ (_ (_ (_ (_ (exp_apply
    (exp_literal) @child_name
  ))))))
  (#eq? @func_name "describe")
  (#eq? @child_name "%s")
  ) @test.definition


  ; describe (qualified, no do notation) with child that matches test_name
  ((exp_apply
    (exp_name (qualified_variable (variable) @func_name))
    (exp_literal) @test.name
  ) (exp_apply
    (exp_literal) @child_name
  )
  (#eq? @func_name "describe")
  (#eq? @child_name "%s")
  ) @test.definition
  ]],
    test_name_escaped,
    test_name_escaped,
    test_name_escaped,
    test_name_escaped,
    test_name_escaped,
    test_name_escaped,
    test_name_escaped,
    test_name_escaped
  )
end

-- @param path: Test file path
-- @type neotest.Tree
function M.parse_positions(path)
  local tests_query = [[
  ;; describe (unqualified)
  ((exp_apply
    (exp_name (variable) @func_name)
    (exp_literal) @test.name
  ) (#eq? @func_name "describe")) @test.definition

  ;; describe (qualified)
  ((exp_apply
    (exp_name (qualified_variable (variable) @func_name))
    (exp_literal) @test.name
  ) (#eq? @func_name "describe")) @test.definition

  ;; it (unqualified)
  ((exp_apply
    (exp_name (variable) @func_name)
    (exp_literal) @test.name
  ) (#eq? @func_name "it")) @test.definition

  ;; it (qualified)
  ((exp_apply
    (exp_name (qualified_variable (variable) @func_name))
    (exp_literal) @test.name
  ) (#eq? @func_name "it")) @test.definition

  ;; prop (unqualified)
  ((exp_apply
    (exp_name (variable) @func_name)
    (exp_literal) @test.name
  ) (#eq? @func_name "prop")) @test.definition

  ;; prop (qualified)
  ((exp_apply
    (exp_name (qualified_variable (variable) @func_name))
    (exp_literal) @test.name
  ) (#eq? @func_name "prop")) @test.definition
  ]]
  return util.parse_positions(path, tests_query)
end

-- @param test_name: The test name to format
-- @return the name, formatted for a hspec --match expression
-- @type string
local function hspec_format(test_name)
  -- TODO: Escape '/' characters?
  return test_name:gsub('"', '')
end

-- Helper function for 'M.get_hspec_match(position)'
-- @param position the position of the test to get the match for
-- @return the hspec match for the test
-- @type string
local function parse_hspec_match(position)
  local test_name = position.name
  local path = position.path
  local row = position.range[1]
  local parent_query = mk_parent_query(test_name)
  local parent_tree = util.parse_positions(path, parent_query)
  local nearest
  for _, parent_node in parent_tree:iter_nodes() do
    local data = parent_node:data()
    if data.type == 'test' then
      if data.range and data.range[1] <= row - 1 then
        nearest = parent_node
      else
        break
      end
    end
  end
  if not nearest then
    return hspec_format(test_name)
  end
  local parent_position = nearest:data()
  return parse_hspec_match(parent_position) .. '/' .. hspec_format(test_name)
end

-- Runs a treesitter query for the tests in the test file 'path',
-- and if there is a test that matches 'test_name',
-- prepends any parent 'describe's to the test name.
-- Example:
--  - position.name: "My test"
--  - Hspec tests in path:
--    ```
--    describe "Run" $ do
--      it "My test" $ do
--      ...
--    ```
--  - Result: "/Run/My test"
-- @param pos the position of the test to get the match for
-- @return the hspec match for the test (see example).
-- @type string
local function get_hspec_match(pos)
  local hspec_match = '/' .. parse_hspec_match(pos) .. '/'
  vim.notify('HSpec: --match: ' .. hspec_match, vim.log.levels.INFO)
  return hspec_match
end

-- @param pos the position of the test to get the match for
-- @return the cabal test options for matching an hspec filter
-- @type table
M.get_cabal_test_opts = function(pos)
  return {
    '--test-option',
    '-m',
    '--test-option',
    get_hspec_match(pos),
    '--test-option',
    '--no-color',
    '--test-option',
    '--format=checks',
  }
end

-- @param pos the position of the test to get the match for
-- @return the stack test options for matching an hspec filter
-- @type table
M.get_stack_test_opts = function(pos)
  return {
    '--ta',
    '--match "' .. get_hspec_match(pos) .. '" --no-color --format=checks',
  }
end

-- Get the error messages
local function get_hspec_errors(raw_lines, test_name)
  local failures_found = false
  local pos_found = false
  local error_message = nil
  for _, line in ipairs(raw_lines) do
    local trimmed = line:match('^%s*(.*)'):gsub('%s*$', '')
    if pos_found and trimmed:match('To rerun use:') then
      return { {
        message = error_message,
      } }
    elseif pos_found then
      error_message = error_message and error_message:gsub('%s*$', '') .. '\n' .. trimmed or trimmed
    end
    if failures_found and trimmed:match('.*' .. util.escape(test_name) .. '.*') then
      pos_found = true
    elseif trimmed:match('Failures:') then
      failures_found = true
    end
  end
  return {}
end

---@async
---@param context table: Spec context with the following fields:
--- - file: Absolute path to the test file
--- - pos_id: Postition ID of the test that was discovered - '<file>::"<test.name>"' [@see base.parse_positions]
--- - pos_path: Absolute path to the file containing the test (== file)
---@param out_path string: Path to an hspec test results output file
function M.parse_results(context, out_path)
  local pos_id = context.pos_id
  local pos_path = context.pos_path
  local success, data = pcall(lib.files.read, out_path)
  if not success then
    vim.notify('Failed to read hspec output.', vim.log.levels.ERROR)
    return { [pos_id] = {
      status = 'failed',
    } }
  end
  local lines = vim.split(data, '\n')
  local failure_positions = {}
  local success_positions = {}
  for _, line in ipairs(lines) do
    local failed = line:match('%s*(.*)%s.✘')
    local succeeded = line:match('%s*(.*)%s.✔')
    if failed then
      failure_positions[#failure_positions + 1] = failed
    elseif succeeded then
      success_positions[#success_positions + 1] = succeeded
    end
  end
  local result = { [pos_id] = {
    status = 'failed',
  } }
  for _, pos in ipairs(failure_positions) do
    local failure = {
      [pos_path .. '::"' .. pos .. '"'] = {
        status = 'failed',
        errors = get_hspec_errors(lines, pos),
      },
    }
    result = vim.tbl_extend('force', result, failure)
  end
  for _, pos in ipairs(success_positions) do
    local passed = { [pos_path .. '::"' .. pos .. '"'] = {
      status = 'passed',
    } }
    result = vim.tbl_extend('keep', result, passed)
  end
  return result
end

return M
