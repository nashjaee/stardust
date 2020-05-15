--- Represnts a miniature of a unit.
--
-- Expects the table "spawnSetup" to be set to initialize the miniature.
--
-- @usage
-- someMini.setTable('spawnSetup', {
--   -- Data table.
--   name = '...',
--
--   -- Whether to be considered a unit leader. Omit if not a leader.
--   leader: {
--     color = 'Red',
--     rank  = 'Corps',
--   },
-- })
--
-- @module Miniature
--
-- @see Data_Controller

_GUIDS = {
  SPAWN_CONTROLLER = '525d68',
  TARGET_CONTROLLER = '4205cc',
}

_PERSIST = {
  CONNECTED_MINIS = {},
  ACTIVE_SILOUHETTE = false,
  ACTIVE_RANGE_FINDER = false,
  SETUP = nil,
}

--- Used by the targeting sub-system to determine what models are targetable.
--
-- Defaults to true.
IS_TARGETABLE = true

--- Used by various sub-systems to determine what models represent unit leaders.
--
-- Defaults to false.
IS_UNIT_LEADER = false

--- Whether this unit is currently selected by a player (color).
--
-- This value should always be `nil` for a non-leader miniature.
--
-- @local
_SELECTED_BY_COLOR = nil

function onLoad(state)
  -- Keep the previously configured state.
  if state != '' then
    _PERSIST = JSON.decode(state)
    if _PERSIST.SETUP.leader then
      initializeAsLeader()
    end
    return
  end

  -- Load the data provided to the model, if any. Otherwise bail out.
  local spawnSetup = self.getTable('spawnSetup')
  if spawnSetup == nil then
    _disableSelectable()
    return
  end

  _PERSIST = {
    CONNECTED_MINIS = {},
    ACTIVE_SILOUHETTE = false,
    ACTIVE_RANGE_FINDER = false,
    SETUP = {
      name = spawnSetup.name,
    }
  }

  -- Are we a unit leader?
  if spawnSetup.leader then
    _PERSIST.SETUP.leader = spawnSetup.leader
    initializeAsLeader()
    self.setName(_PERSIST.SETUP.name .. ' (Unit Leader)')
  else
    initializeAsFollower()
    self.setName(_PERSIST.SETUP.name)
  end

  -- Override defaults.
  self.setLock(false)
  self.setScale({1, 1, 1})
end

function onSave()
  if _PERSIST.SETUP != nil then
    return JSON.encode(_PERSIST)
  end
end

--- Initialize as a Unit Leader.
--
-- Assigns @see Miniature:IS_UNIT_LEADER and sets up UI.
--
-- @local
function initializeAsLeader()
  -- Expose to other objects we are a unit leader.
  IS_UNIT_LEADER = true
end

--- Select button (i.e. the base) is clicked.
--
-- @param player Player that selected the miniature.
--
-- @see Miniature:_selectUnit
-- @local
function _onSelect(player)
  assert(IS_UNIT_LEADER == true)
  local color = player.color
  if color != 'Red' and color != 'Blue' then
    color = _PERSIST.SETUP.leader.color
  end
  _selectUnit(color)
end

-- Initialize as a "Follower" (not a Unit Leader).
function initializeAsFollower()
  _disableSelectable()
end

--- Disables the ability to select this model.
--
-- @local
function _disableSelectable()
  Wait.frames(function()
    self.UI.hide('baseButton')
  end, 1)
end

--- Toggles selection of the unit.
--
-- @param color Player color.
--
-- @local
function _selectUnit(color)
  assert(color != nil)

  -- Toggle on.
  if _SELECTED_BY_COLOR == nil then
    _SELECTED_BY_COLOR = color
    self.highlightOn(color)
    self.UI.show('unitActions')
    return;
  end

  -- Toggle off.
  if _SELECTED_BY_COLOR == color then
    _SELECTED_BY_COLOR = nil
    self.highlightOff()
    self.UI.hide('unitActions')
    return
  end
end

--- Destroys any attachments that pass `.getVar(checkVar)`.
--
-- @local
-- @usage
-- _destroyAttachment('IS_RANGE_FINDER')
function _destroyAttachment(checkVar)
  -- TODO: Implement. Right now it destroys _all_ attachments.
  -- Probably we need to clone another asset bundle for range finders?
  self.destroyAttachments()
end

--- Toggle range finder for the unit leader.
--
-- @usage
-- unitLeaderMini.call('toggleRange')
function toggleRange()
  assert(IS_UNIT_LEADER)
  if _PERSIST.ACTIVE_RANGE_FINDER then
    _hideRange()
  else
    _showRange()
  end
  _PERSIST.ACTIVE_RANGE_FINDER = not _PERSIST.ACTIVE_RANGE_FINDER
end

function _hideRange()
  _destroyAttachment('IS_RANGE_FINDER')
end

function _showRange()
  local controller = getObjectFromGUID(_GUIDS.TARGET_CONTROLLER)
  local object = controller.call('spawnRangeFinder', {
    position = self.getPosition(),
    rotation = self.getRotation(),
  })
  self.addAttachment(object)
end

--- Returns whether the `guid` of the provided table is part of the unit.
--
-- @param args A table with a 'guid' property.
--
-- @usage
-- unitLeaderMini.call('isPartOfUnit', {
--   guid: 'abc123',
-- })
--
-- @return True if the mini is part of the unit.
function isPartOfUnit(args)
  return _isPartOfUnit(args.guid)
end

function _isPartOfUnit(guid)
  if self.guid == guid then
    return true
  end
  for _, miniGuid in ipairs(_PERSIST.CONNECTED_MINIS) do
    if miniGuid == guid then
      return true
    end
  end
  return false
end

--- Toggle silouhettes showing up for the miniature.
--
-- If this unit is a unit leader, then this automatically calls the
-- `toggleSilouhettes` method for all miniatures attached to the unit.
--
-- @usage
-- unitLeaderMini.call('toggleSilouhettes')
function toggleSilouhettes()
  if _PERSIST.ACTIVE_SILOUHETTE then
    _hideSilouhette()
  else
    _showSilouhette()
  end
  if _IS_UNIT_LEADER and #_PERSIST.CONNECTED_MINIS then
    for _, mini in ipairs(_PERSIST.CONNECTED_MINIS) do
      mini.call('toggleSilouhettes')
    end
  end
end

function _hideSilouhette()
  _destroyAttachment('IS_SILOUHETTE')
  _PERSIST.ACTIVE_SILOUHETTE = false
end

function _showSilouhette()
  local controller = getObjectFromGUID(_GUIDS.SPAWN_CONTROLLER)
  local silouhette = controller.call('spawnSilouhette', {
    position = self.getPosition(),
    rotation = self.getRotation(),
  })
  self.addAttachment(silouhette)
  _PERSIST.ACTIVE_SILOUHETTE = true
end

--- Associate this model with another minis.
--
-- @param minis A list of other model objects.
--
-- If you are a unit leader, this method associates itself with miniatures
-- that are considered "part" of your unit (including things like counterparts).
--
-- If you are a non-leader, this method links to your unit leader.
--
-- @usage
-- unitLeaderMini.call('connectTo', {mini1, mini2, mini3})
function connectTo(minis)
  for _, mini in ipairs(minis) do
    _connectTo(mini)
  end
end

function _connectTo(otherMini)
  if otherMini.guid == self.guid then
    return
  end
  table.insert(_PERSIST.CONNECTED_MINIS, otherMini.guid)
end