-- Load Omarchy's helper table `o` when their config chain did not run.
--
-- Source this from the host's Hyprland Lua config (dofile), BEFORE anything
-- written for Omarchy. See docs/ASSUMPTIONS.md, section 2.
--
--     dofile("/path/to/omarchy-guest/lib/guest.lua")
--
-- Loading their real helpers.lua beats copying functions out of it: it is ~150
-- lines of pure definitions with no side effects, the next `o.something` comes
-- for free, and their updates keep it current.

-- The same candidates the doctor checks, in the same order. OMARCHY_PATH is
-- the honest signal, but the compositor that is already running when the
-- guest is installed does not have it yet - environment.d only reaches the
-- session at the next login. The checkout location has to work on its own.
-- table.insert, e nao um literal: os.getenv devolve nil quando a variavel
-- nao existe, e um nil no meio do literal faz ipairs parar ali mesmo.
local candidates = {}
table.insert(candidates, os.getenv("OMARCHY_PATH"))
table.insert(candidates, (os.getenv("HOME") or "") .. "/.local/share/omarchy")
table.insert(candidates, "/usr/share/omarchy")

for _, omarchy_path in ipairs(candidates) do
	if omarchy_path and omarchy_path ~= "" then
		local helpers = omarchy_path .. "/default/hypr/helpers.lua"
		local handle = io.open(helpers, "r")
		if handle then
			handle:close()
			dofile(helpers)
			return true
		end
	end
end

-- Not fatal on purpose: a host config should still load without Omarchy.
return false
