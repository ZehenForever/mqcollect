--[[
    -----------------------------------------------------------------------------------------------

    Collect - A simple item collector for an MQ2 box group that collects all configured items from
    the members in group and gives them to the desired character.

    -----------------------------------------------------------------------------------------------
    AVAILABLE COMMANDS:

    /give <character>
        Loads the target <character>'s configured items, and if the 
        current character has any, they are given to the target <character>.
 
    /collect
        Iterates through group members and instructs them one at a time
        to use the /give <character> command to give the current character 
        any items that the current character has configured.

    /collect add
        Adds the item on the current character's cursor to their ini section

    /collect add target
        Adds the item on the current character's cursor to their current target's ini section
   
    /collect add <character>
        Adds the item on the current character's cursor to the <character>'s ini section
   
    /collect debug
        Enables debug mode for more verbose output.
    
    /collect sort (not implemented yet)
        Sorts the settings in the config file and saves them.
    
    -----------------------------------------------------------------------------------------------
    EXAMPLE SCENARIO: One character likes to gather up items for their Bazaar vendor

        - CharOne wants Diamond Coin, Blue Diamond, and Raw Diamond

        - CharOne has a section in the collect.ini that looks like:

            [CharOne]
            Diamond Coin=true
            Blue Diamond=true
            Raw Diamond=true
        
        - CharOne runs the command '/collect'

            This will ask each group member to give CharOne any Diamond Coin, Blue Diamond, 
            and Raw Diamond that they have in their inventory.

        - CharOne now has every Diamond Coin, Blue Diamond, and Raw Diamond that the other 
          group members had in their inventory.
        
        - CharOne goes to the Bazaar to find their vendor, CharVendor
        
        - CharVendor has a section in the collect.ini that looks like:

            [CharVendor]
            Diamond Coin=true
            Blue Diamond=true
            Raw Diamond=true

        - CharOne and runs the command '/give CharVendor'

            This will give all of the Diamond Coin, Blue Diamond, and Raw Diamond that CharOne 
            has in their inventory to CharVendor.
]]

local mq = require('mq')
local Write = require('lib/Write')
local ini = require('lib/inifile')

local config_file = mq.TLO.MacroQuest.Path() .. '\\config\\collect.ini'

-- Time in ms to wait for things like windows opening
local WaitTime = 750

-- Default Write output to 'info' messages
-- Override via /collect debug
Write.loglevel = 'info'

-- A flag to indicate when a character is done sending items from their inventory.
-- Used during the /collect command to wait before moving on to the next characater.
-- An event handler will set this to true when a character tells us they are done.
local char_done = true

-- An example config for items that each character wants
-- We'll use this to write out an example config file if one does not exist
local example_config = {
    ['CharacterOne'] = {
        ['Bone Chips'] = true,
        ['Rubicite Ore'] = true,
        ['Rhenium Ore'] = true,
    },
    ['CharacterTwo'] = {
        ['Fire Mephit Blood'] = true,
        ['Air Mephit Blood'] = true
    },
}

-- Settings originally set to the example
local settings = example_config

-- test to see if a file exists and is at least readable
local file_exists = function (path)
    local file = io.open(path, "r")
    if file ~= nil then
        io.close(file)
        return true
    else
        return false
    end
end

-- saves our settings to the config file
local save_settings = function (table)
    ini.save(config_file, table)
end

local table_sort = function (tbl)
    local t = {}
    local keys = {}

    -- get and sort table keys
    for k in pairs(tbl) do 
        table.insert(keys, k)
    end
    table.sort(keys)

    -- rebuild tbl by key order and return it
    for _, k in ipairs(keys) do 
        local temp = tbl[k]
        table.sort(temp)
        t[k] = temp
    end
    return t
end

-- convenience function to check if we are in game
local in_game = function ()
    return mq.TLO.MacroQuest.GameState() == 'INGAME'
end

-- convenience function to check if we have a target
local have_target = function ()
    if mq.TLO.Target.ID() ~= nil then return true else return false end
end

-- convenience function to get the distance to a target
local target_distance = function (target)
    return mq.TLO.Spawn(target).Distance3D()
end

-- convenience function to check if the cursor has an item on it
local cursor_has_item = function ()
    if mq.TLO.Cursor.ID() == 0 then return false else return true end
end

-- convenience function to check if the cursor is empty
local cursor_is_empty = function ()
    if mq.TLO.Cursor.ID() == 0 then return true else return false end
end

-- convenience function to check if the trade window is open
local trade_window_open = function ()
    return mq.TLO.Window('TradeWnd').Open()
end

-- convenience function to check if the trade window is closed
local trade_window_closed = function ()
    return mq.TLO.Window('TradeWnd').Open() == false
end

-- Navigate to a target and wait for arrival
local nav_target = function (target)
    mq.cmdf('/target "%s"', target)
    mq.delay(WaitTime, have_target)
    mq.cmd('/nav target distance=10')

    -- Wait while we travel
    while mq.TLO.Navigation.Active() do
        mq.delay(100)
    end
    Write.Debug('Arrived at %s', target)
end

-- Check if the current target is the same as the one we want
local check_target = function (target)
    if mq.TLO.Target.Name() == target then
        return true
    else
        return false
    end
end

-- Gives an item to the target
local give_item = function (name, target)

    -- Find the item in the inventory
    local item_id = mq.TLO.FindItem('='..name).ID()

    -- If we don't find it, exit here
    if item_id == nil then
        Write.Debug('No "%s" in inventory', name)
        return
    end

    -- Always make sure we have the right target before attempting a trade
    mq.cmdf('/target "%s"', target)
    if not check_target(target) then
        Write.Info('Target "%s" not found', target)
        return
    end

    -- Move to our target if we are not already close
    if target_distance(target) > 15 then
        Write.Debug('Moving to %s', target)
        nav_target(target)
    end

    -- Locate the item in the inventory
    local item_slot = mq.TLO.FindItem('='..name).ItemSlot()
    local item_slot2 = mq.TLO.FindItem('='..name).ItemSlot2()
    Write.Debug('Item "%s" (%d) is in slot %d.%d', name, item_id, item_slot, item_slot2)

    -- Pick up the item
    local pickup1 = item_slot - 22
    local pickup2 = item_slot2 + 1
    mq.cmd('/shift /itemnotify in pack' .. pickup1 .. ' ' .. pickup2 .. ' leftmouseup')
    mq.delay(WaitTime, cursor_has_item)

    -- Click theitem on to the target to begin the trade
    mq.cmd('/click left target')
    mq.delay(WaitTime, cursor_is_empty)

    -- Click the Trade button to complete the trade
    mq.cmd('/notify TradeWnd TRDW_Trade_Button leftmouseup')
    mq.delay(WaitTime, trade_window_closed)

    -- If the trade window is still open, wait for it to close
    -- The target character may not have clicked the trade button yet
    while trade_window_open() do
        mq.delay(100)
    end

end

-- Instructs the target character to give us items
local function ask_for_items(target)

    -- We'll wait until this is true
    -- Our event handler will set this to true when the target tells us they are done
    char_done = false

    -- Sends the '/give <character>' command to the target
    mq.cmdf('/e3bct %s /give %s', target, mq.TLO.Me.Name())

    -- Wait until our event handler tells us that the target is done
    while not char_done do
        mq.delay(100)

        -- If the trade window is open, click the trade button
        if trade_window_open() then
            mq.cmd('/notify TradeWnd TRDW_Trade_Button leftmouseup')
            mq.delay(WaitTime, trade_window_closed)
        end
    end

end

-- Adds an item from the cursor to the current character's settings
local add_item_on_cursor = function (target)

    -- If the target is not specified, default to the current character
    if target == nil then 
        target = mq.TLO.Me.Name()
    end

    -- Check to make sure we have an item on the cursor
    local item = mq.TLO.Cursor.Name()
    if item == nil then
        Write.Info('No item on cursor')
        return
    end

     -- Check to make sure we have a valid target
    if mq.TLO.Spawn(target) == nil then
        Write.Info('Target "%s" not found', target)
        return
    end

    -- Add it to the settings file and save that file
    settings[target][item] = true
    save_settings(settings)
    Write.Info('Added "%s" to %s settings', item, target)

    -- Drop the item from the cursor into our inventory
    mq.cmd('/autoinventory')
end

-- Collects all configured items from the rest of the group
-- Receives bind callback from /collect
local collect = function (...)
    local args = {...}

    -- Debug args
    for i,arg in ipairs(args) do
        Write.Debug('/collect arg[%d]: %s', i, arg)
    end

    -- Command: /collect
    -- Loop through the group, and ask each group member for items
    -- that this character wants
    if args[1] == nil then
        for i = 1, mq.TLO.Group.Members() do
            local member = mq.TLO.Group.Member(i)
            if member then
                Write.Debug('Asking %s for items I want', member.Name())
                ask_for_items(member.Name())
            end
        end
    end

    -- Command: /collect debug
    -- Allow setting debug mode to get more verbose output
    if args[1] == 'debug' then
        Write.loglevel = 'debug'
        Write.Info('Debug mode enabled')
        return
    end

    -- Command: /collect sort
    -- Allow sorting of the settings
    if args[1] == 'sort' then
        settings = ini.parse(config_file)
        settings = table_sort(settings)
        save_settings(settings)
        Write.Info('Settings sorted and saved')
        return
    end

    -- Command: /collect add target
    -- Add an item from the cursor to our current target's settings
    if args[1] == 'add' and args[2] == 'target' then
        add_item_on_cursor(mq.TLO.Target.Name())
        return
    end

    -- Command: /collect add <target>
    -- Add an item from the cursor to the specified <target>'s settings
    if args[1] == 'add' and args[2] ~= nil then
        add_item_on_cursor(args[2])
        return
    end

    -- Command: /collect add
    -- Add an item from the cursor to the current character's settings
    if args[1] == 'add' and args[2] == nil then
        add_item_on_cursor(mq.TLO.Me.Name())
        return
    end


end

-- Bind callback for /give
-- Command: /give <target>
-- Loads the target's configured items and gives any items
-- from the current character's inventory to the target
local give = function (...)
    local args = {...}

    -- Debug args
    for i,arg in ipairs(args) do
        Write.Debug('/give arg[%d]: %s', i, arg)
    end

    -- Our target is the first argument
    local target = args[1]
    if target == nil then
        Write.Info('No target specified')
        Write.Info('Usage: /give <target>')
        return
    end

    -- Make sure we have the right target
    mq.cmdf('/target "%s"', target)
    if not check_target(target) then
        Write.Info('Target "%s" not found', target)
        return
    end

    -- Load the most recent version of the settings file
    settings = ini.parse(config_file)

    -- Check if we have settings for the target
    if settings[target] == nil then
        Write.Info('%s does not have any configured items to collect', target)
        return
    end

    -- Navigate to the target
    nav_target(target)

    -- Iterate through all configured items 
    -- and attempt to give them to the target
    for k,v in pairs(settings[target]) do
        Write.Debug('Attempting to give %s to %s', k, target)
        give_item(k, target)
    end

    -- Let the target know we are done
    mq.cmdf('/tell %s Done sending you items', target)
end

-- Handles the event when a character tells us they are done
local handle_char_done = function (line, char)
    Write.Debug('%s has finished sending items', char)
    char_done = true
end

--[[ 
    Register event handlers and command binds
    Loop our process and yield on every frame
]]

-- Register an event handler for when a character tells us they are done
mq.event('char_done', '#1# tells you, \'Done sending you items\'', handle_char_done)

-- Register our command binds
mq.bind('/collect', collect)
mq.bind('/give', give)

-- Load the settings from the config file
-- If the file does not exist, write out an example config file that the user can edit
if file_exists(config_file) then
    Write.Info('Config file exists: %s', config_file)
    settings = ini.parse(config_file)
else
    Write.Info('Config file does NOT exist: %s', config_file)
    Write.Info('Writing example config to %s', config_file)
    save_settings(example_config)
    settings = example_config
end

-- Loop and yield on every frame
while true do
    mq.doevents()
    mq.delay(1)
end
