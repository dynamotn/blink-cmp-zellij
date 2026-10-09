---@class blink-cmp-zellij.Opts
---@field all_panes boolean Read every pane of the session, else the focused one
---@field triggered_only boolean
---@field trigger_chars string[]
---@field scrollback boolean Read the scrollback of a pane too, not only its screen
---@field min_update_period integer Seconds between two reads of the panes
---@field item_lifetime integer Seconds a word stays once its pane no longer shows it
---@field timeout integer Milliseconds a zellij command may take
---@field max_bytes integer Bytes read of one pane at most

---@type blink-cmp-zellij.Opts
local default_opts = {
	all_panes = false,
	triggered_only = false,
	trigger_chars = { "." },
	scrollback = false,
	min_update_period = 5,
	item_lifetime = 60,
	timeout = 2000,
	max_bytes = 1024 * 1024,
}

---@module "blink.cmp"
---@class blink.cmp.zellijSource: blink.cmp.Source
---@field opts blink-cmp-zellij.Opts
---@field items table<string, integer> Word to the `os.time()` it is dropped at
---@field last_update integer `os.time()` the last read of the panes started
---@field updating boolean A read of the panes is running
---@field waiting fun()[] Called once the read under way is done
local zellij = {}

---@param opts blink-cmp-zellij.Opts
---@return blink.cmp.zellijSource
function zellij.new(opts)
	local self = setmetatable({}, { __index = zellij })

	self.opts = vim.tbl_deep_extend("force", default_opts, opts or {})
	self.items = {}
	self.last_update = 0
	self.updating = false
	self.waiting = {}

	return self
end

--- Inside a zellij session that is still there: the variables of a session
--- outlive it in shells started from it
---@return boolean
function zellij:enabled()
	return vim.env.ZELLIJ ~= nil and vim.env.ZELLIJ_SESSION_NAME ~= nil and vim.fn.executable("zellij") == 1
end

---@return string[]
function zellij:get_trigger_characters()
	return self.opts.trigger_chars
end

---@param str string
---@return string
local function strip_ansi(str)
	return (str:gsub("\27%[[%d;]*%a", ""):gsub("\27%]%d+;[^\7]*\7", ""))
end

--- Run `zellij action <args>` in the background, and hand `on_done` its
--- output on the main loop, or nil when it failed; output past `max_bytes`
--- stops the command, and what came before is kept
---@param args string[]
---@param on_done fun(stdout: string?)
function zellij:run(args, on_done)
	local max = self.opts.max_bytes
	local chunks, size, cut, answered = {}, 0, false, false
	---@type vim.SystemObj?
	local process
	---@param stdout string?
	local function answer(stdout)
		if answered then
			return
		end
		answered = true
		vim.schedule(function()
			on_done(stdout)
		end)
	end
	local ok, started = pcall(vim.system, vim.list_extend({ "zellij", "action" }, args), {
		text = true,
		timeout = self.opts.timeout,
		stdout = function(_, data)
			if not data or cut then
				return
			end
			size = size + #data
			if size > max then
				cut = true
				data = data:sub(1, #data - (size - max))
				if process then
					pcall(process.kill, process, "sigterm")
				end
			end
			table.insert(chunks, data)
		end,
	}, function(result)
		answer((cut or result.code == 0) and table.concat(chunks) or nil)
	end)
	if not ok then
		return answer(nil)
	end
	process = started
	-- The exit is only reported once the output closes, and something the
	-- command started can hold it open past the deadline: give up on it then
	local guard = assert(vim.uv.new_timer())
	guard:start(self.opts.timeout + 1000, 0, function()
		guard:close()
		if not answered then
			pcall(started.kill, started, "sigkill")
			answer(nil)
		end
	end)
end

--- Hand `on_done` the ids of the terminal panes of the session, this one
--- left out
---@param on_done fun(ids: integer[])
function zellij:get_pane_ids(on_done)
	local current_id = tonumber(vim.env.ZELLIJ_PANE_ID)
	self:run({ "list-panes", "--json" }, function(stdout)
		local ok, panes = pcall(vim.json.decode, stdout or "")
		if not ok or type(panes) ~= "table" then
			return on_done({})
		end
		local ids = {}
		for _, pane in ipairs(panes) do
			if not pane.is_plugin and pane.id ~= current_id then
				table.insert(ids, pane.id)
			end
		end
		on_done(ids)
	end)
end

--- Hand `on_done` the text of pane `pane_id`, the focused one when nil
---@param pane_id integer?
---@param on_done fun(content: string)
function zellij:get_pane_content(pane_id, on_done)
	local args = { "dump-screen" }
	if self.opts.scrollback then
		table.insert(args, "--full")
	end
	if pane_id ~= nil then
		vim.list_extend(args, { "--pane-id", tostring(pane_id) })
	end
	self:run(args, function(stdout)
		on_done(strip_ansi(stdout or ""))
	end)
end

--- The words of `content`
---@param content string
---@param words? table<string, true> Added to, when given
---@return table<string, true>
function zellij.get_words(content, words)
	words = words or {}
	-- match not only full words, but urls, paths, etc.
	for word in string.gmatch(content, "[%w%d_:/.%-~]+") do
		words[word] = true

		-- but also isolate the words from the result
		for sub_word in string.gmatch(word, "[%w%d]+") do
			words[sub_word] = true
		end
	end
	return words
end

--- Read the panes in the background, one after the other, once
--- `min_update_period` has passed since the last read; `on_done` is called
--- when the read under way, this one or an earlier one, is done
---@param on_done? fun()
---@param force? boolean Read even before `min_update_period` has passed
function zellij:refresh(on_done, force)
	if self.updating then
		if on_done then
			table.insert(self.waiting, on_done)
		end
		return
	end
	local now = os.time()
	if not force and now - self.last_update < self.opts.min_update_period then
		if on_done then
			on_done()
		end
		return
	end
	self.updating, self.last_update = true, now
	if on_done then
		table.insert(self.waiting, on_done)
	end

	local found = {}
	local function finish()
		local time = os.time()
		local expires = time + self.opts.item_lifetime
		for word in pairs(found) do
			self.items[word] = expires
		end
		for word, at in pairs(self.items) do
			if at < time then
				self.items[word] = nil
			end
		end
		self.updating = false
		local waiting = self.waiting
		self.waiting = {}
		for _, callback in ipairs(waiting) do
			callback()
		end
	end

	if not self.opts.all_panes then
		return self:get_pane_content(nil, function(content)
			zellij.get_words(content, found)
			finish()
		end)
	end
	self:get_pane_ids(function(ids)
		local index = 0
		local function next_pane()
			index = index + 1
			if index > #ids then
				return finish()
			end
			self:get_pane_content(ids[index], function(content)
				zellij.get_words(content, found)
				next_pane()
			end)
		end
		next_pane()
	end)
end

---@param context blink.cmp.Context
---@return lsp.CompletionItem[]
function zellij:get_completion_items(context)
	local words = vim.tbl_keys(self.items)
	table.sort(words)
	return vim.iter(words)
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

--- Answered from the words kept, at once; the panes are read again in the
--- background when they are due, and only the very first completion waits
--- for that read
---@param context blink.cmp.Context
---@param callback fun(response: blink.cmp.CompletionResponse)
function zellij:get_completions(context, callback)
	local function respond()
		local triggered = not self.opts.triggered_only
			or vim.list_contains(
				self:get_trigger_characters(),
				context.line:sub(context.bounds.start_col - 1, context.bounds.start_col - 1)
			)
		callback({
			items = triggered and self:get_completion_items(context) or {},
			is_incomplete_backward = false,
			is_incomplete_forward = false,
		})
	end

	if self.last_update == 0 then
		return self:refresh(respond)
	end
	self:refresh()
	respond()
end

return zellij
