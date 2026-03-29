---@class blink-cmp-zellij.Opts
---@field all_panes boolean
---@field triggered_only boolean
---@field trigger_chars string[]

---@type blink-cmp-zellij.Opts
local default_opts = {
	all_panes = false,
	triggered_only = false,
	trigger_chars = { "." },
}

---@module "blink.cmp"
---@class blink.cmp.zellijSource: blink.cmp.Source
---@field opts blink-cmp-zellij.Opts
local zellij = {}

---@param opts blink-cmp-zellij.Opts
---@return blink.cmp.zellijSource
function zellij.new(opts)
	local self = setmetatable({}, { __index = zellij })

	self.opts = vim.tbl_deep_extend("force", default_opts, opts)

	return self
end

---@return boolean
function zellij:enabled()
	return vim.fn.executable("zellij") == 1 and os.getenv("ZELLIJ") ~= nil
end

---@return string[]
function zellij:get_trigger_characters()
	return self.opts.trigger_chars
end

---@param str string
---@return string
local function strip_ansi(str)
	return str:gsub("\27%[[%d;]*%a", ""):gsub("\27%]%d+;[^\7]*\7", "")
end

---@param pane_id integer|nil  nil means current focused pane
---@return string
function zellij:get_pane_content(pane_id)
	local cmd = { "zellij", "action", "dump-screen" }

	if pane_id ~= nil then
		vim.list_extend(cmd, { "--pane-id", tostring(pane_id) })
	end

	local result = vim.system(cmd, { text = true }):wait()

	if result.code ~= 0 then
		return ""
	end

	return strip_ansi(result.stdout or "")
end

---@return integer[]
function zellij:get_pane_ids()
	local current_id = tonumber(os.getenv("ZELLIJ_PANE_ID"))
	local result = vim.system({ "zellij", "action", "list-panes", "--json" }, { text = true }):wait()

	if result.code ~= 0 or not result.stdout then
		return {}
	end

	local ok, panes = pcall(vim.json.decode, result.stdout)
	if not ok or type(panes) ~= "table" then
		return {}
	end

	local ids = {}
	for _, pane in ipairs(panes) do
		if not pane.is_plugin and pane.id ~= current_id then
			table.insert(ids, pane.id)
		end
	end

	return ids
end

---@return string[]
function zellij:get_words()
	local words = {}

	local function process_content(content)
		-- match not only full words, but urls, paths, etc.
		for word in string.gmatch(content, "[%w%d_:/.%-~]+") do
			words[word] = true

			-- but also isolate the words from the result
			for sub_word in string.gmatch(word, "[%w%d]+") do
				words[sub_word] = true
			end
		end
	end

	if self.opts.all_panes then
		vim.iter(self:get_pane_ids()):each(function(id)
			process_content(self:get_pane_content(id))
		end)
	else
		process_content(self:get_pane_content(nil))
	end

	return vim.tbl_keys(words)
end

---@param context blink.cmp.Context
---@return lsp.CompletionItem[]
function zellij:get_completion_items(context)
	return vim.iter(self:get_words())
		:map(function(word)
			---@type lsp.CompletionItem
			local item = {
				label = word,
				kind = require("blink.cmp.types").CompletionItemKind.Text,
				insertText = word,
			}
			if self.opts.triggered_only then
				item = vim.tbl_deep_extend("force", item, {
					textEdit = {
						newText = word,
						range = {
							start = { line = context.cursor[1] - 1, character = context.bounds.start_col - 2 },
							["end"] = { line = context.cursor[1] - 1, character = context.cursor[2] },
						},
					},
				})
			end
			return item
		end)
		:totable()
end

---@param context blink.cmp.Context
---@param callback fun(items: blink.cmp.CompletionItem[])
function zellij:get_completions(context, callback)
	vim.schedule(function()
		local triggered = not self.opts.triggered_only
			or vim.list_contains(
				self:get_trigger_characters(),
				context.line:sub(context.bounds.start_col - 1, context.bounds.start_col - 1)
			)
		callback({
			items = triggered and self:get_completion_items(context) or {},
			is_incomplete_backward = true,
			is_incomplete_forward = true,
		})
	end)
end

return zellij
