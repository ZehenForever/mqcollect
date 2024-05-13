--[[
    -----------------------------------------------------------------------------------------------

    Collect - A simple item collector for an MQ2 box group that collects all configured items from
    the members in group and gives them to the desired character.

    -----------------------------------------------------------------------------------------------
    AVAILABLE COMMANDS:

    /give
        Loads the current target's configured items, and if the 
        current character has any, they are given to the target

    /give <character>
        Loads the <character>'s configured items, and if the 
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
    ['General'] = {
        ['FastMode'] = true,
    },
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

-- Returns the length of a table
local table_length = function(T)
  local count = 0
  for _ in pairs(T) do count = count + 1 end
  return count
end

-- Sorts a table by key and then by value
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

-- Split a string by a delimiter
local split = function (str, delimiter)
    local result = {}
    local from = 1
    local delim_from, delim_to = string.find(str, delimiter, from)    
    while delim_from do
        table.insert(result, string.sub(str, from, delim_from - 1))
        from = delim_to + 1
        delim_from, delim_to = string.find(str, delimiter, from)
    end
    table.insert(result, string.sub(str, from))
    return result
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

-- Set the target if it is not already set
local set_target = function (target)
    if mq.TLO.Target.Name() ~= target then
        mq.cmdf('/target "%s"', target)
    end
end

-- Check if the current target is the same as the one we want
local check_target = function (target)
    if mq.TLO.Target.Name() == target then
        return true
    else
        return false
    end
end

-- Navigate to a target and wait for arrival
local nav_target = function (target)

    -- If our specified target and our current target are not the same
    -- then target the new target before navigating
    set_target(target)
    mq.delay(WaitTime, have_target)
    mq.cmd('/nav target distance=20')

    -- Wait while we travel
    while mq.TLO.Navigation.Active() do
        mq.delay(100)
    end
    Write.Debug('Arrived at %s', target)
end

-- Quickly finds an item in the pack or bank
local find_item = function (location, name, match_type)
    -- { ['name'] = 'Item Name', ['slot'] = 'pack3 2' }
    local item = {}
    if location ~= 'pack' and location ~= 'bank' then
        Write.Error('Invalid search location: %s', location)
        return item
    end

    if match_type == nil then match_type = 'exact' end
    Write.Debug('Searching %s for "%s"', location, name)

    -- Subtract from the ItemSlot() number
    local subtract = 0

    local search = function ()
        if location == 'pack' then
            subtract = 22
            if match_type == 'exact' then
                return mq.TLO.FindItem('='..name)
            elseif match_type == 'partial' then
                return mq.TLO.FindItem(name)
            end
        elseif location == 'bank' then
            subtract = -1
            if match_type == 'exact' then
                return mq.TLO.FindItemBank('='..name)
            elseif match_type == 'partial' then
                return mq.TLO.FindItemBank(name)
            end
        else
            Write.Error('Invalid search location: %s', location)
            return nil
        end
    end
    local search_result = search()

    if search_result.ID() == nil then
        Write.Debug('No items found matching "%s"', name)
        return item
    end
    Write.Debug("Found item: %s %s", search_result.Name(), search_result.ItemSlot() .. ' ' .. search_result.ItemSlot2())

    item = {
        ['name'] = search_result.Name(),
        ['slot'] = location .. (search_result.ItemSlot()-subtract) .. ' ' .. (search_result.ItemSlot2()+1)
    }
    return item
end

-- Go through each bag and slot to find all items
-- that match the name
local find_all_items = function (location, name, match_type)
    local items = {}
    local count = 1

    if location ~= 'pack' and location ~= 'bank' then
        Write.Error('Invalid search location: %s', location)
        return items
    end

    -- Perform a fast search to see if any items match the name
    local fast_search = find_item(location, name, match_type)
    if fast_search['name'] == nil then
        Write.Debug('No items found matching "%s"', name)
        return items
    end

    -- Set the total slots based on the location
    local total_slots = 0
    if location == 'pack' then
        total_slots = 10
    elseif location == 'bank' then
        total_slots = 24
    end

    --Write.Debug('Quick find: %s %s', mq.TLO.FindItem('='..name).ItemSlot(), mq.TLO.FindItem('='..name).ItemSlot2())

    -- Iterate through each slot in the location (pack or bank)
    for i = 1, total_slots do
        local inv_slot = location..tostring(i)

        -- Only process bags with slots ; nil can mean no bag ; does 0 mean no bag or a bag with zero slots?
        Write.Debug('Checking %s: %s', inv_slot, mq.TLO.InvSlot(inv_slot).ID())
        if mq.TLO.InvSlot(inv_slot).ID()
            and mq.TLO.InvSlot(inv_slot).Item.Container() ~= nil
            and mq.TLO.InvSlot(inv_slot).Item.Container() > 0
        then
            local slot_count = mq.TLO.InvSlot(inv_slot).Item.Container()

            -- Process each slot in this bag
            for j = 1, slot_count do

                -- If we find an item in this slot
                if mq.TLO.InvSlot(inv_slot).Item.Item(j)() ~= nil then
                    local item = mq.TLO.InvSlot(inv_slot).Item.Item(j)
                    local pack_slot = inv_slot .. ' ' .. j
                    local found = false

                    -- If we need an exact match
                    if match_type == 'exact' then
                        if item.Name() == name then
                            Write.Debug('Found item: %s in "%s"', item.Name(), pack_slot)
                            found = true
                        end
                    end

                    -- If we need a partial match
                    if match_type == 'partial' then
                        local ok = string.find(string.lower(item.Name()),string.lower(name),nil,true) ~= nil
                        if ok then
                            Write.Debug('Found matching item: %s in %s', item.Name(), pack_slot)
                            found = true
                        end
                    end

                    -- If we found the item, add it to our list
                    if found then
                        items[count] = {
                            ['name'] = item.Name(),
                            ['slot'] = pack_slot
                        }
                        count = count + 1
                    end

                end
            end
        end
    end

    return items
end

-- Click the trade window Trade button
local click_trade = function()
    mq.cmd('/notify TradeWnd TRDW_Trade_Button leftmouseup')

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

    -- If the settings for the target do not exist, create them
    if settings[target] == nil then
        settings[target] = {}
    end

    -- Add it to the settings file and save that file
    settings[target][item] = true
    save_settings(settings)
    Write.Info('Added "%s" to %s settings', item, target)

    -- Drop the item from the cursor into our inventory
    mq.cmd('/autoinventory')
end

local move_to_bank = function (slot)
    mq.cmd('/shift /itemnotify in ' .. slot .. ' leftmouseup')
    mq.delay(WaitTime, cursor_has_item)
    mq.cmd('/nomodkey /notify BigBankWnd BIGB_AutoButton leftmouseup')
    mq.delay(WaitTime, cursor_is_empty)
end

local scan_items = function (location)
    --[[
        { 
          ['pack'] = {
            ['Item One'] = { 'pack3 2, pack3 3' },
            ['Item Two'] = { 'pack4 1, pack4 2' },
            ...
          },
          ['bank'] = {
            ['Item Four'] = { 'bank3 2, bank3 3' },
            ['Item Five'] = { 'bank4 1, bank4 2' },
            ...
          }
        }
    ]]
    local items = {}

    if location ~= 'pack' and location ~= 'bank' then
        Write.Error('Invalid search location: %s', location)
        return items
    end

    -- Set the total slots based on the location
    local total_slots = 0
    if location == 'pack' then
        total_slots = 10
    elseif location == 'bank' then
        total_slots = 24
    end

    if items[location] == nil then
        items[location] = {}
    end

    --Write.Debug('Quick find: %s %s', mq.TLO.FindItem('='..name).ItemSlot(), mq.TLO.FindItem('='..name).ItemSlot2())

    -- Iterate through each slot in the location (pack or bank)
    for i = 1, total_slots do
        local inv_slot = location..tostring(i)

        -- Only process bags with slots ; nil can mean no bag ; does 0 mean no bag or a bag with zero slots?
        Write.Debug('Scanning %s', inv_slot)
        if mq.TLO.InvSlot(inv_slot).ID()
            and mq.TLO.InvSlot(inv_slot).Item.Container() ~= nil
            and mq.TLO.InvSlot(inv_slot).Item.Container() > 0
        then
            local slot_count = mq.TLO.InvSlot(inv_slot).Item.Container()

            -- Process each slot in this bag
            local count = 1
            for j = 1, slot_count do
                if mq.TLO.InvSlot(inv_slot).Item.Item(j)() ~= nil then
                    local item = mq.TLO.InvSlot(inv_slot).Item.Item(j)
                    local pack_slot = inv_slot .. ' ' .. j

                    -- If we don't have this item in our list yet, add it
                    if items[location][item.Name()] == nil then
                        items[location][item.Name()] = { pack_slot }
                    else
                        table.insert(items[location][item.Name()], pack_slot)
                    end

                end

            end
        end
    end

    return items
end

-- Collects all configured items from the rest of the group
-- Receives bind callback from /collect
local collect = function (...)
    local args = {...}

    -- Debug args
    for i,arg in ipairs(args) do
        Write.Debug('/collect arg[%d]: %s', i, arg)
    end

    -- Command: /collect group
    --      or: /collect
    -- Loop through the group, and ask each group member for items
    -- that this character wants
    if args[1] == 'group' or args[1] == nil then
        for i = 1, mq.TLO.Group.Members() do
            local member = mq.TLO.Group.Member(i)
            if member then
                Write.Debug('Asking %s for items I want', member.Name())
                ask_for_items(member.Name())
            end
        end
    end

    -- Command: /collect e3bots
    if args[1] == 'e3bots' then
        local connectedClients = mq.TLO.MQ2Mono.Query('e3,E3Bots.ConnectedClients')()
        local e3peers = split(connectedClients, ',')
        for i, name in ipairs(e3peers) do
            local member = mq.TLO.Spawn(string.format('pc = %s', name))
            if member() then
                Write.Debug('Asking %s for items I want', member.Name())
                ask_for_items(member.Name())
            end
        end
    end

    -- Command: /collect bank <character>
    -- Collect all configured items from the bank for the specified <character>
    if args[1] == 'bank' then
        if args[2] == nil then
            args[2] = mq.TLO.Me.Name()
        end
        local target = args[2]
        Write.Info('Collecting items from bank for %s', target)

        -- Scan the bank for all items that the current character has
        local bank_items = scan_items('bank')

        -- Iterate through the target character's items and see if we have any
        for k,_ in pairs(settings[target]) do
            Write.Debug('Attempting to collect %s from bank for %s', k, target)

            -- If we have the item, give all of them to the target
            if bank_items['bank'][k] ~= nil then
                for i, slot in ipairs(bank_items['bank'][k]) do
                    Write.Debug('Moving %s from %s to inventory', k, slot)
                    mq.cmd('/shift /itemnotify in ' .. slot .. ' leftmouseup')
                    mq.delay(WaitTime, cursor_has_item)
                    mq.cmd('/autoinventory')
                    mq.delay(WaitTime, cursor_is_empty)
                    --TODO: Figure out why we have to do this twice...
                    mq.cmd('/autoinventory')
                 end
            end
        end
        Write.Info('All items moved to inventory')
        return
    end

    -- Command: /collect list
    -- List all configured items for the current character
    if args[1] == 'list' then
        local char = mq.TLO.Me.Name()
        settings = ini.parse(config_file)
        if settings[char] == nil then
            Write.Info('%s does not have any configured items to collect', char)
            return
        end
        for k,v in pairs(settings[char]) do
            Write.Info('%s', k)
        end
        return
    end

    -- Command /collect scan <pack|bank>
    -- Scan the pack or bank for all items and their slots
    if args[1] == 'scan' and (args[2] == 'pack' or args[2] == 'bank') then
        local location = args[2]
        local items = scan_items(location)
        for k,v in pairs(items[location]) do
            Write.Info('%s', k)
            for i, slot in ipairs(v) do
                Write.Debug('  %s', slot)
            end
        end
        return
    end

    -- Command: /collect debug
    -- Allow setting debug mode to get more verbose output
    if args[1] == 'debug' and (args[2] == nil or string.lower(args[2]) == 'true') then
        Write.loglevel = 'debug'
        Write.Info('Debug mode enabled')
        return
    elseif args[1] == 'debug' and string.lower(args[2]) == 'false' then
        Write.loglevel = 'info'
        Write.Info('Debug mode disabled')
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

    -- Command: /collect add <character>
    -- Add an item from the cursor to the specified <character>'s settings
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
local give = function (...)
    local args = {...}

    -- Debug args
    for i,arg in ipairs(args) do
        Write.Debug('/give arg[%d]: %s', i, arg)
    end

    -- Build a list of all items that the current character has
    local my_items = scan_items('pack')

    -- Command: /give bank
    -- Command: /give bank <character>
    -- Move all defined items from the current character's inventory to the bank
    if args[1] == 'bank' then
        Write.Info('Moving all items to bank')
        local target = mq.TLO.Me.Name()
        if args[2] ~= nil then
            target = args[2]
        end
        for k,v in pairs(settings[target]) do
            Write.Debug('Attempting to move %s to bank', k)
            if my_items['pack'][k] ~= nil then
                for i, slot in ipairs(my_items['pack'][k]) do
                    Write.Debug('Moving %s from %s to bank', k, slot)
                    move_to_bank(slot)
                end
            end
        end
        Write.Info('All items moved to bank')
        return
    end

    --[[
        Some test commands to help with testing certain functions
        /give find <item>
        /give findall <item>
    ]]

    -- Finds the first matching item from the inventory
    -- /give find <item>
    if args[1] == 'find' then
        Write.Debug('Searching for %s', args[2])
        local result = find_item('pack', args[2])
        if result['name'] == nil then
            Write.Debug('No items found matching "%s"', args[2])
            return
        end
        Write.Info('Found item: %s in %s', result['name'], result['slot'])
        return
    end

    -- Finds the first matching item from the bank
    -- /give findbank <item>
    if args[1] == 'findbank' then
        Write.Debug('Searching for %s', args[2])
        local result = find_item('bank', args[2])
        if result['name'] == nil then
            Write.Debug('No items found matching "%s"', args[2])
            return
        end
        Write.Info('Found item: %s in %s', result['name'], result['slot'])
        return
    end

    -- Search for all occurrences of an item that exactly matches the name
    -- /give findall <pack|bank> <item>
    if args[1] == 'findall' and (args[2] ~= 'pack' and args[2] ~= 'bank') then
        Write.Info('Usage: /give findall <pack|bank> <item>')
        return
    end
    if args[1] == 'findall' and (args[2] == 'pack' or args[2] == 'bank') then
        Write.Debug('Searching %s for all %s', args[2], args[3])
        find_all_items(args[2], args[3], 'exact')
        return
    end

    -- Search for all occurrences of an item that partially matches the name
    -- /give findall <item>
    if args[1] == 'findallmatch' and (args[2] ~= 'pack' and args[2] ~= 'bank') then
        Write.Info('Usage: /give findallmatch <pack|bank> <item>')
        return
    end
    if args[1] == 'findallmatch' and (args[2] == 'pack' or args[2] == 'bank') then
        Write.Debug('Searching %s for all matches for %s', args[2], args[3])
        find_all_items(args[2], args[3], 'partial')
        return
    end

    --[[
        The user commands 
        /give target
        /give <character>
    ]]

    -- Our target is the first argument or the current target
    local target = args[1]
    if target == nil and have_target() then
        target = mq.TLO.Target.Name()
    end

    -- If we still don't have a target, then return
    if target == nil then
        Write.Info('No target specified')
        Write.Info('Usage: /give')
        Write.Info('Usage: /give <character name>')
        return
    end

    -- Make sure we have the right target
    set_target(target)
    if not check_target(target) then
        Write.Error('Target "%s" not found', target)
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

    -- Iterte through the target character's items and see if we have any
    local count = 0
    local found = 0
    local total = table_length(settings[target])
    for k,_ in pairs(settings[target]) do
        Write.Debug('Attempting to give %s to %s', k, target)
        count = count + 1

        -- If we have the item, give it to the target
        if my_items['pack'][k] ~= nil then
            for i, slot in ipairs(my_items['pack'][k]) do
                found = found + 1
                Write.Debug('Giving "%s" from "%s"', k, slot)
                mq.cmd('/shift /itemnotify in ' .. slot .. ' leftmouseup')
                mq.delay(WaitTime, cursor_has_item)
                mq.cmd('/click left target')
                mq.delay(WaitTime, cursor_is_empty)

                -- If have filled up our trade window, click the trade button
                Write.Debug('We are on %d of %d items', count, total)
                if found % 8 == 0 then
                    click_trade()
                end
            end
        end

        -- If we gone through all of the target items, click the trade button
        if count == total then
            click_trade()
        end
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
