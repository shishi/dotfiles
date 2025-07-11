local M = {}

--- Check if a file exists
--- @param name string The file path to check
--- @return boolean true if file exists, false otherwise
function M.file_exists(name)
  local f = io.open(name, 'r')
  if f ~= nil then
    io.close(f)
    return true
  else
    return false
  end
end

--- Get LSP module names from the after/lsp directory
--- @return table Array of module names (without .lua extension)
function M.get_lsp_modules()
  local lsp_dir = vim.fn.stdpath('config') .. '/after/lsp'
  local modules = {}

  -- Check if directory exists
  if vim.fn.isdirectory(lsp_dir) == 0 then
    return modules
  end

  -- Iterate through files in the directory
  for name, type in vim.fs.dir(lsp_dir) do
    if type == 'file' and name:match('%.lua$') then
      -- Remove .lua extension to get module name
      local module = name:gsub('%.lua$', '')
      table.insert(modules, module)
    end
  end

  return modules
end

return M

