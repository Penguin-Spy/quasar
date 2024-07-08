--[[ registry.lua © Penguin_Spy 2024

  This Source Code Form is subject to the terms of the Mozilla Public
  License, v. 2.0. If a copy of the MPL was not distributed with this
  file, You can obtain one at http://mozilla.org/MPL/2.0/.
  This Source Code Form is "Incompatible With Secondary Licenses", as
  defined by the Mozilla Public License, v. 2.0.
]]

local SendBuffer = require "SendBuffer"
local util = require "util"

local Registry = {}

local registries_data = util.read_json("registries.json")

--
---@param registry_id identifier
---@return table<identifier, number>|table<number, identifier>
local function registry_to_2_way_map(registry_id)
  local reg = registries_data[registry_id].entries
  local map = {}
  for k, v in pairs(reg) do
    map[k] = v.protocol_id
    map[v.protocol_id] = k
  end
  return map
end

---@alias registry.entity_type identifier
---@alias registry.item identifier

Registry.entity_types = registry_to_2_way_map("minecraft:entity_type")  --[[@as table<registry.entity_type, number>|table<number, registry.entity_type>]]
Registry.items = registry_to_2_way_map("minecraft:item")

-- in registries.json
-- minecraft:entity_type
-- minecraft:block -- not block state! just 'minecraft:piston' etc.
-- minecraft:item
-- minecraft:menu  -- the type of screen on the client
-- minecraft:mob_effect -- potion effects
-- minecraft:potion   -- the type of potion item (awkward, turtle master, strong_harming)
-- minecraft:particle_effect
-- minecraft:sound_event

-- items.json contains every item and it's default components
-- blocks.json contains every combination of block states and its network id


----- Network registry data -----
-- These lists come from the existence of files in the vanilla/core data pack

-- Precomputes the network representation of a registry. All entries are sent with "Has data" = false
---@param identifier identifier
---@param entries identifier[]
---@return SendBuffer buffer  the network representation of the registry
local function generate_registry_for_network(identifier, entries)
  local buffer = SendBuffer():string(identifier):varint(#entries)
  for _, entry in ipairs(entries) do
    buffer:string(entry):boolean(false)  -- no data (assumes client has core/vanilla data already)
  end
  return buffer
end

local dimension_types = { "minecraft:overworld", "minecraft:overworld_caves", "minecraft:the_end", "minecraft:the_nether" }

local biomes = {
  "minecraft:badlands",
  "minecraft:bamboo_jungle",
  "minecraft:basalt_deltas",
  "minecraft:beach",
  "minecraft:birch_forest",
  "minecraft:cherry_grove",
  "minecraft:cold_ocean",
  "minecraft:crimson_forest",
  "minecraft:dark_forest",
  "minecraft:deep_cold_ocean",
  "minecraft:deep_dark",
  "minecraft:deep_frozen_ocean",
  "minecraft:deep_lukewarm_ocean",
  "minecraft:deep_ocean",
  "minecraft:desert",
  "minecraft:dripstone_caves",
  "minecraft:end_barrens",
  "minecraft:end_highlands",
  "minecraft:end_midlands",
  "minecraft:eroded_badlands",
  "minecraft:flower_forest",
  "minecraft:forest",
  "minecraft:frozen_ocean",
  "minecraft:frozen_peaks",
  "minecraft:frozen_river",
  "minecraft:grove",
  "minecraft:ice_spikes",
  "minecraft:jagged_peaks",
  "minecraft:jungle",
  "minecraft:lukewarm_ocean",
  "minecraft:lush_caves",
  "minecraft:mangrove_swamp",
  "minecraft:meadow",
  "minecraft:mushroom_fields",
  "minecraft:nether_wastes",
  "minecraft:ocean",
  "minecraft:old_growth_birch_forest",
  "minecraft:old_growth_pine_taiga",
  "minecraft:old_growth_spruce_taiga",
  "minecraft:plains",
  "minecraft:river",
  "minecraft:savanna",
  "minecraft:savanna_plateau",
  "minecraft:small_end_islands",
  "minecraft:snowy_beach",
  "minecraft:snowy_plains",
  "minecraft:snowy_slopes",
  "minecraft:snowy_taiga",
  "minecraft:soul_sand_valley",
  "minecraft:sparse_jungle",
  "minecraft:stony_peaks",
  "minecraft:stony_shore",
  "minecraft:sunflower_plains",
  "minecraft:swamp",
  "minecraft:taiga",
  "minecraft:the_end",
  "minecraft:the_void",
  "minecraft:warm_ocean",
  "minecraft:warped_forest",
  "minecraft:windswept_forest",
  "minecraft:windswept_gravelly_hills",
  "minecraft:windswept_hills",
  "minecraft:windswept_savanna",
  "minecraft:wooded_badlands"
}

---@alias registry.chat_type
---| '"minecraft:chat"'

local chat_types = { "minecraft:chat", "minecraft:emote_command", "minecraft:msg_command_incoming", "minecraft:msg_command_outgoing", "minecraft:say_command", "minecraft:team_msg_command_incoming", "minecraft:team_msg_command_outgoing" }

local trim_patterns = {
  "minecraft:bolt",
  "minecraft:coast",
  "minecraft:dune",
  "minecraft:eye",
  "minecraft:flow",
  "minecraft:host",
  "minecraft:raiser",
  "minecraft:rib",
  "minecraft:sentry",
  "minecraft:shaper",
  "minecraft:silence",
  "minecraft:snout",
  "minecraft:spire",
  "minecraft:tide",
  "minecraft:vex",
  "minecraft:ward",
  "minecraft:wayfinder",
  "minecraft:wild"
}

local trim_materials = {
  "minecraft:amethyst",
  "minecraft:copper",
  "minecraft:diamond",
  "minecraft:emerald",
  "minecraft:gold",
  "minecraft:iron",
  "minecraft:lapis",
  "minecraft:netherite",
  "minecraft:quartz",
  "minecraft:redstone"
}

-- these are missing vanilla values
local wolf_variants = { "minecraft:pale" }
local painting_variants = { "minecraft:burning_skull" }

local damage_types = {
  "minecraft:arrow",
  "minecraft:bad_respawn_point",
  "minecraft:cactus",
  "minecraft:campfire",
  "minecraft:cramming",
  "minecraft:dragon_breath",
  "minecraft:drown",
  "minecraft:dry_out",
  "minecraft:explosion",
  "minecraft:fall",
  "minecraft:falling_anvil",
  "minecraft:falling_block",
  "minecraft:falling_stalactite",
  "minecraft:fireball",
  "minecraft:fireworks",
  "minecraft:fly_into_wall",
  "minecraft:freeze",
  "minecraft:generic",
  "minecraft:generic_kill",
  "minecraft:hot_floor",
  "minecraft:in_fire",
  "minecraft:in_wall",
  "minecraft:indirect_magic",
  "minecraft:lava",
  "minecraft:lightning_bolt",
  "minecraft:magic",
  "minecraft:mob_attack",
  "minecraft:mob_attack_no_aggro",
  "minecraft:mob_projectile",
  "minecraft:on_fire",
  "minecraft:out_of_world",
  "minecraft:outside_border",
  "minecraft:player_attack",
  "minecraft:player_explosion",
  "minecraft:sonic_boom",
  "minecraft:spit",
  "minecraft:stalagmite",
  "minecraft:starve",
  "minecraft:sting",
  "minecraft:sweet_berry_bush",
  "minecraft:thorns",
  "minecraft:thrown",
  "minecraft:trident",
  "minecraft:unattributed_fireball",
  "minecraft:wind_charge",
  "minecraft:wither",
  "minecraft:wither_skull"
}

-- these are missing vanilla values
local banner_patterns = { "minecraft:base", "minecraft:border" }
local encahntments = { "minecraft:aqua_affinity" }
local jukebox_songs = { "minecraft:blocks" }

Registry.network_data = {
  dimension_type = generate_registry_for_network("minecraft:dimension_type", dimension_types),
  ["worldgen/biome"] = generate_registry_for_network("minecraft:worldgen/biome", biomes),
  chat_type = generate_registry_for_network("minecraft:chat_type", chat_types),
  trim_pattern = generate_registry_for_network("minecraft:trim_pattern", trim_patterns),
  trim_material = generate_registry_for_network("minecraft:trim_material", trim_materials),
  wolf_variant = generate_registry_for_network("minecraft:wolf_variant", wolf_variants),
  painting_variant = generate_registry_for_network("minecraft:painting_variant", painting_variants),
  damage_type = generate_registry_for_network("minecraft:damage_type", damage_types),
  banner_pattern = generate_registry_for_network("minecraft:banner_pattern", banner_patterns),
  enchantment = generate_registry_for_network("minecraft:enchantment", encahntments),
  jukebox_song = generate_registry_for_network("minecraft:jukebox_song", jukebox_songs)
}

return Registry
