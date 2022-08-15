local async = require('neotest.async')
local Path = require('plenary.path')
local lib = require('neotest.lib')
local base = require('neotest-haskell.base')
local logger = require("neotest.logging")


---@type neotest.Adapter
local HaskellNeotestAdapter = { name = 'neotest-haskell' }

HaskellNeotestAdapter.root = base.match_package_root_pattern

function HaskellNeotestAdapter.is_test_file(file_path)
  return base.is_test_file(file_path)
end

---@async
---@return neotest.Tree | nil
function HaskellNeotestAdapter.discover_positions(path)
  return base.parse_positions(path)
end

---@async
---@param args neotest.RunArgs
---@return neotest.RunSpec
function HaskellNeotestAdapter.build_spec(args)
  local tree = args.tree
  if not tree then
    return
  end
  local pos = args.tree:data()
  if pos.type ~= "test" then
    return
  end

  local hspec_match = base.get_hspec_match(pos.name, pos.path)
  local package_root = base.match_package_root_pattern(pos.path)
  local project_root = base.match_project_root_pattern(pos.path)

  local command = nil
  local results_path = async.fn.tempname()
  if lib.files.exists(project_root .. '/cabal.project') then
    logger.debug('Building spec for Cabal project...')
    for _, package_file_path in ipairs(async.fn.glob(Path:new(package_root, '*.cabal').filename, true, true)) do
      if lib.files.exists(package_file_path) then
        local package_file_name = vim.fn.fnamemodify(package_file_path, ':t')
        local package_name = package_file_name:gsub('.cabal', '')
        command = vim.tbl_flatten({
          'cabal',
          'new-test',
          package_name,
          '--test-options',
          hspec_match,
          '--test-machine-log=' .. results_path,
        })
        vim.pretty_print(command)
      end
    end
    logger.error( 'Could not determine Cabal package name.')
  elseif lib.files.exists(project_root .. 'package.yaml') then
    error("Stack not supported yet.") -- TODO
    logger.debug('Building spec for Stack project...')
    local is_subpackage = package_root ~= project_root
    local package_name = vim.fn.fnamemodify(package_root, ':t')
    local package_arg = is_subpackage and { package_name } or {}
    command = vim.tbl_flatten({
      'stack',
      'test',
      package_arg,
      '--ta',
      hspec_match,
      -- TODO: Set results path
    })
  else
    logger.error( 'Project is neither a Cabal nor a Stack project.')
  end

  if not command then
    return {}
  end

  return {
    command = command,
    context = {
      results_path = results_path,
      file = pos.path,
    },
  }
end

---@async
---@param spec neotest.RunSpec
---@param result neotest.StrategyResult
---@return neotest.Result[]
function HaskellNeotestAdapter.results(spec, result)
  print("Spec:")
  vim.pretty_print(spec)
  print("Result:")
  vim.pretty_print(result)
  -- TODO
  return {}
end

setmetatable(HaskellNeotestAdapter, {
  __call = function()
    return HaskellNeotestAdapter
  end,
})

return HaskellNeotestAdapter
