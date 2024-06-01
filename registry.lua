local NBT = require "nbt"

local damage_types = {}
local damage_type_names = { "in_fire", "lightning_bolt", "on_fire", "lava", "hot_floor", "in_wall", "cramming", "drown", "starve", "cactus", "fall", "fly_into_wall", "out_of_world", "generic", "magic", "wither", "dragon_breath", "dry_out", "sweet_berry_bush", "freeze", "stalagmite", "outside_border", "generic_kill" }

for _, name in pairs(damage_type_names) do
  table.insert(damage_types, {
    name = "minecraft:" .. name,
    id = NBT.int(0),
    element = {
      message_id = "death.attack." .. name,
      scaling = "never",
      exhaustion = NBT.float(0.0),
      effects = "hurt"
    }
  })
end

return NBT.compound{
  ["minecraft:worldgen/biome"] = {
    type = "minecraft:worldgen/biome",
    value = {
      {
        name = "minecraft:plains",
        id = NBT.int(0),
        element = {
          has_precipitation = true,
          temperature = NBT.float(0.5),
          downfall = NBT.float(0.5),
          effects = {
            fog_color = NBT.int(8364543),
            water_color = NBT.int(8364543),
            water_fog_color = NBT.int(8364543),
            sky_color = NBT.int(8364543)
            -- a bunch of optional values are omitted
          }
        }
      },
    },
  },
  ["minecraft:dimension_type"] = {
    type = "minecraft:dimension_type",
    value = {
      {
        name = "minecraft:overworld",
        id = NBT.int(0),
        element = {
          has_skylight = true,
          has_ceiling = false,
          ultrawarm = false,
          natural = true,
          coordinate_scale = NBT.double(1),
          bed_works = true,
          respawn_anchor_works = false,
          min_y = NBT.int(0),
          height = NBT.int(256),
          logical_height = NBT.int(256),
          infiniburn = "#minecraft:infiniburn_overworld",
          effects = "minecraft:overworld",
          ambient_light = NBT.float(0.0),
          piglin_safe = false,
          has_raids = true,
          monster_spawn_light_level = NBT.int(0),
          monster_spawn_block_light_limit = NBT.int(0)
        }
      }
    }
  },
  ["minecraft:damage_type"] = {
    type = "minecraft:damage_type",
    value = damage_types
  }
}
