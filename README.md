# mqcollect

A Lua script for MQ + E3 that allows individual characters to store a list of items they want to collect from the other characers in their group.

# Installing
```
cd C:\YourE3MQ2\lua
git clone https://github.com/ZehenForever/mqcollect.git collect
```
Or [download the zip file](https://github.com/ZehenForever/mqcollect/archive/refs/heads/main.zip).

# Usage

Run the Lua script in game for each relevant character:
```
/lua run collect
```
Or for the whole group at once:
```
/e3bcga /lua run collect
```

The first time it runs, it will create an example `collect.ini` file at `C:\PathToE3MQ\config\collect.ini`.  It will look like so:
```
[CharacterOne]
Bone Chips=true
Rubicite Ore=true
Rhenium Ore=true

[CharacterTwo]
Air Mephit Blood=true
Fire Mephit Blood=true
```

# Customizing
Freely edit the ini file at `C:\PathToE3MQ\config\collect.ini` to set up your characters.  This file will be re-loaded every time you run relevant script commmands, so feel free to change the file without needing to restart the script.

# Available commands

`/give <character>`
        
From any character, loads the target &lt;character&gt;'s configured items, and if the current character has any of those, they are given to &lt;character&gt;.
 
`/collect`

Alias for "/collect group"

`/collect group`

Iterates through group members and instructs them one at a time
to use the `/give <character>` command to give the current character 
any items that the current character has configured.

`collect e3bots`

Iterates through all connected E3 bots and instructs them one at a time
to use the `/give <character>` command to give the current character 
any items that the current character has configured.

`/collect add`

Adds the item on the current character's cursor to their section in the ini file. Useful for creating a button that can be clicked on with an item on the cursor to update the ini file accordingly.

`/collect add target`

Adds the item on the current character's cursor to their current target's section in the ini file. Useful for creating a button that can be clicked on with an item on the cursor to update the ini file accordingly.

`/collect add <character>`

Adds the item on the current character's cursor to the &lt;character&gt;'s section in the ini file. Useful for creating a button that can be clicked on with an item on the cursor to update the ini file accordingly.

`/collect debug`

Enables debug mode for more verbose output.
    
`/collect sort (not implemented yet)`

Sorts the settings in the `collect.ini` file and saves them.

# Example scenario:

One character, **CharOne** has just finished adventuring with their group, and would like to gather up items for their Bazaar vendor, **CharVendor**.

- **CharOne** wants Diamond Coin, Blue Diamond, and Raw Diamond so that they can put these on their vendor, **CharVendor**, in the Bazaar.

- **CharOne** has a section in the `collect.ini` that looks like:

        [CharOne]
        Diamond Coin=true
        Blue Diamond=true
        Raw Diamond=true
    
- **CharOne** runs the command `/collect` while still grouped.

    This will ask each group member to give **CharOne** any Diamond Coin, Blue Diamond, and Raw Diamond that they have in their inventory.

- **CharOne** now has every Diamond Coin, Blue Diamond, and Raw Diamond that have been looted by any character in the group.
    
- **CharOne** goes to the Bazaar to find their vendor, **CharVendor**
    
- **CharVendor** has a section in the `collect.ini` that looks like:

        [CharVendor]
        Diamond Coin=true
        Blue Diamond=true
        Raw Diamond=true

- **CharOne** runs the command `/give CharVendor`

    This will give all of the Diamond Coin, Blue Diamond, and Raw Diamond that **CharOne** has in their inventory to **CharVendor**.

- **CharVendor** can now flood the market with their low, low prices.
