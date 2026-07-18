local JOULES_PER_MJ = 1000000
local TICKS_PER_SECOND = 60

local flammable_types = {}
local gas_types = {}
local fluid_energy_joules = {}
local configured_whitelist = {}
local configured_blacklist = {}
local whitelist_enabled = false

local damage_chance_settings = {
  fire = "flo-chance-fire",
  explosion = "flo-chance-explosion",
  acid = "flo-chance-acid",
  electric = "flo-chance-electric",
  laser = "flo-chance-laser",
  physical = "flo-chance-physical",
  impact = "flo-chance-impact",
  poison = "flo-chance-poison",
}

local production_entity_types = {
  ["agricultural-tower"] = true,
  ["assembling-machine"] = true,
  boiler = true,
  ["burner-generator"] = true,
  furnace = true,
  generator = true,
  ["fusion-generator"] = true,
  ["fusion-reactor"] = true,
  lab = true,
  ["mining-drill"] = true,
  reactor = true,
  ["rocket-silo"] = true,
}

local flammable_types_override = {
  ["crude-oil"] = true,
  ["heavy-oil"] = true,
  ["light-oil"] = true,
  lubricant = false,
  ["gas-hydrogen"] = true,
  ["gas-methane"] = true,
  ["gas-ethane"] = true,
  ["gas-butane"] = true,
  ["gas-propene"] = true,
  ["liquid-naphtha"] = true,
  ["liquid-mineral-oil"] = true,
  ["liquid-fuel-oil"] = true,
  ["gas-methanol"] = true,
  ["gas-ethylene"] = true,
  ["gas-benzene"] = true,
  ["gas-synthesis"] = true,
  ["gas-butadiene"] = true,
  ["gas-phenol"] = true,
  ["gas-ethylbenzene"] = true,
  ["gas-styrene"] = true,
  ["gas-formaldehyde"] = true,
  ["gas-polyethylene"] = true,
  ["gas-glycerol"] = true,
  ["gas-natural-1"] = true,
  ["liquid-multi-phase-oil"] = true,
  ["gas-raw-1"] = true,
  ["liquid-condensates"] = true,
  ["liquid-ngl"] = true,
  ["gas-chlor-methane"] = true,
  hydrogen = true,
  ["liquid-fuel"] = true,
  ["diesel-fuel"] = true,
  ["petroleum-gas"] = true,
  water = false,
  ["sulfuric-acid"] = false,
  ["molten-tiberium"] = true,
  ["tiberium-waste"] = false,
  ["tiberium-sludge"] = false,
  ["tiberium-slurry"] = false,
  ["liquid-tiberium"] = true,
  ["tiberium-slurry-blue"] = false,
  ["cubeine-solution"] = false,
}

local gas_types_override = {
  ["liquid-cubonium"] = true,
}

-- Used when a prototype does not supply a fuel value. Values are MJ per fluid unit.
local built_in_energy_mj = {
  ["crude-oil"] = 0.4,
  ["light-oil"] = 0.9,
  ["heavy-oil"] = 0.45,
  ["petroleum-gas"] = 0.45,
  ["diesel-fuel"] = 1.1,
  ["liquid-fuel"] = 1.1,
}

local FIRE_CREATED_EFFECT_ID = "flammable-oils-fire-created"
local SOLID_SCAN_RADIUS = 1.25
local SOLID_FIRE_ACTIVE_TICKS = 600
local SOLID_EMPTY_RECHECK_TICKS = 60

local barrel_contents = {}

local solid_item_profiles = {
  wood = {
    setting = "flo-enable-wood-fires",
    delay = 15,
    pollution = 0.015,
    priority = 10,
  },
  coal = {
    setting = "flo-enable-coal-fires",
    delay = 60,
    pollution = 0.08,
    priority = 20,
  },
  ["solid-fuel"] = {
    setting = "flo-enable-solid-fuel-fires",
    delay = 20,
    pollution = 0.04,
    priority = 30,
  },
  ["rocket-fuel"] = {
    setting = "flo-enable-rocket-fuel-fires",
    delay = 30,
    pollution = 0.08,
    priority = 60,
    explosive = true,
    fallback_energy_mj = 100,
  },
  ["flamethrower-ammo"] = {
    setting = "flo-enable-flamethrower-ammo-fires",
    delay = 20,
    pollution = 0.08,
    priority = 70,
    explosive = true,
    fallback_energy_mj = 25,
  },
}

local cargo_inventory_by_entity_type = {
  container = defines.inventory.chest,
  ["logistic-container"] = defines.inventory.chest,
  ["infinity-container"] = defines.inventory.chest,
  ["linked-container"] = defines.inventory.linked_container_main,
  ["cargo-wagon"] = defines.inventory.cargo_wagon,
}

local belt_entity_types = {
  "transport-belt",
  "underground-belt",
  "splitter",
  "loader",
  "loader-1x1",
  "linked-belt",
  "lane-splitter",
}

local function new_queue()
  return {
    items = {},
    head = 1,
    tail = 0,
  }
end

local function normalize_queue(queue)
  queue.items = queue.items or {}
  queue.head = queue.head or 1
  queue.tail = queue.tail or #queue.items
  return queue
end

local function push_queue(queue, value)
  queue.tail = queue.tail + 1
  queue.items[queue.tail] = value
end

local function compact_queue(queue)
  if queue.head > queue.tail then
    queue.items = {}
    queue.head = 1
    queue.tail = 0
    return
  end

  if queue.head > 1024 and queue.head > queue.tail / 2 then
    local compacted = {}
    local count = 0
    for index = queue.head, queue.tail do
      count = count + 1
      compacted[count] = queue.items[index]
    end
    queue.items = compacted
    queue.head = 1
    queue.tail = count
  end
end

local function ensure_storage()
  storage.fluid_overrides = storage.fluid_overrides or {}
  storage.fluid_overrides.flammable = storage.fluid_overrides.flammable or {}
  storage.fluid_overrides.gas = storage.fluid_overrides.gas or {}
  storage.fluid_overrides.energy_mj = storage.fluid_overrides.energy_mj or {}

  storage.scheduled_explosions = storage.scheduled_explosions or {}
  storage.ready_explosions = normalize_queue(storage.ready_explosions or new_queue())
  storage.scheduled_solid_scans = storage.scheduled_solid_scans or {}
  storage.ready_solid_scans = normalize_queue(storage.ready_solid_scans or new_queue())
  storage.active_solid_cells = storage.active_solid_cells or {}

  -- Migrate requests saved by earlier development builds.
  if storage.pending_explosions then
    for _, explosion in ipairs(storage.pending_explosions) do
      push_queue(storage.ready_explosions, explosion)
    end
    storage.pending_explosions = nil
  end
end

local function parse_name_list(value)
  local names = {}
  for name in string.gmatch(value or "", "[^,%s;]+") do
    names[name] = true
  end
  return names
end

local function refresh_configured_fluid_filters()
  configured_whitelist = parse_name_list(settings.global["flo-fluid-whitelist"].value)
  configured_blacklist = parse_name_list(settings.global["flo-fluid-blacklist"].value)
  whitelist_enabled = next(configured_whitelist) ~= nil
end

local function init_fluid_types()
  flammable_types = {}
  gas_types = {}
  fluid_energy_joules = {}

  for name, fluid in pairs(prototypes.fluid) do
    local prototype_energy = fluid.fuel_value or 0
    flammable_types[name] = prototype_energy > 0
    fluid_energy_joules[name] = prototype_energy

    if prototype_energy <= 0 and built_in_energy_mj[name] then
      fluid_energy_joules[name] = built_in_energy_mj[name] * JOULES_PER_MJ
    end

    local name_looks_gaseous =
      string.find(name, "gasoline", 1, true) == nil
      and (
        string.find(name, "-gas", 1, true) ~= nil
        or string.find(name, "gas-", 1, true) ~= nil
      )

    gas_types[name] =
      (fluid.gas_temperature and fluid.default_temperature > fluid.gas_temperature)
      or name_looks_gaseous
  end

  for name, value in pairs(flammable_types_override) do
    flammable_types[name] = value
  end

  for name, value in pairs(gas_types_override) do
    gas_types[name] = value
  end

  local saved_overrides = storage.fluid_overrides
  if saved_overrides then
    for name, value in pairs(saved_overrides.flammable or {}) do
      flammable_types[name] = value
    end
    for name, value in pairs(saved_overrides.gas or {}) do
      gas_types[name] = value
    end
  end
end

local function prototype_amount(entry)
  if entry.amount then
    return entry.amount
  end
  if entry.amount_min and entry.amount_max then
    return (entry.amount_min + entry.amount_max) / 2
  end
  return 0
end

local function is_empty_barrel_ingredient(item_name)
  return item_name == "barrel"
    or item_name == "empty-barrel"
    or (
      string.find(item_name, "empty", 1, true) ~= nil
      and string.match(item_name, "%-barrel$") ~= nil
    )
end

local function init_barrel_contents()
  barrel_contents = {}

  for _, recipe in pairs(prototypes.recipe) do
    local fluid_ingredient
    local has_empty_barrel_ingredient = false
    for _, ingredient in pairs(recipe.ingredients) do
      if ingredient.type == "fluid" and prototype_amount(ingredient) > 0 then
        if fluid_ingredient then
          fluid_ingredient = nil
          break
        end
        fluid_ingredient = ingredient
      elseif ingredient.type == "item"
        and prototype_amount(ingredient) > 0
        and is_empty_barrel_ingredient(ingredient.name)
      then
        has_empty_barrel_ingredient = true
      end
    end

    if fluid_ingredient and has_empty_barrel_ingredient then
      for _, product in pairs(recipe.products) do
        local product_amount = prototype_amount(product)
        if product.type == "item"
          and product_amount > 0
          and string.match(product.name, "%-barrel$")
          and prototypes.item[product.name]
        then
          barrel_contents[product.name] = {
            fluid_name = fluid_ingredient.name,
            amount = prototype_amount(fluid_ingredient) / product_amount,
          }
        end
      end
    end
  end

  -- Follow the standard barreling convention for modded fluids whose recipes
  -- are generated in an unusual way that was not visible in the scan above.
  for item_name in pairs(prototypes.item) do
    if item_name ~= "empty-barrel" and not barrel_contents[item_name] then
      local fluid_name = string.match(item_name, "^(.*)%-barrel$")
      if fluid_name and prototypes.fluid[fluid_name] then
        barrel_contents[item_name] = {
          fluid_name = fluid_name,
          amount = 50,
        }
      end
    end
  end
end

local function initialise()
  ensure_storage()
  init_fluid_types()
  init_barrel_contents()
  refresh_configured_fluid_filters()
end

script.on_init(initialise)
script.on_configuration_changed(initialise)

-- Local lookup tables are not persisted in saves, so rebuild them on load.
script.on_load(function()
  init_fluid_types()
  init_barrel_contents()
  refresh_configured_fluid_filters()
end)

script.on_event(defines.events.on_runtime_mod_setting_changed, function(event)
  if event.setting == "flo-fluid-whitelist" or event.setting == "flo-fluid-blacklist" then
    refresh_configured_fluid_filters()
  end

  if event.setting == "flo-enable-solid-items"
    and not settings.global["flo-enable-solid-items"].value
  then
    ensure_storage()
    storage.scheduled_solid_scans = {}
    storage.ready_solid_scans = new_queue()
    storage.active_solid_cells = {}
  end
end)

local function validate_fluid_name(name)
  if type(name) ~= "string" or not prototypes.fluid[name] then
    error("Unknown fluid prototype: " .. tostring(name))
  end
end

local function validate_energy(energy_mj)
  if type(energy_mj) ~= "number" or energy_mj < 0 then
    error("Fluid energy must be a non-negative number in MJ per fluid unit")
  end
end

local function set_saved_override(group, name, value)
  validate_fluid_name(name)
  ensure_storage()
  storage.fluid_overrides[group][name] = value
  init_fluid_types()
end

local function reset_saved_override(group, name)
  validate_fluid_name(name)
  ensure_storage()
  storage.fluid_overrides[group][name] = nil
  init_fluid_types()
end

local function get_fluid_energy_joules(name)
  local saved_energy = storage.fluid_overrides
    and storage.fluid_overrides.energy_mj
    and storage.fluid_overrides.energy_mj[name]

  if saved_energy ~= nil then
    return saved_energy * JOULES_PER_MJ
  end

  local energy = fluid_energy_joules[name] or 0
  if energy > 0 then
    return energy
  end

  return settings.global["flo-default-energy-mj"].value * JOULES_PER_MJ
end

remote.add_interface("flammable_oils", {
  add_flammable_type = function(name, energy_mj)
    validate_fluid_name(name)
    ensure_storage()
    storage.fluid_overrides.flammable[name] = true
    if energy_mj ~= nil then
      validate_energy(energy_mj)
      storage.fluid_overrides.energy_mj[name] = energy_mj
    end
    init_fluid_types()
  end,
  remove_flammable_type = function(name)
    set_saved_override("flammable", name, false)
  end,
  reset_flammable_type = function(name)
    reset_saved_override("flammable", name)
  end,
  get_flammable_types = function()
    return flammable_types
  end,
  add_gas_type = function(name)
    set_saved_override("gas", name, true)
  end,
  remove_gas_type = function(name)
    set_saved_override("gas", name, false)
  end,
  reset_gas_type = function(name)
    reset_saved_override("gas", name)
  end,
  get_gas_types = function()
    return gas_types
  end,
  set_fluid_energy = function(name, energy_mj)
    validate_fluid_name(name)
    validate_energy(energy_mj)
    ensure_storage()
    storage.fluid_overrides.energy_mj[name] = energy_mj
  end,
  reset_fluid_energy = function(name)
    validate_fluid_name(name)
    ensure_storage()
    storage.fluid_overrides.energy_mj[name] = nil
  end,
  get_fluid_energy = function(name)
    validate_fluid_name(name)
    return get_fluid_energy_joules(name) / JOULES_PER_MJ
  end,
})

local function is_fluid_flammable(name)
  if configured_blacklist[name] then
    return false
  end
  if whitelist_enabled then
    return configured_whitelist[name] == true
  end
  return flammable_types[name] == true
end

local function get_solid_item_profile(item_name)
  local profile = solid_item_profiles[item_name]
  if profile then
    if settings.global[profile.setting].value then
      return profile
    end
    return nil
  end

  if not settings.global["flo-enable-filled-barrel-fires"].value then
    return nil
  end

  local barrel = barrel_contents[item_name]
  if not barrel or not is_fluid_flammable(barrel.fluid_name) then
    return nil
  end

  local energy_density = get_fluid_energy_joules(barrel.fluid_name)
  local fluid = prototypes.fluid[barrel.fluid_name]
  local emissions_multiplier = fluid and fluid.emissions_multiplier or 1

  return {
    delay = 30,
    priority = 50,
    pollution = energy_density / 1.8e6 * 0.5 * emissions_multiplier * barrel.amount / 1.5,
    explosive = true,
    energy_mj = energy_density * barrel.amount / JOULES_PER_MJ,
    damage_type = gas_types[barrel.fluid_name] and "explosion" or "fire",
    fluid_name = barrel.fluid_name,
  }
end

local function get_item_explosive_energy_mj(item_name, profile)
  if not profile.explosive then
    return 0
  end
  if profile.energy_mj then
    return profile.energy_mj
  end

  local item = prototypes.item[item_name]
  local fuel_value = item and item.fuel_value or 0
  if fuel_value > 0 then
    return fuel_value / JOULES_PER_MJ
  end
  return profile.fallback_energy_mj or 0
end

local function is_entity_enabled(entity_type)
  if entity_type == "pipe" or entity_type == "pipe-to-ground" then
    return settings.global["flo-enable-pipes"].value
  end
  if entity_type == "storage-tank" then
    return settings.global["flo-enable-storage-tanks"].value
  end
  if entity_type == "fluid-wagon" then
    return settings.global["flo-enable-fluid-wagons"].value
  end
  if entity_type == "pump" or entity_type == "offshore-pump" then
    return settings.global["flo-enable-pumps"].value
  end
  if production_entity_types[entity_type] then
    return settings.global["flo-enable-production-machines"].value
  end
  return settings.global["flo-enable-other-entities"].value
end

local function get_ignition_chance(damage_type_name)
  local setting_name = damage_chance_settings[damage_type_name] or "flo-chance-other"
  return settings.global[setting_name].value / 100
end

local function get_underground_neighbour_position(entity)
  if entity.type ~= "pipe-to-ground" then
    return nil
  end

  local best_neighbour
  local best_distance_squared = -1

  for _, neighbours in pairs(entity.fluidbox_neighbours) do
    for _, neighbour in pairs(neighbours) do
      if neighbour.valid and neighbour.type == "pipe-to-ground" and neighbour.unit_number ~= entity.unit_number then
        local dx = neighbour.position.x - entity.position.x
        local dy = neighbour.position.y - entity.position.y
        local distance_squared = dx * dx + dy * dy

        -- Prefer the distant underground connection over any adjacent surface connection.
        if distance_squared > best_distance_squared then
          best_neighbour = neighbour
          best_distance_squared = distance_squared
        end
      end
    end
  end

  if best_neighbour then
    return { x = best_neighbour.position.x, y = best_neighbour.position.y }
  end

  return nil
end

local function get_flammable_contents(entity)
  local total_energy = 0
  local gas_energy = 0
  local weighted_fraction = 0
  local pollution = 0

  for index = 1, entity.fluids_count do
    local contents = entity.get_fluid(index)
    if contents and contents.amount > 0 and is_fluid_flammable(contents.name) then
      local energy_density = get_fluid_energy_joules(contents.name)
      local energy = energy_density * contents.amount / JOULES_PER_MJ

      if energy > 0 then
        local capacity = entity.get_fluid_capacity(index)
        local fraction = capacity > 0 and contents.amount / capacity or 0
        fraction = math.max(0, math.min(fraction, 1))

        total_energy = total_energy + energy
        weighted_fraction = weighted_fraction + energy * fraction

        local fluid = prototypes.fluid[contents.name]
        local emissions_multiplier = fluid.emissions_multiplier or 1
        pollution = pollution
          + energy_density / 1.8e6 * 0.5 * emissions_multiplier * contents.amount / 1.5

        if gas_types[contents.name] then
          gas_energy = gas_energy + energy
        end
      end
    end
  end

  if total_energy <= settings.global["flo-min-energy-mj"].value then
    return nil
  end

  return {
    energy = total_energy,
    fraction = weighted_fraction / total_energy,
    pollution = pollution,
    damage_type = gas_energy >= total_energy / 2 and "explosion" or "fire",
  }
end

local function random_offset(radius)
  return (math.random() * 2 - 1) * radius
end

local function create_warning_smoke(surface, position, half_width, half_height)
  local count = math.max(1, math.min(6, math.ceil(math.max(half_width, half_height) * 2)))
  for _ = 1, count do
    surface.create_trivial_smoke({
      name = "smoke-fast",
      position = {
        position.x + random_offset(half_width),
        position.y + random_offset(half_height),
      },
    })
  end
end

local function schedule_flammable_explosion(entity, contents)
  ensure_storage()

  local position = entity.position
  local bounding_box = entity.bounding_box
  local half_width = math.max(
    position.x - bounding_box.left_top.x,
    bounding_box.right_bottom.x - position.x
  )
  local half_height = math.max(
    position.y - bounding_box.left_top.y,
    bounding_box.right_bottom.y - position.y
  )

  local explosion = {
    position = { x = position.x, y = position.y },
    surface_index = entity.surface.index,
    force_index = entity.force.index,
    half_width = half_width,
    half_height = half_height,
    entity_type = entity.type,
    underground_neighbour_position = get_underground_neighbour_position(entity),
    fraction = contents.fraction,
    pollution = contents.pollution,
    energy = contents.energy,
    damage_type = contents.damage_type,
  }

  local configured_delay = settings.global["flo-ignition-delay-seconds"].value
  local delay_ticks = math.floor(configured_delay * TICKS_PER_SECOND + 0.5)
  local due_tick = game.tick + math.max(1, delay_ticks)
  local scheduled = storage.scheduled_explosions[due_tick]
  if not scheduled then
    scheduled = {}
    storage.scheduled_explosions[due_tick] = scheduled
  end
  scheduled[#scheduled + 1] = explosion

  if delay_ticks > 0 then
    create_warning_smoke(entity.surface, position, half_width, half_height)
  end
end

local function get_solid_cargo_contents(entity)
  local inventory_index = cargo_inventory_by_entity_type[entity.type]
  if not inventory_index then
    return nil
  end

  local inventory = entity.get_inventory(inventory_index)
  if not inventory or not inventory.valid then
    return nil
  end

  local total_items = 0
  local pollution = 0
  local explosive_energy = 0
  local gas_energy = 0

  for _, item in pairs(inventory.get_contents()) do
    local profile = get_solid_item_profile(item.name)
    if profile and item.count > 0 then
      local energy = get_item_explosive_energy_mj(item.name, profile) * item.count
      total_items = total_items + item.count
      pollution = pollution + (profile.pollution or 0) * item.count
      explosive_energy = explosive_energy + energy

      if (profile.damage_type or "explosion") == "explosion" then
        gas_energy = gas_energy + energy
      end
    end
  end

  if total_items <= 0 then
    return nil
  end

  return {
    total_items = total_items,
    pollution = pollution,
    energy = explosive_energy,
    damage_type = explosive_energy > 0
      and gas_energy >= explosive_energy / 2
      and "explosion"
      or "fire",
  }
end

local function schedule_solid_cargo_reaction(entity, contents)
  ensure_storage()

  local position = entity.position
  local bounding_box = entity.bounding_box
  local half_width = math.max(
    position.x - bounding_box.left_top.x,
    bounding_box.right_bottom.x - position.x
  )
  local half_height = math.max(
    position.y - bounding_box.left_top.y,
    bounding_box.right_bottom.y - position.y
  )

  local reaction = {
    kind = "solid-cargo",
    position = { x = position.x, y = position.y },
    surface_index = entity.surface.index,
    force_index = entity.force.index,
    half_width = half_width,
    half_height = half_height,
    entity_type = entity.type,
    fraction = 1,
    pollution = contents.pollution,
    energy = contents.energy,
    damage_type = contents.damage_type,
    total_items = contents.total_items,
  }

  local configured_delay = settings.global["flo-ignition-delay-seconds"].value
  local delay_ticks = math.floor(configured_delay * TICKS_PER_SECOND + 0.5)
  local due_tick = game.tick + math.max(1, delay_ticks)
  local scheduled = storage.scheduled_explosions[due_tick]
  if not scheduled then
    scheduled = {}
    storage.scheduled_explosions[due_tick] = scheduled
  end
  scheduled[#scheduled + 1] = reaction

  if delay_ticks > 0 then
    create_warning_smoke(entity.surface, position, half_width, half_height)
  end
end

script.on_event(defines.events.on_entity_died, function(event)
  local entity = event.entity
  local fluid_enabled = is_entity_enabled(entity.type)
  local solid_cargo_enabled = settings.global["flo-enable-solid-items"].value
    and settings.global["flo-solid-items-in-containers"].value
    and cargo_inventory_by_entity_type[entity.type] ~= nil

  if not fluid_enabled and not solid_cargo_enabled then
    return
  end

  local damage_type = event.damage_type
  if not damage_type then
    return
  end

  local chance = get_ignition_chance(damage_type.name)
  if chance <= 0 or (chance < 1 and math.random() > chance) then
    return
  end

  if fluid_enabled then
    local contents = get_flammable_contents(entity)
    if contents then
      schedule_flammable_explosion(entity, contents)
    end
  end

  if solid_cargo_enabled then
    local cargo_contents = get_solid_cargo_contents(entity)
    if cargo_contents then
      schedule_solid_cargo_reaction(entity, cargo_contents)
    end
  end
end)

local function create_oil_fire(surface, position)
  surface.create_entity({
    name = "oil-fire-flame",
    position = position,
    raise_built = true,
  })
end

local function solid_cell_key(surface_index, position)
  local x = math.floor(position.x)
  local y = math.floor(position.y)
  return surface_index .. ":" .. x .. ":" .. y, x, y
end

local function schedule_solid_scan(cell, due_tick)
  cell.due_tick = due_tick
  local scheduled = storage.scheduled_solid_scans[due_tick]
  if not scheduled then
    scheduled = {}
    storage.scheduled_solid_scans[due_tick] = scheduled
  end
  scheduled[#scheduled + 1] = cell.key
end

local function activate_solid_cell(surface_index, position, tick, active_until)
  if not settings.global["flo-enable-solid-items"].value then
    return
  end

  ensure_storage()
  local key, x, y = solid_cell_key(surface_index, position)
  local cell = storage.active_solid_cells[key]
  if cell then
    cell.expires_tick = math.max(cell.expires_tick, active_until or tick + SOLID_FIRE_ACTIVE_TICKS)
    return
  end

  cell = {
    key = key,
    surface_index = surface_index,
    position = { x = x + 0.5, y = y + 0.5 },
    expires_tick = active_until or tick + SOLID_FIRE_ACTIVE_TICKS,
  }
  storage.active_solid_cells[key] = cell
  schedule_solid_scan(cell, tick + 1)
end

script.on_event(defines.events.on_script_trigger_effect, function(event)
  if event.effect_id ~= FIRE_CREATED_EFFECT_ID
    or not settings.global["flo-enable-solid-items"].value
  then
    return
  end

  local position = event.target_position or event.source_position
  if not position then
    local entity = event.target_entity or event.source_entity
    if entity and entity.valid then
      position = entity.position
    end
  end
  if position then
    activate_solid_cell(event.surface_index, position, event.tick)
  end
end)

local function candidate_is_better(candidate, best)
  if not best then
    return true
  end
  if candidate.profile.priority ~= best.profile.priority then
    return candidate.profile.priority > best.profile.priority
  end
  return candidate.distance_squared < best.distance_squared
end

local function find_ground_item_candidate(surface, position)
  if not settings.global["flo-solid-items-on-ground"].value then
    return nil
  end

  local best
  local entities = surface.find_entities_filtered({
    position = position,
    radius = SOLID_SCAN_RADIUS,
    type = "item-entity",
  })

  for _, entity in pairs(entities) do
    if entity.valid then
      local stack = entity.stack
      if stack and stack.valid_for_read then
        local profile = get_solid_item_profile(stack.name)
        if profile then
          local dx = entity.position.x - position.x
          local dy = entity.position.y - position.y
          local candidate = {
            stack = stack,
            item_name = stack.name,
            profile = profile,
            position = { x = entity.position.x, y = entity.position.y },
            distance_squared = dx * dx + dy * dy,
          }
          if candidate_is_better(candidate, best) then
            best = candidate
          end
        end
      end
    end
  end

  return best
end

local function line_was_seen(line, seen_lines)
  for _, seen in pairs(seen_lines) do
    if line.line_equals(seen) then
      return true
    end
  end
  seen_lines[#seen_lines + 1] = line
  return false
end

local function find_belt_item_candidate(surface, position)
  if not settings.global["flo-solid-items-on-belts"].value then
    return nil
  end

  local best
  local seen_lines = {}
  local seen_items = {}
  local entities = surface.find_entities_filtered({
    position = position,
    radius = SOLID_SCAN_RADIUS + 0.75,
    type = belt_entity_types,
  })

  for _, entity in pairs(entities) do
    if entity.valid then
      local maximum_line = entity.get_max_transport_line_index()
      for line_index = 1, maximum_line do
        local line = entity.get_transport_line(line_index)
        if line and not line_was_seen(line, seen_lines) then
          for _, item in pairs(line.get_detailed_contents()) do
            if not seen_items[item.unique_id]
              and item.stack.valid_for_read
            then
              seen_items[item.unique_id] = true
              local profile = get_solid_item_profile(item.stack.name)
              if profile then
                local item_position = line.get_line_item_position(item.position)
                local dx = item_position.x - position.x
                local dy = item_position.y - position.y
                local distance_squared = dx * dx + dy * dy

                if distance_squared <= SOLID_SCAN_RADIUS * SOLID_SCAN_RADIUS then
                  local candidate = {
                    stack = item.stack,
                    item_name = item.stack.name,
                    profile = profile,
                    position = { x = item_position.x, y = item_position.y },
                    distance_squared = distance_squared,
                  }
                  if candidate_is_better(candidate, best) then
                    best = candidate
                  end
                end
              end
            end
          end
        end
      end
    end
  end

  return best
end

local function consume_candidate(candidate)
  local stack = candidate.stack
  if not stack.valid or not stack.valid_for_read or stack.name ~= candidate.item_name then
    return false
  end

  if stack.count > 1 then
    stack.count = stack.count - 1
  else
    stack.clear()
  end
  return true
end

local function queue_solid_item_explosion(surface, position, item_name, profile)
  local energy = get_item_explosive_energy_mj(item_name, profile)
  if energy <= settings.global["flo-min-energy-mj"].value then
    return
  end

  ensure_storage()
  push_queue(storage.ready_explosions, {
    kind = "solid-item",
    position = { x = position.x, y = position.y },
    surface_index = surface.index,
    force_index = game.forces.neutral.index,
    half_width = 0.25,
    half_height = 0.25,
    entity_type = "solid-item",
    fraction = 1,
    pollution = 0,
    energy = energy,
    damage_type = profile.damage_type or "explosion",
  })
end

local function ignite_solid_candidate(surface, candidate)
  surface.create_entity({
    name = "flammable-item-fire-flame",
    position = candidate.position,
    force = "neutral",
  })

  local pollution = (candidate.profile.pollution or 0)
    * settings.global["flo-pollution-mult"].value
  if pollution > 0 then
    surface.pollute(candidate.position, pollution)
  end

  if candidate.profile.explosive then
    queue_solid_item_explosion(
      surface,
      candidate.position,
      candidate.item_name,
      candidate.profile
    )
  end
end

local function process_solid_cell(cell, tick)
  cell.due_tick = nil

  if not settings.global["flo-enable-solid-items"].value or tick > cell.expires_tick then
    storage.active_solid_cells[cell.key] = nil
    return
  end

  local surface = game.get_surface(cell.surface_index)
  if not surface then
    storage.active_solid_cells[cell.key] = nil
    return
  end

  local ground_candidate = find_ground_item_candidate(surface, cell.position)
  local belt_candidate = find_belt_item_candidate(surface, cell.position)
  local candidate = ground_candidate
  if belt_candidate and candidate_is_better(belt_candidate, candidate) then
    candidate = belt_candidate
  end

  local delay = SOLID_EMPTY_RECHECK_TICKS
  if candidate and consume_candidate(candidate) then
    ignite_solid_candidate(surface, candidate)
    delay = candidate.profile.delay
    cell.expires_tick = math.max(cell.expires_tick, tick + 300)
  end

  if tick + delay <= cell.expires_tick then
    schedule_solid_scan(cell, tick + delay)
  else
    storage.active_solid_cells[cell.key] = nil
  end
end

local function scaled_count(base_count, multiplier, maximum)
  return math.min(maximum, math.max(0, math.floor(base_count * multiplier + 0.5)))
end

local function process_flammable_explosion(explosion)
  local surface = game.get_surface(explosion.surface_index)
  if not surface then
    return
  end

  local force = game.forces[explosion.force_index] or game.forces.neutral
  local radius_multiplier = settings.global["flo-radius-mult"].value
  local radius_power = 1 / settings.global["flo-radius-power"].value
  local damage_multiplier = settings.global["flo-damage-mult"].value
  local damage_power = 1 / settings.global["flo-damage-power"].value
  local fire_multiplier = settings.global["flo-fire-spread-mult"].value
  local pollution_multiplier = settings.global["flo-pollution-mult"].value

  local explosion_radius = radius_multiplier * math.pow(explosion.energy * 10, radius_power)
  local explosion_damage = damage_multiplier * math.pow(explosion.energy * 10, damage_power)
  local position = explosion.position
  local half_width = explosion.half_width or explosion.entity_radius or 0.5
  local half_height = explosion.half_height or explosion.entity_radius or 0.5
  local width = math.max(half_width, half_height) * 2

  local pollution = explosion.pollution * pollution_multiplier / 10
  if pollution > 0 then
    surface.pollute(position, pollution)
  end

  if width <= 1 then
    surface.create_entity({ name = "explosion", position = position })
    if fire_multiplier > 0 then
      create_oil_fire(surface, position)
    end
  else
    surface.create_entity({
      name = "medium-explosion",
      position = {
        position.x + random_offset(half_width),
        position.y + random_offset(half_height),
      },
    })

    if explosion.energy > 10000 then
      surface.create_entity({
        name = "big-explosion",
        position = {
          position.x + random_offset(half_width),
          position.y + random_offset(half_height),
        },
      })
    end

    if explosion.energy > 100000 then
      surface.create_entity({
        name = "massive-explosion",
        position = {
          position.x + random_offset(half_width),
          position.y + random_offset(half_height),
        },
      })
    end

    local inner_fires = scaled_count(math.ceil(width), fire_multiplier, 200)
    for _ = 1, inner_fires do
      create_oil_fire(surface, {
        position.x + random_offset(half_width),
        position.y + random_offset(half_height),
      })
    end

    local burst_radius = width + 2 * explosion.fraction
    local burst_fires = scaled_count(
      math.ceil(width) * math.ceil(4 * explosion.fraction),
      fire_multiplier,
      800
    )
    for _ = 1, burst_fires do
      create_oil_fire(surface, {
        position.x + random_offset(burst_radius),
        position.y + random_offset(burst_radius),
      })
    end
  end

  if explosion.entity_type == "pipe-to-ground"
    and explosion.underground_neighbour_position
    and explosion_damage > 0
  then
    local neighbours = surface.find_entities_filtered({
      position = explosion.underground_neighbour_position,
      type = "pipe-to-ground",
    })

    local neighbour = neighbours[1]
    if neighbour and neighbour.valid then
      if fire_multiplier > 0 then
        create_oil_fire(surface, neighbour.position)
      end
      neighbour.damage(explosion_damage, force, explosion.damage_type)
    end
  end

  if explosion_radius > 0 and explosion_damage > 0 then
    local horizontal_radius = half_width + 0.5 + explosion_radius
    local vertical_radius = half_height + 0.5 + explosion_radius
    local area = {
      { position.x - horizontal_radius, position.y - vertical_radius },
      { position.x + horizontal_radius, position.y + vertical_radius },
    }

    for _, nearby in pairs(surface.find_entities(area)) do
      if nearby.valid and nearby.health then
        local horizontal_gap = math.max(math.abs(nearby.position.x - position.x) - half_width, 0)
        local vertical_gap = math.max(math.abs(nearby.position.y - position.y) - half_height, 0)
        local distance = math.sqrt(horizontal_gap * horizontal_gap + vertical_gap * vertical_gap)
        local damage = explosion_damage * (1 - distance / explosion_radius)

        if damage > 0 then
          nearby.damage(damage, force, explosion.damage_type)
        end
      end
    end
  end

  if explosion_radius > 2 and explosion.damage_type == "fire" and fire_multiplier > 0 then
    local danger = math.min(explosion_radius * math.sqrt(explosion_radius), 400)
    local danger_fires = scaled_count(danger, fire_multiplier, 2000)
    for _ = 1, danger_fires do
      local angle = math.pi * 2 * math.random()
      local range = math.random() * math.random() * explosion_radius

      surface.create_entity({
        name = "oil-fire-flame",
        position = {
          position.x + math.cos(angle) * range,
          position.y + math.sin(angle) * range,
        },
        force = "neutral",
      })
    end
  end
end

local function process_solid_cargo_reaction(reaction)
  local surface = game.get_surface(reaction.surface_index)
  if not surface then
    return
  end

  local fire_multiplier = settings.global["flo-fire-spread-mult"].value
  local fire_count = scaled_count(
    math.max(1, math.ceil(math.sqrt(reaction.total_items or 1))),
    fire_multiplier,
    80
  )
  local spread_x = math.max(reaction.half_width or 0.5, 0.5) + 0.5
  local spread_y = math.max(reaction.half_height or 0.5, 0.5) + 0.5

  for _ = 1, fire_count do
    local fire_position = {
      x = reaction.position.x + random_offset(spread_x),
      y = reaction.position.y + random_offset(spread_y),
    }
    surface.create_entity({
      name = "flammable-item-fire-flame",
      position = fire_position,
      force = "neutral",
    })
    activate_solid_cell(surface.index, fire_position, game.tick)
  end

  if reaction.energy > settings.global["flo-min-energy-mj"].value then
    process_flammable_explosion(reaction)
  else
    local pollution = reaction.pollution * settings.global["flo-pollution-mult"].value / 10
    if pollution > 0 then
      surface.pollute(reaction.position, pollution)
    end
  end
end

local function release_scheduled_explosions(tick)
  local scheduled = storage.scheduled_explosions[tick]
  if not scheduled then
    return
  end

  for _, explosion in ipairs(scheduled) do
    push_queue(storage.ready_explosions, explosion)
  end
  storage.scheduled_explosions[tick] = nil
end

local function release_scheduled_solid_scans(tick)
  local scheduled = storage.scheduled_solid_scans[tick]
  if not scheduled then
    return
  end

  for _, key in pairs(scheduled) do
    local cell = storage.active_solid_cells[key]
    if cell and cell.due_tick == tick then
      push_queue(storage.ready_solid_scans, key)
    end
  end
  storage.scheduled_solid_scans[tick] = nil
end

local function process_ready_explosions()
  local queue = storage.ready_explosions
  local available = queue.tail - queue.head + 1
  if available <= 0 then
    compact_queue(queue)
    return
  end

  local maximum = settings.global["flo-max-explosions-per-tick"].value
  local to_process = math.min(available, maximum)
  local last_index = queue.head + to_process - 1

  for index = queue.head, last_index do
    local explosion = queue.items[index]
    queue.items[index] = nil
    local solid_reaction = explosion.kind == "solid-cargo"
      or explosion.kind == "solid-item"
    if solid_reaction and not settings.global["flo-enable-solid-items"].value then
      -- The master switch can be changed while a delayed reaction is queued.
    elseif explosion.kind == "solid-cargo" then
      process_solid_cargo_reaction(explosion)
    else
      process_flammable_explosion(explosion)
    end
  end

  queue.head = last_index + 1
  compact_queue(queue)
end

local function process_ready_solid_scans(tick)
  local queue = storage.ready_solid_scans
  local available = queue.tail - queue.head + 1
  if available <= 0 then
    compact_queue(queue)
    return
  end

  local maximum = settings.global["flo-max-solid-updates-per-tick"].value
  local to_process = math.min(available, maximum)
  local last_index = queue.head + to_process - 1

  for index = queue.head, last_index do
    local key = queue.items[index]
    queue.items[index] = nil
    local cell = storage.active_solid_cells[key]
    if cell then
      process_solid_cell(cell, tick)
    end
  end

  queue.head = last_index + 1
  compact_queue(queue)
end

-- A bounded queue prevents recursive C stack overflows and limits the amount
-- of chain-reaction work performed in any one tick.
script.on_event(defines.events.on_tick, function(event)
  if not storage.ready_explosions
    or not storage.scheduled_explosions
    or not storage.ready_solid_scans
    or not storage.scheduled_solid_scans
  then
    return
  end

  release_scheduled_explosions(event.tick)
  release_scheduled_solid_scans(event.tick)
  process_ready_explosions()
  process_ready_solid_scans(event.tick)
end)
