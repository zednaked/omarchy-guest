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

local omarchy_path = os.getenv("OMARCHY_PATH") or "/usr/share/omarchy"
local helpers = omarchy_path .. "/default/hypr/helpers.lua"

local handle = io.open(helpers, "r")
if not handle then
	-- Not fatal on purpose: a host config should still load without Omarchy.
	return false
end
handle:close()

dofile(helpers)
return true
