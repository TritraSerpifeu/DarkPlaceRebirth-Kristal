-- Dont replace state variables if we are hotswapping
if HOTSWAPPING then return end

HOTSWAPPING = false

DISCORD_RPC_ID = "1174736572000776252"
DISCORD_RPC_AVAILABLE = false
DISCORD_RPC_PRESENCE = {}

FRAMERATE = 30

BASE_DT = (1/30)
DT = (1/30)
DTMULT = DT * 30

FPS = 0
FPS_COUNTER = 0
FPS_TIMER = 0

RUNTIME = 0

MOD_LOADING = false
ACTIVE_LIB = nil

DEBUG_RENDER = false

FAST_FORWARD = false
FAST_FORWARD_SPEED = 5
CURRENT_SPEED_MULT = 1

CURRENT_SCALE_X = 1
CURRENT_SCALE_Y = 1

MOUSE_VISIBLE = false
---@type love.Image?
MOUSE_SPRITE = nil

OVERLAY_OPEN = false
NOCLIP = false

REGISTRY_LOADED = false

--- Which Deltarune save file should be loaded upon mod startup.
---@type 1|2|3|nil
DELTARUNE_SAVE_ID = nil

---@type string?
COROUTINE_TRACEBACK = nil
