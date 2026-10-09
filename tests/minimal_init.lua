-- Neovim for the specs: this plugin, plenary.nvim, and blink.cmp's types,
-- cloned once into `.tests/` unless `BLINK_CMP_ZELLIJ_DEPS` points at them
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
local deps = vim.env.BLINK_CMP_ZELLIJ_DEPS or (root .. "/.tests/deps")

---@param repo string
---@return string
local function dep(repo)
	local dir = deps .. "/" .. repo:match("[^/]+$")
	if not vim.uv.fs_stat(dir) then
		vim.fn.mkdir(deps, "p")
		vim.fn.system({ "git", "clone", "--depth=1", "https://github.com/" .. repo, dir })
	end
	return dir
end

vim.opt.runtimepath = { vim.env.VIMRUNTIME, root, dep("nvim-lua/plenary.nvim") }
-- blink.cmp's types only: its plugin file wants its fuzzy matcher built
package.path = dep("saghen/blink.cmp") .. "/lua/?.lua;" .. root .. "/?.lua;" .. package.path
vim.env.XDG_STATE_HOME = root .. "/.tests/state"
vim.cmd("runtime plugin/plenary.vim")
