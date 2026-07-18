local util = require("util")
local fire = util.table.deepcopy(data.raw.fire["fire-flame"])
fire.initial_lifetime = 3000
fire.name = "oil-fire-flame"
fire.damage_per_tick = { amount = 1, type = "fire" }
local item_fire = util.table.deepcopy(data.raw.fire["fire-flame"])
item_fire.name = "flammable-item-fire-flame"
item_fire.localised_name = {"entity-name.flammable-item-fire-flame"}
item_fire.initial_lifetime = 300
item_fire.maximum_lifetime = 1200
item_fire.damage_per_tick = { amount = 0.5, type = "fire" }
---@diagnostic disable-next-line: assign-type-mismatch
data:extend({fire, item_fire})

local fire_created_trigger = {
  type = "direct",
  action_delivery = {
    type = "instant",
    source_effects = {
      {
        type = "script",
        effect_id = "flammable-oils-fire-created",
      },
    },
  },
}

local function append_created_trigger(prototype)
  if not prototype then
    return
  end

  if not prototype.created_effect then
    prototype.created_effect = util.table.deepcopy(fire_created_trigger)
    return
  end

  if prototype.created_effect.type then
    prototype.created_effect = {
      prototype.created_effect,
      util.table.deepcopy(fire_created_trigger),
    }
  else
    table.insert(prototype.created_effect, util.table.deepcopy(fire_created_trigger))
  end
end

append_created_trigger(data.raw.fire["fire-flame"])
append_created_trigger(data.raw.fire["fire-flame-on-tree"])
append_created_trigger(data.raw.fire["oil-fire-flame"])

--note:
--base pipes have 100 hp and 70% fire resist
--undergrounds have 150 hp and 80% fire resist
--as such we need 150 / (1 - 0.8) = 750 fire damage to guarantee destruction



local fuel_values = {
  ["crude-oil"] = "0.4MJ",
  ["light-oil"] = "0.9MJ",
  ["heavy-oil"] = "0.45MJ",
  ["petroleum-gas"] = "0.45MJ",
  ["diesel-fuel"] = "1.1MJ",
}
local emissions = {
  ["crude-oil"] = 1.4,
  ["light-oil"] = 1.2,
  ["heavy-oil"] = 1.3,
  ["petroleum-gas"] = 1,
  ["diesel-fuel"] = 0.8,
  ["molten-tiberium"] = 2.1,
  ["tiberium-waste"] = 1.2,
  ["tiberium-sludge"] = 1.7,
  ["tiberium-slurry"] = 1.8,
  ["liquid-tiberium"] = 4,
  ["tiberium-slurry-blue"] = 3,
}

for _, fluid in pairs(data.raw.fluid) do
  if not fluid.fuel_value or fluid.fuel_value == "0J" then --All fluids have 0J fuel value by default
    fluid.fuel_value = fuel_values[fluid.name]
  end
  if not fluid.emissions_multiplier then --All fluids have 1.0 multiplier by default
    fluid.emissions_multiplier = emissions[fluid.name]
  end
end
