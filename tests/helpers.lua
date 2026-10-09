local M = {}

--- A scratch directory, removed by the returned function
---@return string dir
---@return fun() cleanup
function M.tmpdir()
	local dir = vim.fn.tempname()
	vim.fn.mkdir(dir, "p")
	return dir, function()
		vim.fn.delete(dir, "rf")
	end
end

--- Put a fake `zellij` holding `lines` first on `$PATH`, logging each call
--- to `<dir>/calls`; the returned function puts `$PATH` back
---@param dir string
---@param lines string[]
---@return fun() restore
function M.fake_zellij(dir, lines)
	local path = dir .. "/zellij"
	vim.fn.writefile(vim.list_extend({ "#!/bin/sh", 'echo "start $*" >> "' .. dir .. '/calls"' }, lines), path)
	vim.fn.setfperm(path, "rwxr-xr-x")
	local before = vim.env.PATH
	vim.env.PATH = dir .. ":" .. before
	return function()
		vim.env.PATH = before
	end
end

return M
