--- The heart of Kristal - this class stores serves as the global that almost everything during gameplay is stored under in some way or another. \
--- Game itself is mainly responsible for changing between states, handling player control, and accessing overarching features across gameplay such as the inventory or party members.
---@class Game
---@field stage             Stage
---@field world             World
---@field battle            Battle
---@field shop              Shop
---@field gameover          GameOver
---@field legend            Legend
---@field dogcheck          DogCheck
---@field inventory         DarkInventory|LightInventory
---@field dark_inventory    DarkInventory
---@field light_inventory   LightInventory
---@field quick_save        SaveData
---@field lock_movement     boolean
---@field key_repeat        boolean
---@field started           boolean
---@field border            Border
---
---@field previous_state    string
---@field state             string
---@field music             Music
---
---@field chapter           integer
---@field save_name         string
---@field save_level        integer
---@field playtime          number
---@field light             boolean
---@field money             integer
---@field xp                integer
---@field tension           number
---@field max_tension       number
---@field lw_money          integer
---@field level_up_count    integer
---@field temp_followers    table<[string, number]|string>
---@field flags             table<[string, any]>
---@field party             PartyMember[]
---@field party_data        PartyMember[]
---@field recruits_data     Recruit[]
---@field quests_data       Quest[]
---
---@field fader             Fader
---@field max_followers     integer
---@field is_new_file       boolean
local Game = {}

function Game:clear()
    if self.world and self.world.music then
        self.world.music:stop()
    end
    if self.battle and self.battle.music then
        self.battle.music:stop()
    end
    if self.stage then
        for _,child in ipairs(self.stage.children) do
            self.stage:removeFromStage(child)
        end
    end
    if self.music then
        self.music:stop()
    end
    self.stage = nil
    self.world = nil
    self.battle = nil
    self.minigame = nil
    self.shop = nil
    self.gameover = nil
    self.legend = nil
    self.dogcheck = nil
    self.inventory = nil
    self.quick_save = nil
    self.lock_movement = false
    self.key_repeat = false
    self.started = false
    self.border = "simple"
    self.swap_into_mod = nil
    self.total_bp = nil
end

---@overload fun(self: Game, previous_state: string, save_data: SaveData, save_id: number)
---@param previous_state    string
---@param save_data?        SaveData
---@param save_id?          number
---@param save_name?        string
---@param fade?             boolean
function Game:enter(previous_state, save_id, save_name, fade)
    self.previous_state = previous_state

    self.music = Music()

    self.quick_save = nil

    Kristal.callEvent(KRISTAL_EVENT.init)
    Game:loadHooks()

    self.lock_movement = false

    self:initTaunt()
    self:initBattleTaunt()

    fade = fade ~= false
    if type(save_id) == "table" then
        local save = save_id
        save_id = save_name
        save_name = nil
        self:load(save, save_id, fade)
    elseif save_id then
        Kristal.loadGame(save_id, fade)
    else
        self:load(nil, nil, fade)
    end

    if save_name then
        self.save_name = save_name
    end

    self.started = true

    DISCORD_RPC_PRESENCE = {}

    Kristal.callEvent(KRISTAL_EVENT.postInit, self.is_new_file)

    if next(DISCORD_RPC_PRESENCE) == nil then
        Kristal.setPresence({
            state = Kristal.callEvent(KRISTAL_EVENT.getPresenceState) or ("Playing " .. (Kristal.getModOption("name") or "a mod")),
            details = Kristal.callEvent(KRISTAL_EVENT.getPresenceDetails),
            largeImageKey = Kristal.callEvent(KRISTAL_EVENT.getPresenceImage) or "logo",
            largeImageText = "Kristal v" .. tostring(Kristal.Version),
            startTimestamp = self.playtime and math.floor(os.time() - self.playtime) or 0,
            instance = 0
        })
    end
end

function Game:loadHooks()
    if MagicalGlassLib then
        Utils.hook(LightEnemyBattler, "registerMarcyAct", function(orig, self, name, description, party, tp, highlight, icons)
            if Game:getFlag("marcy_joined") then
                self:registerShortActFor("jamm", name, description, party, tp, highlight, icons)
                self.acts[#self.acts].color = {0, 1, 1}
            end
        end)
        Utils.hook(LightEnemyBattler, "registerShortMarcyAct", function(orig, self, name, description, party, tp, highlight, icons)
            if Game:getFlag("marcy_joined") then
                self:registerActFor("jamm", name, description, party, tp, highlight, icons)
                self.acts[#self.acts].color = {0, 1, 1}
            end
        end)
    end
end

function Game:leave()
    self:clear()
    self.quick_save = nil
end

---@return Border
function Game:getBorder()
    return self.border
end

---@param border?   string|Border
---@param time?     number
function Game:setBorder(border, time)
    time = time or 1
    local new_border_id = border
    if type(border) ~= "string" then
        new_border_id = border.id
    end
    local current_border_id
    if Kristal.getBorder() then
        current_border_id = Kristal.getBorder().id
    end
    if time == 0 then
        Kristal.showBorder(0)
    elseif time > 0 and current_border_id ~= new_border_id then
        Kristal.transitionBorder(time)
    end

    if type(border) == "string" then
        local border_class = Registry.createBorder(border)
        if border_class then border = border_class end
    end
    self.border = border
end

function Game:returnToMenu()
    self.fader:fadeOut(Kristal.returnToMenu, {speed = 0.5, music = 10/30})
    Kristal.hideBorder(0.5)
    self.state = "EXIT"
end

---@param key           string
---@param merge?        boolean
---@param deep_merge?   boolean
---@return any
function Game:getConfig(key, merge, deep_merge)
    local default_config = Kristal.ChapterConfigs[Utils.clamp(self.chapter, 1, #Kristal.ChapterConfigs)]
    for index, config in pairs(Kristal.ExtraConfigs) do
       default_config[index] = config
    end

    if not Mod then return default_config[key] end

    local mod_result = Kristal.callEvent(KRISTAL_EVENT.getConfig, key)
    if mod_result ~= nil then return mod_result end

    local mod_config = Mod.info and Mod.info.config and Utils.getAnyCase(Mod.info.config, "kristal") or {}

    local default_value = Utils.getAnyCase(default_config, key)
    local mod_value = Utils.getAnyCase(mod_config, key)

    if mod_value ~= nil and default_value == nil then
        return mod_value
    elseif default_value ~= nil and mod_value == nil then
        return default_value
    elseif type(default_value) == "table" and merge then
        return Utils.merge(Utils.copy(default_value, true), mod_value, deep_merge)
    else
        return mod_value
    end
end

---@return Music
function Game:getActiveMusic()
    if self.state == "OVERWORLD" then
        return self.world.music
    elseif self.state == "BATTLE" then
        return self.battle.music
	elseif self.state == "MINIGAME" then
        return self.minigame.music
    elseif self.state == "SHOP" then
        return self.shop.music
    elseif self.state == "GAMEOVER" then
        return self.gameover.music
    elseif self.state == "LEGEND" then
        return self.legend.music
    elseif self.state == "DOGCHECK" then
        return self.dogcheck.music
    else
        return self.music
    end
end

---@return {name: string, level: integer, playtime: number, room_name: string}
function Game:getSavePreview()
    return {
        name = self.save_name,
        level = self.save_level,
        playtime = self.playtime,
        room_name = self.world and self.world.map and self.world.map.name or "???",
    }
end

---@overload fun(self: Game, marker: string) : SaveData
---@overload fun(self: Game, position: {x: number, y: number}) : SaveData
---@param x number
---@param y number
---@param marker string
---@param position {x: number, y: number}
---@return SaveData
function Game:save(x, y)
    local data = {
        mod = Mod.info.id,

        chapter = self.chapter,

        name = self.save_name,
        level = self.save_level,
        playtime = self.playtime,

        light = self.light,

        room_name = self.world and self.world.map and self.world.map.name or "???",
        room_id = self.world and self.world.map and self.world.map.id,

        money = self.money,
        xp = self.xp,

        tension = self.tension,
        max_tension = self.max_tension,

        lw_money = self.lw_money,

        level_up_count = self.level_up_count,

        border = self.border.id,

        temp_followers = self.temp_followers,

        flags = self.flags,

        total_bp = self.total_bp,

        bossrush_encounters = self.bossrush_encounters,
    }

    if x then
        if type(x) == "string" then
            data.spawn_marker = x
        elseif type(x) == "table" then
            data.spawn_position = x
        elseif x and y then
            data.spawn_position = {x, y}
        end
    end

    data.party = {}
    for _,party in ipairs(self.party) do
        table.insert(data.party, party.id)
    end
    
    data.default_equip_slots = self.default_equip_slots

    data.inventory = self.inventory:save()
    data.light_inventory = self.light_inventory:save()
    data.dark_inventory = self.dark_inventory:save()

    data.party_data = {}
    for k,v in pairs(self.party_data) do
        data.party_data[k] = v:save()
    end
    
    data.recruits_data = {}
    for k,v in pairs(self.recruits_data) do
        data.recruits_data[k] = v:save()
    end

    data.quests_data = {}
    for k,v in pairs(self.quests_data) do
        data.quests_data[k] = v:save()
    end

    Kristal.callEvent(KRISTAL_EVENT.save, data)

    return data
end

---@param data?     SaveData
---@param index?    number
---@param fade?     boolean
function Game:load(data, index, fade)
    self.is_new_file = data == nil

    data = data or {}

    self:clear()

    if data.mod and data.mod ~= Mod.info.id then
        print("WARNING: Loading save file from a different DLC. Hopefully you're just switching inbetween.")
    end

    BORDER_ALPHA = 0
    Kristal.showBorder(1)

    -- states: OVERWORLD, BATTLE, SHOP, MINIGAME, GAMEOVER, LEGEND, DOGCHECK
    self.state = "OVERWORLD"

    self.stage = Stage()

    self.world = World()
    self.stage:addChild(self.world)

    self.fader = Fader()
    self.fader.layer = 1000
    self.stage:addChild(self.fader)

    if fade then
        self.fader:fadeIn(nil, {alpha = 1, speed = 0.5})
    end

    self.battle = nil

    self.shop = nil

    self.max_followers = Kristal.getModOption("maxFollowers") or 10

    self.light = false
    
    -- Used to carry the soul invulnerability frames between waves
    self.old_soul_inv_timer = 0

    -- BEGIN SAVE FILE VARIABLES --

    self.chapter = data.chapter or Kristal.getModOption("chapter") or 2

    self.save_name = data.name or self.save_name or "PLAYER"
    self.save_level = data.level or self.chapter
    self.save_id = index or self.save_id or 1

    self.playtime = data.playtime or 0

    self.flags = data.flags or {}

    self:initPartyMembers()
    if data.party_data then
        for k,v in pairs(data.party_data) do
            if self.party_data[k] then
                self.party_data[k]:load(v)
            end
        end
    end
    
    self.party = {}
    for _,id in ipairs(data.party or Kristal.getModOption("party") or {"kris"}) do
        local ally = self:getPartyMember(id)
        if ally then
            table.insert(self.party, ally)
        else
            Kristal.Console:error("Could not load party member \"" ..id.."\"")
        end
    end
    
    self:initRecruits()
    if data.recruits_data then
        for k,v in pairs(data.recruits_data) do
            if self.recruits_data[k] then
                self.recruits_data[k]:load(v)
            end
        end
    end
    self:initQuests()
    if data.quests_data then
        for k,v in pairs(data.quests_data) do
            if self.quests_data[k] then
                self.quests_data[k]:load(v)
            else
                self.quests_data[k] = FallbackQuest(v)
            end
        end
    end

    if data.temp_followers then
        self.temp_followers = data.temp_followers
    else
        self.temp_followers = {}
        for _,id in ipairs(Kristal.getModOption("followers") or {}) do
            table.insert(self.temp_followers, id)
        end
    end

    self.bossrush_encounters = data.bossrush_encounters

    self.level_up_count = data.level_up_count or 0

    self.money = data.money or Kristal.getModOption("money") or 0
    self.xp = data.xp or 0

    self.tension = data.tension or 0
    self.max_tension = data.max_tension or 100

    self.total_bp = data.total_bp or 3

    self.lw_money = data.lw_money or 2

    self.border = data.border
    if not self.border then
        self.border = self.light and "leaves" or "castle"
    end

    local map = nil
    local room_id = data.room_id or Kristal.getModOption("map")
    if room_id and not self.bossrush_encounters then
        map = Registry.createMap(room_id, self.world)

        self.light = map.light or false
    end
    
    self.default_equip_slots = data.default_equip_slots or 48
    if self.is_new_file and Game:getConfig("lessEquipments") then
        self.default_equip_slots = 12
    end

    if self.light then
        self.inventory = LightInventory()
    else
        self.inventory = DarkInventory()
    end

    self.light_inventory = LightInventory()
    if data.light_inventory then
        self.light_inventory:load(data.light_inventory)
    end
    self.dark_inventory = DarkInventory()
    if data.dark_inventory then
        self.dark_inventory:load(data.dark_inventory)
    end
    
    if data.inventory then
        self.inventory:load(data.inventory)
    else
        local default_inv = Kristal.getModOption("inventory") or {}
        if not self.light and not default_inv["key_items"] then
            default_inv["key_items"] = {"cell_phone"}
        end
        for storage,items in pairs(default_inv) do
            for i,item in ipairs(items) do
                self.inventory:setItem(storage, i, item)
            end
        end
    end

    local loaded_light = data.light or false

    -- Party members have to be converted to light initially, due to dark world defaults
    if loaded_light ~= self.light then
        if self.light then
            for _,chara in pairs(self.party_data) do
                chara:convertToLight()
            end
        else
            for _,chara in pairs(self.party_data) do
                chara:convertToDark()
            end
        end
    end

    if self.is_new_file then
        if self.light then
            Game:setFlag("has_cell_phone", Kristal.getModOption("cell") ~= false)
        end

        for id,equipped in pairs(Kristal.getModOption("equipment") or {}) do
            if equipped["weapon"] then
                self.party_data[id]:setWeapon(equipped["weapon"] ~= "" and equipped["weapon"] or nil)
            end
            local armors = equipped["armor"] or {}
            for i = 1, 2 do
                if armors[i] then
                    if self.light and i == 2 then
                        local main_armor = self.party_data[id]:getArmor(1)
                        if not main_armor:includes(LightEquipItem) then
                            error("Cannot set 2nd armor, 1st armor must be a LightEquipItem")
                        end
                        main_armor:setArmor(2, armors[i])
                    else
                        self.party_data[id]:setArmor(i, armors[i] ~= "" and armors[i] or nil)
                    end
                end
            end
        end
    end
    -- Make sure it only comes back when you load a file, not when switching between DLCs
    if not Game:getFlag("is_swapping_mods", false) and Game:getFlag("oddstone_tossed", false) then
        -- If you threw away the Odd Stone, bring it back
        if self.light then
            self.inventory:addItem("light/grey_marble")
        else
            self.inventory:addItem("oddstone")
        end
        Game:setFlag("oddstone_tossed", false)
    end
    Game:setFlag("is_swapping_mods", false)
    -- END SAVE FILE VARIABLES --

    Kristal.callEvent(KRISTAL_EVENT.load, data, self.is_new_file, index)

    -- Load the map if we have one
    if map then
        if data.spawn_position then
            self.world:loadMap(map, data.spawn_position[1], data.spawn_position[2], data.spawn_facing)
        else
            self.world:loadMap(map, data.spawn_marker or "spawn", data.spawn_facing)
        end
    end

    Kristal.DebugSystem:refresh()

    self.started = true
    
    self.nothing_warn = true
    if self.is_new_file then
        if Kristal.getModOption("encounter") then
            self:encounter(Kristal.getModOption("encounter"), false)
        elseif Kristal.getModOption("shop") then
            self:enterShop(Kristal.getModOption("shop"), {menu = true})
        end
    elseif self.bossrush_encounters then
        self:setBorder("battle")
        self:encounter(self:getBossRef(self.bossrush_encounters[1]).encounter)
    end

    Kristal.callEvent(KRISTAL_EVENT.postLoad)
end

---@param light? boolean
function Game:setLight(light)
    light = light or false

    if not self.started then
        self.light = light
        return
    end

    if self.light == light then return end

    self.light = light

    if self.light then
        self:convertToLight()
    else
        self:convertToDark()
    end
end

---@return boolean
function Game:isLight()
    return self.light
end

function Game:convertToLight()
    local inventory = self.inventory
    ---@cast inventory DarkInventory

    if inventory:hasItem("cell_phone") then
        self:setFlag("has_cell_phone", true)
        inventory:removeItem("cell_phone")
    else
        self:setFlag("has_cell_phone", false)
    end

    self.inventory = inventory:convertToLight()

    for _,chara in pairs(self.party_data) do
        chara:convertToLight()
    end
end

function Game:convertToDark()
    local inventory = self.inventory
    ---@cast inventory LightInventory

    self.inventory = inventory:convertToDark()

    for _,chara in pairs(self.party_data) do
        chara:convertToDark()
    end

    if self:getFlag("has_cell_phone", false) then
        self.inventory:addItemTo("key_items", 1, "cell_phone")
    end
end

---@param x? number
---@param y? number
---@param sf? boolean
function Game:gameOver(x, y, sf)
    Kristal.hideBorder(0)

    self.state = "GAMEOVER"
    if self.battle   then self.battle  :remove() end
    if self.world    then self.world   :remove() end
    if self.shop     then self.shop    :remove() end
    if self.gameover then self.gameover:remove() end
    if self.legend   then self.legend  :remove() end
    if self.dogcheck then self.dogcheck:remove() end

    if Game:getFlag("FUN", 0) ~= 18 --[[0xE+0xA]] and not sf then
        self.gameover = GameOver(x or 0, y or 0)
        self.stage:addChild(self.gameover)
    else
        self.gameover = GameOverSF(sf == "bearers" and true or nil)
        self.stage:addChild(self.gameover)
    end
end

---@param cutscene          string
---@param legend_options?   table
---@param fade_options?     table
function Game:fadeIntoLegend(cutscene, legend_options, fade_options)
    legend_options = legend_options or {}
    fade_options = fade_options or {}

    fade_options["speed"] = fade_options["speed"] or 2
    fade_options["music"] = fade_options["music"] or true

    Game.lock_movement = true
    Game.world.fader:fadeOut(function() Game:startLegend(cutscene, legend_options) end, fade_options)
end

---@param cutscene  string
---@param options?  table
function Game:startLegend(cutscene, options)

    if self.legend then
        self.legend:remove()
    end

    self.state = "LEGEND"
    self.legend = Legend(cutscene, options)
    self.stage:addChild(self.legend)
end

---@param ... unknown
function Game:saveQuick(...)
    self.quick_save = Utils.copy(self:save(...), true)
end

---@param fade? boolean
function Game:loadQuick(fade)
    local save = self.quick_save
    if save then
        assert(save.mod == Mod.info.id, "Loading quick save created in another DLC ("..save.mod..") is UNIMPLEMENTED!")
        self:load(save, self.save_id, fade)
    else
        Kristal.loadGame(self.save_id)
    end
    self.quick_save = save
end

--- Starts a battle using the specified encounter file.
---@param encounter     Encounter|string    The encounter id or instance to use for this battle.
---@param transition?   boolean|string      Whether to start in the transition state (Defaults to `true`). As a string, represents the state to start the battle in.
---@param enemy?        Character|table     An enemy instance or list of enemies as `Character`s in the world that will transition into the battle.
---@param context?      ChaserEnemy
function Game:encounter(encounter, transition, enemy, context)
    if transition == nil then transition = true end

    if self.battle then
        error("Attempt to enter battle while already in battle")
    end

    if enemy and not isClass(enemy) then
        self.encounter_enemies = enemy
    else
        self.encounter_enemies = {enemy}
    end

    self.state = "BATTLE"

    self.battle = Battle()

    if context then
        self.battle.encounter_context = context
    end

    if type(transition) == "string" then
        self.battle:postInit(transition, encounter)
    else
        self.battle:postInit(transition and "TRANSITION" or "INTRO", encounter)
    end

    self.stage:addChild(self.battle)
end

---@param shop string|Shop
function Game:setupShop(shop)
    if self.shop then
        error("Attempt to enter shop while already in shop")
    end

    if type(shop) == "string" then
        shop = Registry.createShop(shop)
    end

    if shop == nil then
        error("Attempt to enter shop with nil shop")
    end

    self.shop = shop
    self.shop:postInit()
end

--- Enters a shop
---@param shop      string|Shop The shop to enter
---@param options?  table       An optional table of [`leave_options`](lua://Shop.leave_options) for exiting the shop
function Game:enterShop(shop, options)
    -- Add the shop to the stage and enter it.
    if self.shop then
        self.shop:leaveImmediate()
    end

    self:setupShop(shop)

    if options then
        self.shop.leave_options = options
    end

    if self.world and self.shop.shop_music then
        self.world.music:stop()
    end

    self.state = "SHOP"

    self.stage:addChild(self.shop)
    self.shop:onEnter()
end

function Game:startMinigame(game)
    if Game.minigame then
        error("Attempt to enter minigame while already being in one")
    end

    Game.state = "MINIGAME"

    Game.minigame = Registry.createMinigame(game)

    Game.minigame:postInit()

    Game.stage:addChild(Game.minigame)
end

function Game:dogCheck(variant)
    Kristal.hideBorder(0)

    self.state = "DOGCHECK"
    if self.battle   then self.battle  :remove() end
    if self.world    then self.world   :remove() end
    if self.shop     then self.shop    :remove() end
    if self.gameover then self.gameover:remove() end
    if self.legend   then self.legend  :remove() end
    if self.dogcheck then self.dogcheck:remove() end

    if variant then
        self.dogcheck = DogCheck(variant)
    else
        self.dogcheck = DogCheck()
    end
    self.stage:addChild(self.dogcheck)
end

function Game:setPresenceState(details)
    self.rpc_state = details

    -- talk about some half-baked support :bangbang:
    local presence = Kristal.getPresence()
    if presence then
        presence.state = Kristal.callEvent("getPresenceState")
        Kristal.setPresence(presence)
    end
end

--- Sets the value of the flag named `flag` to `value`
---@param flag  string
---@param value any
function Game:setFlag(flag, value)
    self.flags[flag] = value
end

--- Gets the value of the flag named `flag`, returning `default` if the flag does not exist
---@param flag      string
---@param default?  any
---@return any
function Game:getFlag(flag, default)
    local result = self.flags[flag]
    if result == nil then
        return default
    else
        return result
    end
end

--- Adds `amount` to a numeric flag named `flag` (or defines it if it does not exist)
---@param flag      string  The name of the flag to add to
---@param amount?   number  (Defaults to `1`)
---@return number new_value
function Game:addFlag(flag, amount)
    self.flags[flag] = (self.flags[flag] or 0) + (amount or 1)
    return self.flags[flag]
end

function Game:initPartyMembers()
    self.party_data = {}
    for id,_ in pairs(Registry.party_members) do
        if Registry.getPartyMember(id) then
            self.party_data[id] = Registry.createPartyMember(id)
        else
            error("Attempted to add non-existent member \"" .. id .. "\" to the party")
        end
    end
end

function Game:initRecruits()
    self.recruits_data = {}
    for id,_ in pairs(Registry.recruits) do
        if Registry.getRecruit(id) then
            self.recruits_data[id] = Registry.createRecruit(id)
        else
            error("Attempted to create non-existent recruit \"" .. id .. "\"")
        end
    end
end

function Game:initQuests()
    self.quests_data = {}
    for id,_ in pairs(Registry.quests) do
        self.quests_data[id] = Registry.createQuest(id)
    end
end

---@param id string
---@return PartyMember?
function Game:getPartyMember(id)
    if self.party_data[id] then
        return self.party_data[id]
    end
end

---@param id string
---@return Recruit?
function Game:getRecruit(id)
    if self.recruits_data[id] then
        return self.recruits_data[id]
    end
end

---@param include_incomplete?   boolean
---@param include_hidden?       boolean
---@return Recruit[]
function Game:getRecruits(include_incomplete, include_hidden)
    local recruits = {}
    for id,recruit in pairs(Game.recruits_data) do
        if (not recruit:getHidden() or include_hidden) and (recruit:getRecruited() == true or include_incomplete and type(recruit:getRecruited()) == "number" and recruit:getRecruited() > 0) then
            table.insert(recruits, recruit)
        end
    end
    table.sort(recruits, function(a,b) return a.index < b.index end)
    return recruits
end

---@param recruit string
---@return boolean
function Game:hasRecruit(recruit)
    return self:getRecruit(recruit):getRecruited() == true
end

---@param chara     string|PartyMember
---@param index?    any
---@return any
function Game:addPartyMember(chara, index)
    if type(chara) == "string" then
        chara = self:getPartyMember(chara)
    end
    if index then
        table.insert(self.party, index, chara)
    else
        table.insert(self.party, chara)
    end
    return chara
end

---@param chara string|PartyMember
---@return PartyMember?
function Game:removePartyMember(chara)
    if type(chara) == "string" then
        chara = self:getPartyMember(chara)
    end
    Utils.removeFromTable(self.party, chara)
    return chara
end

---@param ... string|PartyMember
function Game:setPartyMembers(...)
    local args = {...}
    self.party = {}
    for i,chara in ipairs(args) do
        if type(chara) == "string" then
            self.party[i] = self:getPartyMember(chara)
        else
            self.party[i] = chara
        end
    end
end

---@param chara string|PartyMember
---@return boolean?
function Game:hasPartyMember(chara)
    if type(chara) == "string" then
        chara = self:getPartyMember(chara)
    end
    if chara then
        for _,party_member in ipairs(self.party) do
            if party_member.id == chara.id then
                return true
            end
        end
        return false
    end
end

---@param chara string|PartyMember
---@param index integer
---@return string|PartyMember
function Game:movePartyMember(chara, index)
    if type(chara) == "string" then
        chara = self:getPartyMember(chara)
    end
    self:removePartyMember(chara)
    self:addPartyMember(chara, index)
    return chara
end

---@param chara string|PartyMember
---@return integer
function Game:getPartyIndex(chara)
    if type(chara) == "string" then
        chara = self:getPartyMember(chara)
    end
    for i,party_member in ipairs(self.party) do
        if party_member.id == chara.id then
            return i
        end
    end
    return nil
end

---@param item_id string
---@return boolean
---@return integer
function Game:checkPartyEquipped(item_id)
    local success, count = false, 0
    for _,party in ipairs(self.party) do
        if party:checkWeapon(item_id) then
            success = true
            count = count + 1
        end
        local armor_success, armor_count = party:checkArmor(item_id)
        if armor_success then
            success = true
            count = count + armor_count
        end
    end
    return success, count
end

---@return PartyMember
function Game:getSoulPartyMember()
    ---@type PartyMember?
    local current
    for _,party in ipairs(self.party) do
        if not current or (party:getSoulPriority() > current:getSoulPriority()) then
            current = party
        end
    end
    return current
end

---@return integer
---@return integer
---@return integer
---@return integer
function Game:getSoulColor()
    local mr, mg, mb, ma = Kristal.callEvent(KRISTAL_EVENT.getSoulColor)
    if mr ~= nil then
        return mr, mg, mb, ma or 1
    end

    local chara = Game:getSoulPartyMember()

    if chara and chara:getSoulPriority() >= 0 then
        local r, g, b, a = chara:getSoulColor()
        return r, g, b, a or 1
    end

    return 1, 0, 0, 1
end

---@return string
function Game:getSoulFacing()
    if Game.state == "BATTLE" and Game.battle and Game.battle.encounter and Game.battle.encounter.getSoulFacing and Game.battle.encounter:getSoulFacing() then
        return Game.battle.encounter:getSoulFacing()
    end

    local face = Kristal.callEvent(KRISTAL_EVENT.getSoulFacing)
    if face ~= nil then
        return face
    end
    
    local chara = Game:getSoulPartyMember()
    
    if chara and chara:getSoulPriority() >= 0 and chara:getSoulFacing() then
        return chara:getSoulFacing()
    end
    
    return "up"
end

---@return PartyMember
function Game:getActLeader()
    for _,party in ipairs(self.party) do
        if party:hasAct() then
            return party
        end
    end
end

---@param chara  string|Follower
---@param index? integer
function Game:addFollower(chara, index)
    if isClass(chara) then
        chara = chara.actor.id
    end
    if index then
        table.insert(self.temp_followers, {chara, index})
    else
        table.insert(self.temp_followers, chara)
    end
end

---@param chara string|Follower
function Game:removeFollower(chara)
    if isClass(chara) then
        chara = chara.actor.id
    end
    for i,v in ipairs(self.temp_followers) do
        if type(v) == "table" then
            if v[1] == chara then
                table.remove(self.temp_followers, i)
                return
            end
        elseif v == chara then
            table.remove(self.temp_followers, i)
            return
        end
    end
end

---@param amount number
---@return number change
function Game:giveTension(amount)
    local start = self:getTension()
    self:setTension(self:getTension() + amount)
    if self:getTension() > self:getMaxTension() then
        Game:setTension(self:getMaxTension())
    end
    self:setTensionPreview(0)
    return self:getTension() - start
end

---@param amount number
function Game:setTensionPreview(amount)
    if Game.battle and Game.battle.tension_bar then
        Game.battle.tension_bar:setTensionPreview(amount)
    end
end

---@param amount number
---@return number change
function Game:removeTension(amount)
    local start = self:getTension()
    self:setTension(self:getTension() - amount)
    if self:getTension() < 0 then
        self:setTension(0)
    end
    self:setTensionPreview(0)
    return start - self:getTension()
end

---@param amount        number
---@param dont_clamp?   boolean
function Game:setTension(amount, dont_clamp)
    Game.tension = dont_clamp and amount or Utils.clamp(amount, 0, Game:getMaxTension())
end

---@return number
function Game:getTension()
    return self.tension or 0
end

---@param amount number
function Game:setMaxTension(amount)
    self.max_tension = amount
end

---@return number
function Game:getMaxTension()
    local max_tension = Game.max_tension or 100
    max_tension = max_tension + (50 * self:getBadgeEquipped("tension_plus"))
    return max_tension
end

-- [Kristal.swapIntoMod](lua://Kristal.swapIntoMod) but it happens after update
function Game:swapIntoMod(...)
    self.swap_into_mod = {...}
end

function Game:update()
    if self.state == "EXIT" then
        self.fader:update()
        return
    end

    if not self.started then
        self.started = true
        self.lock_movement = false
        if self.world.player then
            self.world.player.visible = true
        end
        for _,follower in ipairs(self.world.followers) do
            follower.visible = true
        end
    end

    if Kristal.callEvent(KRISTAL_EVENT.preUpdate, DT) then
        return
    end

    if (self.state == "BATTLE" and self.battle and self.battle:isWorldHidden()) or
       (self.state == "SHOP"   and self.shop) then
        self.world.active = false
        self.world.visible = false
    else
        self.world.active = true
        self.world.visible = true
    end

    self.playtime = self.playtime + DT

    self.stage:update()

    if Gamestate.current() == self then -- HACK
        if not self.shop and not self.battle and not (self.world and self.world.map and self.world.map.id) then
            if self.nothing_warn then Kristal.Console:warn("No map, shop nor encounter were loaded") end
            if Kristal.getModOption("hardReset") then
                love.event.quit("restart")
            else
                Kristal.returnToMenu()
            end
        else
            self.nothing_warn = false
        end
    end

    Kristal.callEvent(KRISTAL_EVENT.postUpdate, DT)

    self:updateTaunt()
    self:updateBattleTaunt()

    if self.save_name == "MERG" then
        for _, party in ipairs(self.party) do
            if party.health > 1 then
                party.health = 1
            end
            if party.stats.health ~= 1 then
                party.stats.health = 1
            end
        end
        if self.battle then
            self.battle:targetAll()
            for _,enemy in ipairs(self.battle:getActiveEnemies()) do
                enemy.current_target = "ALL"
            end
        end
    end

    for _, badge in ipairs(self:getBadgeStorage()) do
        badge:update(badge.equipped)
    end

    if self.swap_into_mod then
        Kristal.swapIntoMod(unpack(self.swap_into_mod))
        self.swap_into_mod = nil
    end
end

---@param key       string
---@param is_repeat boolean
function Game:onKeyPressed(key, is_repeat)
    if Kristal.callEvent(KRISTAL_EVENT.onKeyPressed, key, is_repeat) then
        -- Mod:onKeyPressed returned true, cancel default behaviour
        return
    end

    if is_repeat and not self.key_repeat then
        -- Ignore key repeat unless enabled by a game state
        return
    end

    if self.state == "BATTLE" then
        if self.battle then
            self.battle:onKeyPressed(key)
        end
    elseif self.state == "OVERWORLD" then
        if self.world then
            self.world:onKeyPressed(key)
        end
	elseif self.state == "MINIGAME" then
        if self.minigame then
            self.minigame:onKeyPressed(key)
        end
    elseif self.state == "SHOP" then
        if self.shop then
            self.shop:onKeyPressed(key, is_repeat)
        end
    elseif self.state == "GAMEOVER" then
        if self.gameover then
            self.gameover:onKeyPressed(key)
        end
    end
end

---@param key string
function Game:onKeyReleased(key)
    Kristal.callEvent(KRISTAL_EVENT.onKeyReleased, key)
end

---@param x integer
---@param y integer
function Game:onWheelMoved(x, y)
    Kristal.callEvent(KRISTAL_EVENT.onWheelMoved, x, y)
end

function Game:draw()
    love.graphics.clear(0, 0, 0, 1)
    love.graphics.push()
    if Kristal.callEvent(KRISTAL_EVENT.preDraw) then
        love.graphics.pop()
        return
    end
    love.graphics.pop()

    self.stage:draw()

    love.graphics.push()
    Kristal.callEvent(KRISTAL_EVENT.postDraw)
    love.graphics.pop()
end

---@param ignore_light? boolean -- if you still want some stats etc. despite being in LW
function Game:getBadgeStorage(ignore_light)
    if self:isLight() and not ignore_light then return {} end
    local inventory ---@type DarkInventory
    if not self:isLight() then
        inventory = self.inventory
    else
        inventory = self.dark_inventory
    end
    if not inventory then return {} end
    return inventory:getStorage("badges")
end

---@return {mod: string, encounter: string} boss?
function Game:getBossRef(id)
    for mod_id, mod in pairs(Kristal.Mods.data) do
        if mod.dlc and mod.dlc.bosses then
            if mod.dlc.bosses[id] then
                local t = Utils.copy(mod.dlc.bosses[id])
                t.mod = t.mod or mod_id
                return t
            end
        end
    end
end

function Game:getUsedBadgePoints(ignore_light)
    local total_bp = 0
    for _, badge in ipairs(Game:getBadgeStorage(ignore_light)) do
        if badge.equipped then
            total_bp = total_bp + badge:getBadgePoints()
        end
    end
    return total_bp
end

function Game:getBadgeEquipped(badge, ignore_light)
    local total_count = 0
    for _, b in ipairs(Game:getBadgeStorage(ignore_light)) do
        if b.equipped and b.id == badge then
            total_count = total_count + 1
        end
    end
    return total_count
end

--- Taunt Mechanic
function Game:isTauntingAvaliable()
    if self.let_me_taunt then return true end
    if self.save_name:upper() == "PEPPINO" then return true end

    for _,party in ipairs(self.party) do
        if party:checkArmor("pizza_toque") then return true end
    end
    return false
end

--Overworld taunt
function Game:initTaunt()
    self.taunt_lock_movement = false
    --[[
	Utils.hook(Actor, "init", function(orig, self)
        orig(self)
        self.taunt_sprites = {}
    end)
	--]]
    Utils.hook(Player, "isMovementEnabled",
        ---@overload fun(orig:function, self:Player) : boolean
        function(orig, self)
            return orig(self)
                and not Game.taunt_lock_movement
        end
    )

end

function Game:updateTaunt()
    if not (OVERLAY_OPEN or TextInput.active)
        and self:isTauntingAvaliable()
        and Input.pressed("taunt", false)
        and not self.taunt_lock_movement
        and (self.state == "OVERWORLD" and self.world.state == "GAMEPLAY"
            and not self.world:hasCutscene() and not self.lock_movement)
    then
        -- awesome workaround for run_anims
        self.world.player:setState("WALK")
        self.world.player.running = false
        for _, follower in ipairs(self.world.followers) do
            if follower:getTarget() == self.world.player and follower.state == "RUN" then
                follower.state_manager:setState("WALK")
                follower.running = false
            end
        end
        self.world.player:resetFollowerHistory()
        self.taunt_lock_movement = true

        Assets.playSound("taunt", 0.5, Utils.random(0.9, 1.1))

        for _,chara in ipairs(self.stage:getObjects(Character)) do
            if not chara.actor or not chara.visible then goto continue end

            -- workaround due to actors being loaded first by registry
            local sprites = chara.actor.getTauntSprites and chara.actor:getTauntSprites() or chara.actor.taunt_sprites
            if not sprites or #sprites <= 0 then goto continue end

            local shine = Sprite("effects/taunt", chara:getRelativePos(chara.width/2, chara.height/2))
            shine:setOrigin(0.5, 0.5)
            shine:setScale(1)
			chara.layer = chara.layer + 0.1
            shine.layer = chara.layer - 0.1
            self.world:addChild(shine)

            chara.sprite:set(Utils.pick(sprites))
            shine:play(1/30, false, function()
                shine:remove()
                chara:resetSprite()
			    chara.layer = chara.layer - 0.1
            end)

            ::continue::
        end

        self.world.timer:after(1/3, function()
            self.taunt_lock_movement = false
        end)
    end
end

--Battle taunt
function Game:initBattleTaunt()
    self.taunt_cooldown = 0
    self.state_blacklist = {
        "DEFENDINGBEGIN",
        "DEFENDING", -- handled by the soul itself, so this is ignored
        "DEFENDINGEND",
        "ENEMYDIALOGUE",
        "ATTACKING",
        "ACTIONS",
        "ACTIONSDONE",
        "INTRO",
        "TRANSITION",
        "TRANSITIONOUT"
    }
end

function Game:updateBattleTaunt()
    if
        self:isTauntingAvaliable()
        and Input.pressed("taunt", false)
        and self.taunt_cooldown == 0
        and (Game.state == "BATTLE" and not Game.battle:hasCutscene())
        and not Utils.containsValue(self.state_blacklist, Game.battle.state)
        and not (OVERLAY_OPEN or TextInput.active)
    then
        self.taunt_cooldown = 2.1

        Assets.playSound("taunt", 0.5, Utils.random(0.9, 1.1))

        for _,chara in ipairs(Game.battle.party) do
            if not chara.actor or chara.is_down then goto continue end

            -- workaround due of actors being loaded first by registry
            local sprites = chara.actor.getTauntSprites and chara.actor:getTauntSprites() or chara.actor.taunt_sprites
            if not sprites or #sprites <= 0 then goto continue end

            local shine = Sprite("effects/taunt", chara:getRelativePos(chara.width/2, chara.height/2))
            shine:setOrigin(0.5, 0.5)
            shine:setScale(1)
            shine.layer = chara.layer - 0.1
            Game.battle:addChild(shine)

            chara:toggleOverlay(true)
            chara.overlay_sprite:setSprite(Utils.pick(sprites))
            shine:play(1/30, false, function()
                shine:remove()
                chara:toggleOverlay(false)
            end)

            ::continue::
        end

    end

    self.taunt_cooldown = Utils.approach(self.taunt_cooldown, 0, DT)
end


--stuff for Noel the Noel-body

local save_dir = "saves"
local n_save = "saves/null.char"

function Game:saveNoel(new_data)
    if Kristal.temp_save == true then
    else

    local data = self:loadNoel() or {}
    if new_data then
        for k, v in pairs(new_data) do
            data[k] = v
        end
    end

    love.filesystem.createDirectory(save_dir)
    love.filesystem.write(n_save, JSON.encode(data))

    end
end

function Game:loadNoel()
    if Kristal.temp_save == true then
    else
    if love.filesystem.getInfo(n_save) then
        return JSON.decode(love.filesystem.read(n_save))
    end
    end
    return nil
end

function Game:getGlobalFlag(flag, default)
    local flags

    if love.filesystem.getInfo("saves/global_flags.json") then
        flags = JSON.decode(love.filesystem.read("saves/global_flags.json"))
    else
        return false
    end

    local result = flags[flag]
    if result == nil then
        return default
    else
        return result
    end
end

function Game:setGlobalFlag(flag_name, value)
    local data
    if love.filesystem.getInfo("saves/global_flags.json") then
        data = JSON.decode(love.filesystem.read("saves/global_flags.json"))
    else
        data = {}
    end


    local new_data = {[flag_name] = value}
    if new_data then
        for k, v in pairs(new_data) do
            data[k] = v
        end
    end

    love.filesystem.write("saves/global_flags.json", JSON.encode(data))
end

function Game:getUISkin()
    return Game:isLight() and "light" or "dark"
end

function Game:unlockPartyMember(member)
    Kristal.callEvent(KRISTAL_EVENT.onDPUnlockPartyMember, member)
    local currentUnlockedParty = Game:getFlag("_unlockedPartyMembers")
    if Game:getPartyMember(member) then
        table.insert(currentUnlockedParty, member)
        Game:setFlag("_unlockedPartyMembers", currentUnlockedParty)
    else
        error("Could not find any existing party member with id \""..member.."\".")
    end
end

function Game:getUnlockedPartyMembers()
    return Game:getFlag("_unlockedPartyMembers")
end

--- Checks if you have a party member unlocked and returns true if you do. Returns false otherwise
---@param member string -- the party member ID to check for
function Game:hasUnlockedPartyMember(member)
    for i, v in ipairs(Game:getUnlockedPartyMembers()) do
        if v == member then
            return true
        end
    end
    return false
end

function Game:getQuest(id)
    return self.quests_data[id]
end

--- Checks if you have a certain DLC installed and returns true if you do. Returns false otherwise
---@param dlc string -- the DLC ID to check for
function Game:hasDLC(dlc)
    local dlcs = Utils.filter(Kristal.Mods.getMods(), function(mod) return not mod.hidden end)
    for i, v in ipairs(dlcs) do
        if v.id == dlc then
            return true
        end
    end
    return false
end

function Game:isDessMode()
    if Game:getFlag("Dess_Mode") then
        return true
    else
        return false
    end
end

--- Debug function -
--- Unlocks every party member (Except for Noel since their unlock mechanics are weird)
function Game:unlockAllPartyMembers()
    local unlock = {"berdly", "brenda", "ceroba", "ddelta", "dess", "hero", "jamm", "kris", "mario", "nelle", "noelle", "ostarwalker", "pauling", "ralsei", "susie"}
    for i, v in ipairs(unlock) do
        Game:unlockPartyMember(v)
    end
end

---@param name string
function Game:isSpecialMode(name)
    if Game.save_name:upper() == "EVERYCHALLEN" and name ~= "DESS" then return true end
    if Game.save_name:upper() == "NIGHTMAREWAD" then return true end
    return Game.save_name:upper() == name:upper()
end

return Game