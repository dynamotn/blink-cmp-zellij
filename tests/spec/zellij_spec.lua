local h = require("tests.helpers")

local PANES = vim.json.encode({
	{ id = 0, is_plugin = true },
	{ id = 1, is_plugin = false },
	{ id = 2, is_plugin = false },
	{ id = 3, is_plugin = false },
})

describe("blink-cmp-zellij", function()
	local zellij, dir, cleanup, restore, env
	before_each(function()
		package.loaded["blink-cmp-zellij"] = nil
		zellij = require("blink-cmp-zellij")
		dir, cleanup = h.tmpdir()
		env = { vim.env.ZELLIJ, vim.env.ZELLIJ_SESSION_NAME, vim.env.ZELLIJ_PANE_ID }
		vim.env.ZELLIJ, vim.env.ZELLIJ_SESSION_NAME, vim.env.ZELLIJ_PANE_ID = "0", "main", "2"
		vim.fn.writefile({ PANES }, dir .. "/panes.json")
		restore = h.fake_zellij(dir, {
			'case "$*" in',
			'  "action list-panes --json") cat "' .. dir .. '/panes.json";;',
			"  *pane-id\\ 1) sleep 0.1; echo pane_one http://one.dev;;",
			"  *pane-id\\ 3) echo pane-three;;",
			'  "action dump-screen") echo focused_pane;;',
			"esac",
		})
	end)
	after_each(function()
		restore()
		vim.env.ZELLIJ, vim.env.ZELLIJ_SESSION_NAME, vim.env.ZELLIJ_PANE_ID = env[1], env[2], env[3]
		cleanup()
	end)

	--- Complete at the end of `line`, the word starting at `start_col`, and
	--- wait for the answer
	local function complete(src, line, start_col)
		local response
		src:get_completions({ line = line, cursor = { 1, #line }, bounds = { start_col = start_col } }, function(r)
			response = r
		end)
		assert.is_true(vim.wait(5000, function()
			return response ~= nil
		end))
		return response
	end

	local function labels(response)
		return vim.tbl_map(function(item)
			return item.label
		end, response.items)
	end

	local function calls()
		return vim.fn.readfile(dir .. "/calls")
	end

	it("is on only inside a live session", function()
		local src = zellij.new({})
		assert.is_true(src:enabled())
		vim.env.ZELLIJ_SESSION_NAME = nil
		assert.is_false(src:enabled())
	end)

	it("reads the focused pane, without waiting on it", function()
		local src = zellij.new({})
		local response
		src:get_completions({ line = "fo", cursor = { 1, 2 }, bounds = { start_col = 1 } }, function(r)
			response = r
		end)
		-- Not answered within the call: the pane is read in the background
		assert.is_nil(response)
		assert.is_true(vim.wait(5000, function()
			return response ~= nil
		end))
		assert.is_true(vim.list_contains(labels(response), "focused_pane"))
		assert.is_false(response.is_incomplete_forward)
	end)

	it("reads every other terminal pane, one after the other", function()
		local src = zellij.new({ all_panes = true })
		local words = labels(complete(src, "pa", 1))
		assert.is_true(vim.list_contains(words, "pane_one"))
		assert.is_true(vim.list_contains(words, "http://one.dev"))
		assert.is_true(vim.list_contains(words, "pane-three"))
		assert.same({
			"start action list-panes --json",
			"start action dump-screen --pane-id 1",
			"start action dump-screen --pane-id 3",
		}, calls())
	end)

	it("answers from what it kept until the update period has passed", function()
		local src = zellij.new({ all_panes = true })
		complete(src, "pa", 1)
		local before = #calls()
		local response = complete(src, "pane", 1)
		assert.equal(before, #calls())
		assert.is_true(vim.list_contains(labels(response), "pane_one"))
	end)

	it("reads the scrollback when asked to", function()
		local src = zellij.new({ scrollback = true })
		complete(src, "x", 1)
		assert.same({ "start action dump-screen --full" }, calls())
	end)

	it("gives up on a pane past the deadline, and answers anyway", function()
		restore()
		restore = h.fake_zellij(dir, { "sleep 5" })
		local src = zellij.new({ timeout = 100 })
		local response = complete(src, "x", 1)
		assert.same({}, response.items)
		assert.is_false(src.updating)
	end)

	it("stops reading a pane at the cap", function()
		restore()
		restore = h.fake_zellij(dir, { "exec yes word" })
		local src = zellij.new({ max_bytes = 1000 })
		local response = complete(src, "wo", 1)
		assert.same({ "word" }, labels(response))
	end)

	it("offers words only after a trigger character, when asked to", function()
		local src = zellij.new({ triggered_only = true })
		assert.same({}, complete(src, "x fo", 3).items)
		local items = complete(src, "x.fo", 3).items
		assert.is_true(#items > 0)
		assert.same({ line = 0, character = 1 }, items[1].textEdit.range.start)
	end)

	it("drops a word once its lifetime is over", function()
		local src = zellij.new({ item_lifetime = 0, min_update_period = 0 })
		complete(src, "fo", 1)
		src.items.old = os.time() - 1
		src:refresh(nil, true)
		assert.is_true(vim.wait(5000, function()
			return not src.updating
		end))
		assert.is_nil(src.items.old)
	end)
end)
