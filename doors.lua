-- Import necessary libraries
-- luarocks install luasql-sqlite3

local sqlite3 = require("luasql.sqlite3")
local title = "Door Manager"
local version = "1.0"   
local seedData = true -- if you want to use csv seed data files, set this to true

-- Common variables for all data lists
local currentListType = "" 
local selectedID = nil
local scrollStartRow = 7  -- Adjust the starting row of the scroll area as needed
local maxRows = bbs_get_term_height() - scrollStartRow - 3
local selectedIndex = 1
local offset = 0

-- Function to connect to the database
function connectToDatabase()
    local env = sqlite3.sqlite3()
    local path = bbs_get_data_path() .. "/gm_data.db"
    local conn = env:connect(path)
    return conn
end

-- ANSI Escape Code Function for Cursor Positioning
function positionCursor(row, col)
    bbs_write_string(string.format("\x1b[%d;%df", row, col))
end

function menuHeader(name)
    bbs_clear_screen()
    bbs_write_string("|03" .. title .. " v" .. version .. "|07\r\n")
    bbs_write_string("|11" .. name .. "|07\r\n")
    bbs_write_string("|08------------------------------------------------------------------------------|07\r\n")
end

function menuFooter()  
    positionCursor(bbs_get_term_height() - 2, 1)
    bbs_write_string("|08------------------------------------------------------------------------------|07\r\n")
    bbs_write_string(" |11[|15Q|11] Quit|07  |11[|15I|11] Insert New|07")
end

function readNonBlankString(prompt, maxLength)
    local input
    repeat
        bbs_write_string(prompt)
        input = bbs_read_string(maxLength)
        if input == "" or input:match("^%s*$") then  -- Checks for empty or whitespace-only input
            bbs_write_string("\r\n|12Input cannot be blank.|07\r\n")
        end
    until input ~= "" and not input:match("^%s*$")
    return input
end

function readUniqueServerName(prompt, maxLength)
    local name, exists
    repeat
        bbs_write_string(prompt)
        name = bbs_read_string(maxLength)

        if name == "" or name:match("^%s*$") then
            bbs_write_string("\r\n|12Server name cannot be blank.|07\r\n")
        else
            local conn = connectToDatabase()
            if not conn then
                bbs_write_string("\r\n|12Failed to connect to the database.|07\r\n")
                return nil
            end

            local sql = string.format("SELECT COUNT(*) AS count FROM Servers WHERE Name = '%s'", name)
            local cursor, err = conn:execute(sql)

            if not cursor then
                bbs_write_string("\r\n|12Failed to check server name: |04" .. err .. "|07\r\n")
                conn:close()
                return nil
            end

            local row = cursor:fetch({}, "a")
            exists = row and tonumber(row.count) > 0
            cursor:close()
            conn:close()

            if exists then
                bbs_write_string("\r\n|12A server with this name already exists.\r\nPlease enter a different name.|07\r\n")
            end
        end
    until not exists and name ~= "" and not name:match("^%s*$")
    return name
end

function readYesNo(prompt)
    local input
    repeat
        bbs_write_string(prompt)
        input = bbs_getchar():upper()
        if input ~= 'Y' and input ~= 'N' then
            bbs_write_string("\r\n|12Please enter [Y]es or [N]o.|07\r\n")
        end
    until input == 'Y' or input == 'N'
    return input == 'Y'
end

function readValidInput(prompt, validator, maxLength)
    local input
    repeat
        bbs_write_string(prompt)
        input = bbs_read_string(maxLength or 50)
        if not validator(input) then
            bbs_write_string("\r\n|12Invalid input. Please try again.|07\r\n")
        end
    until validator(input)
    return input
end

function isValidIP(ip)
    -- Simple pattern matching to validate IP address
    return ip:match("^%d+%.%d+%.%d+%.%d+$") ~= nil
end

function isValidPort(port)
    -- Validate port number (typically should be between 1 and 65535)
    local portNum = tonumber(port)
    return portNum and portNum >= 1 and portNum <= 65535
end

function isValidTag(tag)
    -- Tag should not be blank. Can be further restricted if needed.
    return tag ~= "" and not tag:match("^%s*$")
end

----------------------------------------------------------------
--  Data Views - Common to All
----------------------------------------------------------------

function listItems(query, header, itemName, tableName, columnName, addItemFunction, editFunction, deleteFunction, listType)
    local conn = connectToDatabase()
    if not conn then
        bbs_write_string("Failed to connect to the database.\r\n")
        return
    end

    local selectedIndex = 1
    local itemList = {}
    local itemMapping = {} -- Mapping table to map sorted indexes to original item IDs

    local cursor, err = conn:execute(query)

    if not cursor then
        bbs_write_string("Failed to fetch " .. itemName .. ": " .. err .. "\r\n")
        conn:close()
        return
    end

    local originalIndex = 1

    local row = cursor:fetch({}, "a")
    while row do
        local itemText = string.sub(row[itemName], 1, 45)
        local itemID = row[columnName]
        
        -- Insert the item into itemList
        table.insert(itemList, { ID = itemID, Text = itemText })

        -- Map the sorted index to the original item ID
        itemMapping[originalIndex] = itemID

        row = cursor:fetch(row, "a")
        originalIndex = originalIndex + 1
    end

    cursor:close()
    conn:close()

    local numItems = #itemList
    local reloadMenu = false

    bbs_clear_screen()
    menuHeader(header)

    bbs_write_string(string.format("... |08Total items: %d|07\r\n", numItems))
    bbs_write_string("... Use Arrow Keys and view with [Enter]]\r\n")
    bbs_write_string("|08------------------------------------------------------------------------------|07\r\n")

    menuFooter()

    while true do
        if reloadMenu then
            -- Reload the menu if the user has added or deleted an item
            reloadMenu = false

            conn = connectToDatabase()
            if not conn then
                bbs_write_string("Failed to connect to the database.\r\n")
                return
            end
            cursor, err = conn:execute(query)
            if not cursor then
                bbs_write_string("Failed to fetch " .. itemName .. ": " .. err .. "\r\n")
                conn:close()
                return
            end
            itemList = {}
            itemMapping = {} -- Reset the item mapping
            originalIndex = 1
            row = cursor:fetch({}, "a")
            while row do
                local itemText = string.sub(row[itemName], 1, 45)
                local itemID = row[columnName]
                table.insert(itemList, { ID = itemID, Text = itemText })
                itemMapping[originalIndex] = itemID
                row = cursor:fetch(row, "a")
                originalIndex = originalIndex + 1
            end
            cursor:close()
            conn:close()
            numItems = #itemList

            bbs_clear_screen()
            menuHeader(header)
            bbs_write_string(string.format("... |08Total items: %d|07\r\n", numItems))
            bbs_write_string("... Use Arrow Keys and view with [Enter]:\r\n")
            bbs_write_string("|08------------------------------------------------------------------------------|07\r\n")

            menuFooter()
        end

        local startIndex = (offset * maxRows) + 1
        local endIndex = math.min(startIndex + maxRows - 1, numItems)

        -- Clear the entire list area
        for i = scrollStartRow, scrollStartRow + maxRows - 1 do
            positionCursor(i, 1)
            bbs_write_string(string.rep(" ", bbs_get_term_width()))
        end

        -- Print items for the current view and highlight the selected row
        for i = startIndex, endIndex do
            local rowIndex = i - startIndex + scrollStartRow
            local item = itemList[i]
            positionCursor(rowIndex, 1)
            
            if i == selectedIndex then
                -- Highlight the selected row
                bbs_write_string("|21|11")
            else
                bbs_write_string("|16|03")
            end
            bbs_write_string(string.format(" %-45s |16|07\r\n", item.Text))
        end

        -- Handle user input for scrolling and adding items
        local c = bbs_getchar()

        if c == 'a' or c == 'A' then
            selectedIndex = selectedIndex - 1
            if selectedIndex < 1 then
                selectedIndex = 1
            end
            if selectedIndex < startIndex then
                offset = math.max(0, offset - 1)
            end
        elseif c == 'b' or c == 'B' then
            selectedIndex = selectedIndex + 1
            if selectedIndex > numItems then
                selectedIndex = numItems
            end
            if selectedIndex > endIndex then
                offset = math.min(math.floor((selectedIndex - 1) / maxRows), numItems - maxRows)
            end
        elseif c == '\13' then
            -- Enter key
            local selectedItemID = itemMapping[selectedIndex]
            viewFunction(selectedItemID, tableName, columnName, editFunction, deleteFunction)
            reloadMenu = true -- Set this flag to reload the menu after editing
        elseif c == 'i' or c == 'I' then
            addItemFunction()
            reloadMenu = true -- Set this flag to reload the menu after adding
        elseif c:lower() == 'q' then
            break
        end
        -- Clear the last line of the list to prevent duplication
        positionCursor(scrollStartRow + maxRows - 1, 1)
        bbs_write_string(string.rep(" ", bbs_get_term_width()))
    end
end

function listCategories()
    local query = "SELECT CategoryID, Name, IsAdult FROM Categories ORDER BY Name;"
    local header = "Categories"
    local columnName = "CategoryID"
    local itemName = "Name"
    local tableName = "Categories"
    local addItemFunction = addCategory -- Add your addCategory function here
    local editFunction = addCategory
    local deleteFunction = deleteCategory
    local listType = "Categories" 
    listItems(query, header, itemName, tableName, columnName, addItemFunction, editFunction, deleteFunction, listType)
end

function listGameInfo()
    local query = "SELECT GameID, Title, IsAdult FROM GameInfo ORDER BY Title;"
    local header = "GameInfo"
    local columnName = "GameID"
    local itemName = "Title"
    local tableName = "GameInfo"
    local addItemFunction = addGameInfo 
    local editFunction = editGameInfo
    local deleteFunction = deleteGameInfo
    local listType = "Game Info"
    listItems(query, header, itemName, tableName, columnName, addItemFunction, editFunction, deleteFunction, listType)
end

function listServers()
    local query = "SELECT ServerID, Name, IP, Port, Type, Tag, IsActive FROM Servers ORDER BY Name;"
    local header = "Servers"
    local columnName = "ServerID"
    local itemName = "Name"
    local tableName = "Servers"
    local addItemFunction = addServer
    local editFunction = editServer
    local deleteFunction = deleteServer
    local listType = "Servers" 
    listItems(query, header, itemName, tableName, columnName, addItemFunction, editFunction, deleteFunction, listType)
end

function viewFunction(selectedItemID, tableName, columnName, editFunction, deleteFunction)
    if not selectedItemID then
        bbs_write_string("selectedItemID is nil.\r\n")
        return
    end

    local conn = connectToDatabase()
    if not conn then
        bbs_write_string("Failed to connect to the database.\r\n")
        return
    end

    -- Query the database to retrieve item details
    local query = string.format("SELECT * FROM %s WHERE %s = %s;", tableName, columnName, tonumber(selectedItemID))

    local cursor, err = conn:execute(query) -- Convert selectedID to a number

    if not cursor then
        bbs_write_string("Failed to fetch item details: " .. err .. "\r\n")
        conn:close()
        return
    end

    local itemDetails = cursor:fetch({}, "a")
    cursor:close()
    conn:close()

    -- Check if item exists
    if not itemDetails then
        bbs_write_string("Item not found.\r\n")
        return
    end

    -- Display item details
    bbs_clear_screen()
    bbs_write_string("Item Details:\r\n")
    for key, value in pairs(itemDetails) do
        bbs_write_string(string.format("%s: %s\r\n", key, value))
    end
    bbs_write_string("\r\n")

    -- Menu for Edit and Delete options
    bbs_write_string("Options:\r\n")
    bbs_write_string("1. Edit\r\n")
    bbs_write_string("2. Delete\r\n")
    bbs_write_string("Q. Quit\r\n")

    while true do
        local choice = bbs_getchar():lower()
        if choice == '1' then
            editFunction(selectedItemID)
            break
        elseif choice == '2' then
            deleteFunction(selectedItemID)
            break
        elseif choice == 'q' then
            break
        end
    end
end

----------------------------------------------------------------
-- Server Management
----------------------------------------------------------------

function addServer()
    bbs_clear_screen()
    bbs_write_string("|03" .. title .. " v" .. version .. "|07\r\n")
    bbs_write_string("|11Servers |07> |15Add|07\r\n")
    bbs_write_string("|08------------------------------------------------------------------------------|07\r\n")
    
    -- Server Name with validation and uniqueness check
    local name = readUniqueServerName("Enter Server Name: ", 50)
    if not name then
        return -- Exit if the name is not valid or couldn't be obtained
    end
    
   -- Server Type Selection
   local serverType
   repeat
       bbs_write_string("\r\nSelect Server Type [L]ocal / [N]etwork: ")
       serverType = bbs_getchar():upper()
       if serverType ~= 'L' and serverType ~= 'N' then
           bbs_write_string("\r\n|12Invalid selection. Please enter 'L' for Local or 'N' for Network.|07\r\n")
       end
   until serverType == 'L' or serverType == 'N'

   serverType = serverType == 'L' and 'LOCAL' or 'NETWORK'

    -- Initialize variables
    local ip, port, tag, isActive
    -- Collect additional information based on server type
    if serverType == "NETWORK" then
        ip = readValidInput("\r\nEnter IP Address: ", isValidIP, 15)
        port = readValidInput("\r\nEnter Port: ", isValidPort, 5)
        tag = readValidInput("\r\nEnter Server Tag (up to 3 characters): ", isValidTag, 3)
    else
        ip = nil
        port = nil
        tag = nil
    end

    -- isActive flag Selection using the reusable function
    local isActive = readYesNo("\r\nIs it active? [Y]es / [N]o: ") and 1 or 0

    -- Database connection and insertion
    local conn = connectToDatabase()
    if not conn then
        bbs_write_string("\r\n|12Failed to connect to the database.|07\r\n")
        bbs_pause()
        return
    end

    local sql = string.format("INSERT INTO Servers (Name, IP, Port, Type, Tag, IsActive) VALUES ('%s', %s, %s, '%s', %s, %d)", 
                              name, 
                              ip and string.format("'%s'", ip) or "NULL", 
                              port and string.format("'%s'", port) or "NULL", 
                              serverType, 
                              tag and string.format("'%s'", tag) or "NULL", 
                              isActive)

    local res, err = conn:execute(sql)
    if not res then
        bbs_write_string("\r\n|12Failed to add server: " .. err .. "|07\r\n")
    else
        bbs_write_string("\r\n|10Server added successfully.|07\r\n")
    end

    conn:close()  -- Close the connection here to ensure it's closed whether the query succeeds or fails
    bbs_pause()
    bbs_clear_screen()
end

function deleteServer()
    bbs_clear_screen()
    bbs_write_string("Delete Server\r\n")

    -- First, list all servers for the user to choose from
    listServers()

    bbs_write_string("\r\nEnter the ID of the server to delete: ")
    local serverID = bbs_read_string(10)

    -- Convert serverID to a number and validate
    serverID = tonumber(serverID)
    if not serverID then
        bbs_write_string("\r\n|12Invalid server ID.|07\r\n")
        bbs_pause()
        return
    end

    local conn = connectToDatabase()
    if not conn then
        bbs_write_string("\r\n|12Failed to connect to the database.|07\r\n")
        bbs_pause()
        return
    end

    -- Check if the server is used in any Games before deleting
    local sqlCheck = string.format("SELECT COUNT(*) AS GameCount FROM GameInstances WHERE ServerID = %d", serverID)
    local cursor, err = conn:execute(sqlCheck)

    if not cursor then
        bbs_write_string("\r\n|12Failed to query games: " .. err .. "|07\r\n")
        conn:close()
        bbs_pause()
        return
    end

    local row = cursor:fetch({}, "a")
    if not row or tonumber(row.GameCount) > 0 then
        bbs_write_string("\r\n|12Cannot delete server, as it has games assigned to it.|07\r\n")
        cursor:close()
        conn:close()
        bbs_pause()
        return
    end

    cursor:close()

    -- Confirm deletion
    bbs_write_string("\r\n|14Are you sure you want to delete server ID " .. serverID .. "? (yes/no): |07")
    local confirmation = bbs_read_string(3)

    if confirmation:lower() == "yes" then
        local sql = string.format("DELETE FROM Servers WHERE ServerID = %d", serverID)
        local res, err = conn:execute(sql)
        if not res then
            bbs_write_string("\r\n|12Failed to delete server: " .. err .. "|07\r\n")
        else
            bbs_write_string("\r\n|10Server deleted successfully.|07\r\n")
        end
    else
        bbs_write_string("\r\n|14Server deletion cancelled.|07\r\n")
    end

    conn:close()
    bbs_pause()
end

-- Define the getServerInfo function to retrieve server details by ID
function getServerInfo(serverID)
    local conn = connectToDatabase()  -- Connect to your database here

    if not conn then
        return nil
    end

    local sql = string.format("SELECT * FROM Servers WHERE ServerID = %d", serverID)
    local cursor, err = conn:execute(sql)

    if not cursor then
        conn:close()
        return nil
    end

    local serverInfo = cursor:fetch({}, "a")
    cursor:close()
    conn:close()

    return serverInfo
end

function editServer()
    while true do
        -- First, list all servers for the user to choose from
        listServers()

        -- Ask the user to enter the ID of the server to edit or [Q] to Quit
        bbs_write_string("\r\nEnter server ID or [Q] to Quit: ")
        local input = bbs_getchar()

        if input:upper() == 'Q' then
            -- Quit the edit operation
            break
        end

        local serverID = tonumber(input)

        -- Check if the entered server ID is valid and exists
        if not serverID then
            bbs_write_string("\r\n|12Invalid server ID.|07\r\n")
            bbs_pause()
        else
            local conn = connectToDatabase()
            if not conn then
                bbs_write_string("\r\n|12Failed to connect to the database.|07\r\n")
                bbs_pause()
                return
            end

            local sqlCheck = string.format("SELECT COUNT(*) AS ServerCount FROM Servers WHERE ServerID = %d", serverID)
            local cursor, err = conn:execute(sqlCheck)

            if not cursor then
                bbs_write_string("\r\n|12Failed to query servers: " .. err .. "|07\r\n")
                conn:close()
                bbs_pause()
                return
            end

            local row = cursor:fetch({}, "a")
            if not row or tonumber(row.ServerCount) == 0 then
                bbs_write_string("\r\n|12No server found with the specified ID.|07\r\n")
                cursor:close()
                conn:close()
                bbs_pause()
            else
                cursor:close()

                while true do
                    bbs_clear_screen()
                    local serverInfo = getServerInfo(serverID)  -- Retrieve server details

                    bbs_write_string("Editing Server ID: " .. serverID .. "\r\n")
                    bbs_write_string("Name: " .. serverInfo.Name .. "\r\n")
                    bbs_write_string("Type: " .. serverInfo.Type .. "\r\n") -- Show the server type

                    if serverInfo.Type ~= "LOCAL" then
                        bbs_write_string("IP: " .. serverInfo.IP .. "\r\n")
                        bbs_write_string("Port: " .. serverInfo.Port .. "\r\n")
                        bbs_write_string("Tag: " .. serverInfo.Tag .. "\r\n")
                    end

                    bbs_write_string("Active: " .. (serverInfo.IsActive == 1 and "Yes" or "No") .. "\r\n")

                    -- Ask the user which field to edit or [Q] to Quit
                    bbs_write_string("\r\nSelect field to edit or [Q] to Quit:\r\n")
                    bbs_write_string("[1] Name\r\n")
                    bbs_write_string("[2] Type\r\n") -- Option to change the server type
                    if serverInfo.Type ~= "LOCAL" then
                        bbs_write_string("[3] IP\r\n")
                        bbs_write_string("[4] Port\r\n")
                        bbs_write_string("[5] Tag\r\n")
                    end
                    bbs_write_string("[6] Active\r\n")
                    bbs_write_string("[Q] Quit\r\n")

                    bbs_write_string("\r\nEnter choice: ")

                    local choice = bbs_getchar()

                    if choice == '1' then
                        -- Edit Name
                        bbs_write_string("\r\nEnter new Name: ")
                        local newName = readUniqueServerName("", 50, serverID)  -- Check for uniqueness
                        if newName then
                            updateServerField(serverID, "Name", newName, "Server name updated successfully.")
                        else
                            bbs_write_string("\r\n|12Invalid or duplicate server name.|07\r\n")
                        end
                    elseif choice == '2' then
                        -- Edit Type
                        if serverInfo.Type == "LOCAL" then
                            -- Change from LOCAL to NETWORK and clear IP, Port, and Tag fields
                            updateServerField(serverID, "Type", "NETWORK", "Changed to NETWORK Type successfully.")
                            updateServerField(serverID, "IP", "", "IP cleared successfully.")
                            updateServerField(serverID, "Port", "", "Port cleared successfully.")
                            updateServerField(serverID, "Tag", "", "Tag cleared successfully.")
                        else
                            -- Change from NETWORK to LOCAL
                            updateServerField(serverID, "Type", "LOCAL", "Changed to LOCAL Type successfully.")
                        end
                    elseif choice == '3' and serverInfo.Type ~= "LOCAL" then
                        -- Edit IP only if the server type is not "LOCAL"
                        bbs_write_string("\r\nEnter new IP: ")
                        local newIP = readValidInput("", isValidIP, 15)
                        updateServerField(serverID, "IP", newIP, "IP updated successfully.")
                    elseif choice == '4' and serverInfo.Type ~= "LOCAL" then
                        -- Edit Port only if the server type is not "LOCAL"
                        bbs_write_string("\r\nEnter new Port: ")
                        local newPort = readValidInput("", isValidPort, 5)
                        updateServerField(serverID, "Port", newPort, "Port updated successfully.")
                    elseif choice == '5' and serverInfo.Type ~= "LOCAL" then
                        -- Edit Tag only if the server type is not "LOCAL"
                        bbs_write_string("\r\nEnter new Tag (up to 3 characters): ")
                        local newTag = readValidInput("", isValidTag, 3)
                        updateServerField(serverID, "Tag", newTag, "Tag updated successfully.")
                    elseif choice == '6' then
                        -- Edit Active
                        bbs_write_string("\r\nSet Active [Y]es / [N]o: ")
                        local newActive = (bbs_getchar():upper() == 'Y') and 1 or 0
                        updateServerField(serverID, "IsActive", newActive, "Status updated successfully.")
                    elseif choice:upper() == 'Q' then
                        -- Quit editing this server
                        break
                    else
                        -- Invalid choice
                        bbs_write_string("|12Invalid choice|07\r\n\r\n")
                        bbs_pause()
                    end
                end
                conn:close() -- Close the connection after editing this server
            end
        end
    end
end

function updateServerField(serverID, field, value, successMessage)
    local conn = connectToDatabase()
    local sql = string.format("UPDATE Servers SET %s = '%s' WHERE ServerID = %d", field, value, serverID)
    local res, err = conn:execute(sql)

    if res then
        if successMessage then
            bbs_write_string("\r\n|10" .. successMessage .. "|07\r\n")
        else
            bbs_write_string("\r\n|10Server updated successfully.|07\r\n")
        end
        bbs_pause()
    else
        bbs_write_string("\r\n|12Failed to update server: " .. err .. "|07\r\n")
        bbs_pause()
    end

    conn:close() -- Close the connection after the update
end

----------------------------------------------------------------
-- Category Management
----------------------------------------------------------------

function addCategory()
    bbs_clear_screen()
    bbs_write_string("Add New Category\r\n")

    -- Category Name
    bbs_write_string("Enter Category Name: ")
    local name = bbs_read_string(50)

    -- Ask for adult category flag
    bbs_write_string("\r\nIs this an adult category? [Y]es / [N]o: ")
    local isAdultKey = bbs_getchar():upper()
    local isAdult = (isAdultKey == 'Y') and 1 or 0

    -- Database connection and insertion
    local conn = connectToDatabase()
    if not conn then
        bbs_write_string("Failed to connect to the database.\r\n")
        bbs_pause()
        return
    end

    local sql = string.format("INSERT INTO Categories (Name, IsAdult) VALUES ('%s', %d)", 
                              name, isAdult)

    local res, err = conn:execute(sql)
    if not res then
        bbs_write_string("Failed to add category: " .. err .. "\r\n")
    else
        bbs_write_string("\r\nCategory added successfully.\r\n")
    end

    conn:close()  -- Close the connection here to ensure it's closed whether the query succeeds or fails
    bbs_pause()
end

function deleteCategory()
    local conn = connectToDatabase()
    if not conn then
        bbs_write_string("Failed to connect to the database.\r\n")
        return
    end

    -- List all categories for the user to choose from
    listCategories()

    -- Ask the user to enter the ID of the category to delete
    bbs_write_string("\r\nEnter the ID of the category to delete: ")
    local categoryId = bbs_read_string(10) 

    -- Convert categoryId to a number and validate
    categoryId = tonumber(categoryId)
    if not categoryId then
        bbs_write_string("Invalid category ID.\r\n")
        bbs_pause()
        return
    end

    -- Check if the category is used in any Games before deleting
    local sqlCheck = string.format("SELECT COUNT(*) AS GameCount FROM GameInstances WHERE CategoryID = %d", categoryId)
    local cursor, err = conn:execute(sqlCheck)

    if not cursor then
        bbs_write_string("Failed to query games: " .. err .. "\r\n")
        conn:close()
        return
    end

    local row = cursor:fetch({}, "a")
    if tonumber(row.GameCount) > 0 then
        bbs_write_string("\r\nCannot delete category, as it has games assigned to it.\r\n")
        cursor:close()
        conn:close()
        bbs_pause()
        return
    end

    cursor:close()

    -- Confirm deletion
    bbs_write_string("\r\nAre you sure you want to delete category ID " .. categoryId .. "? Type (yes/no): ")
    local confirmation = bbs_read_string(3)

    if confirmation:lower() == "yes" then
        -- Perform deletion
        local sql = string.format("DELETE FROM Categories WHERE CategoryID = %d", categoryId)
        local res, err = conn:execute(sql)
        if not res then
            bbs_write_string("Failed to delete category: " .. err .. "\r\n")
        else
            bbs_write_string("\r\nCategory deleted successfully.\r\n")
        end
    else
        bbs_write_string("\r\nCategory deletion cancelled.\r\n")
    end

    conn:close()
    bbs_pause()
end

function editCategory()
    bbs_clear_screen()
    bbs_write_string("Edit Category\r\n")

    -- First, list all categories for the user to choose from
    listCategories()

    -- Ask the user to enter the ID of the category to edit
    bbs_write_string("\r\nEnter the ID of the category to edit: ")
    local categoryId = tonumber(bbs_read_string(10))

    -- Check if the entered category ID is valid and exists
    if not categoryId then
        bbs_write_string("\r\nInvalid category ID.\r\n")
        bbs_pause()
        return
    end

    local conn = connectToDatabase()
    if not conn then
        bbs_write_string("Failed to connect to the database.\r\n")
        return
    end

    local sqlCheck = string.format("SELECT COUNT(*) AS CategoryCount FROM Categories WHERE CategoryID = %d", categoryId)
    local cursor, err = conn:execute(sqlCheck)

    if not cursor then
        bbs_write_string("Failed to query categories: " .. err .. "\r\n")
        conn:close()
        return
    end

    local row = cursor:fetch({}, "a")
    if not row or tonumber(row.CategoryCount) == 0 then
        bbs_write_string("\r\nNo category found with the specified ID.\r\n")
        cursor:close()
        conn:close()
        bbs_pause()
        return
    end

    cursor:close()

    -- Ask the user which field to edit
    bbs_write_string("\r\nSelect field to edit:\r\n")
    bbs_write_string("[1] Name\r\n")
    bbs_write_string("[2] Mature\r\n")
    bbs_write_string("[3] Cancel\r\n")
    bbs_write_string("\r\nEnter choice: ")

    local choice = bbs_getchar()

    if choice == '1' then
        -- Edit Name
        bbs_write_string("\r\nEnter new Name: ")
        local newName = bbs_read_string(50)
        updateCategoryField(categoryId, "Name", newName)
    elseif choice == '2' then
        -- Edit IsAdult
        bbs_write_string("\r\nSet as adult category? [Y]es / [N]o: ")
        local isAdult = (bbs_getchar():upper() == 'Y') and 1 or 0
        updateCategoryField(categoryId, "IsAdult", isAdult)
    else
        -- Cancel
        bbs_write_string("\r\nEdit canceled.\r\n")
    end

    bbs_pause()
end

function updateCategoryField(categoryId, field, value)
    local conn = connectToDatabase()
    local sql
    if field == "IsAdult" then
        sql = string.format("UPDATE Categories SET %s = %d WHERE CategoryID = %d", field, value, categoryId)
    else
        sql = string.format("UPDATE Categories SET %s = '%s' WHERE CategoryID = %d", field, value, categoryId)
    end

    local res, err = conn:execute(sql)

    if res then
        bbs_write_string("\r\nCategory updated successfully.\r\n")
    else
        bbs_write_string("\r\nFailed to update category: " .. err .. "\r\n")
    end

    conn:close() -- Close the connection after the update
end

----------------------------------------------------------------
-- Games Database (metadata about the game)
----------------------------------------------------------------

function addGameInfo()
    bbs_clear_screen()
    bbs_write_string("Add New Game Info\r\n")

    -- Game Title
    bbs_write_string("Enter Game Title: ")
    local title = bbs_read_string(50)

    -- Game Description
    bbs_write_string("\r\nEnter Game Description: ")
    local description = bbs_read_string(100)

    -- Ask for adult game info flag
    bbs_write_string("\r\nIs this game for adults only? [Y]es / [N]o: ")
    local isAdultKey = bbs_getchar():upper()
    local isAdult = (isAdultKey == 'Y') and 1 or 0

    -- Year Published
    bbs_write_string("\r\nEnter Year Published: ")
    local yearPublished = tonumber(bbs_read_string(4))

    -- Author Name
    bbs_write_string("\r\nEnter Author Name: ")
    local authorName = bbs_read_string(50)

    -- Database connection and insertion
    local conn = connectToDatabase()
    if not conn then
        bbs_write_string("\r\nFailed to connect to the database.\r\n")
        bbs_pause()
        return
    end

    local sql = string.format("INSERT INTO GameInfo (Title, Description, IsAdult, YearPublished, AuthorName) VALUES ('%s', '%s', %d, %d, '%s')", 
                              title, description, isAdult, yearPublished, authorName)

    local res, err = conn:execute(sql)
    if not res then
        bbs_write_string("\r\nFailed to add game info: " .. err .. "\r\n")
    else
        bbs_write_string("\r\nGame info added successfully.\r\n")
    end

    conn:close()  -- Close the connection here to ensure it's closed whether the query succeeds or fails
    bbs_pause()
end

function deleteGameInfo()
    local conn = connectToDatabase()
    if not conn then
        bbs_write_string("\r\nFailed to connect to the database.\r\n")
        bbs_pause()
        return
    end

    -- List all game info for the user to choose from
    listGameInfo()

    -- Ask the user to enter the ID of the game info to delete
    bbs_write_string("\r\nEnter the ID of the game info to delete: ")
    local gameIDToDelete = tonumber(bbs_read_string(10)) 

    -- Convert gameIDToDelete to a number and validate
    if not gameIDToDelete then
        bbs_write_string("\r\n|12Invalid game info ID.|07\r\n")
        bbs_pause()
        return
    end

    -- Check if the game info is used in any Game Instances before deleting
    local sqlCheck = string.format("SELECT COUNT(*) AS GameInstanceCount FROM GameInstances WHERE GameID = %d", gameIDToDelete)
    local cursor, err = conn:execute(sqlCheck)

    if not cursor then
        bbs_write_string("\r\n|12Failed to query game instances: " .. err .. "|07\r\n")
        conn:close()
        bbs_pause()
        return
    end

    local row = cursor:fetch({}, "a")
    if tonumber(row.GameInstanceCount) > 0 then
        bbs_write_string("\r\n|12Cannot delete game info, as it is associated with game instances.|07\r\n")
        cursor:close()
        conn:close()
        bbs_pause()
        return
    end

    cursor:close()

    -- Confirm deletion
    bbs_write_string("\r\n|14Are you sure you want to delete game info ID " .. gameIDToDelete .. "? (yes/no): |07")
    local confirmation = bbs_read_string(3)

    if confirmation:lower() == "yes" then
        -- Perform deletion
        local sql = string.format("DELETE FROM GameInfo WHERE GameID = %d", gameIDToDelete)
        local res, err = conn:execute(sql)
        if not res then
            bbs_write_string("\r\n|12Failed to delete game info: " .. err .. "|07\r\n")
        else
            bbs_write_string("\r\n|10Game info deleted successfully.|07\r\n")
        end
    else
        bbs_write_string("\r\n|14Game info deletion cancelled.|07\r\n")
    end

    conn:close()
    bbs_pause()
end

function editGameInfo()
    -- Ask the user to enter the ID of the game info to edit
    bbs_write_string("\r\nEnter Game ID: ")
    local input = bbs_read_string(10)

    if input:lower() == 'q' then
        return
    end

    local gameID = tonumber(input)

    if not gameID then
        bbs_write_string("\r\n|12Invalid game ID.|07\r\n")
        bbs_pause()
        return
    end

    local conn = connectToDatabase()
    if not conn then
        bbs_write_string("\r\n|12Failed to connect to the database.|07\r\n")
        bbs_pause()
        return
    end

    local sqlCheck = string.format("SELECT COUNT(*) AS GameCount FROM GameInfo WHERE GameID = %d", gameID)
    local cursor, err = conn:execute(sqlCheck)

    if not cursor then
        bbs_write_string("\r\n|12Failed to query game info: " .. err .. "|07\r\n")
        conn:close()
        bbs_pause()
        return
    end

    local row = cursor:fetch({}, "a")
    if not row or tonumber(row.GameCount) == 0 then
        bbs_write_string("\r\n|12No game info found with the specified ID.|07\r\n")
        cursor:close()
        conn:close()
        bbs_pause()
        return
    end

    cursor:close()

    -- Ask the user which field to edit
    bbs_write_string("\r\nSelect field to edit:\r\n")
    bbs_write_string("[1] Title\r\n")
    bbs_write_string("[2] Description\r\n")
    bbs_write_string("[3] Is Adult\r\n")
    bbs_write_string("[4] Year Published\r\n")
    bbs_write_string("[5] Author Name\r\n")
    bbs_write_string("[6] Cancel\r\n")
    bbs_write_string("\r\nEnter choice: ")

    local choice = bbs_getchar()

    if choice == '1' then
        -- Edit Title
        bbs_write_string("\r\nEnter new Title: ")
        local newTitle = bbs_read_string(50)
        updateGameInfoField(gameID, "Title", newTitle)
    elseif choice == '2' then
        -- Edit Description
        bbs_write_string("\r\nEnter new Description: ")
        local newDescription = bbs_read_string(100)
        updateGameInfoField(gameID, "Description", newDescription)
    elseif choice == '3' then
        -- Edit IsAdult
        bbs_write_string("\r\nSet as adult game info? [Y]es / [N]o: ")
        local isAdult = (bbs_getchar():upper() == 'Y') and 1 or 0
        updateGameInfoField(gameID, "IsAdult", isAdult)
    elseif choice == '4' then
        -- Edit Year Published
        bbs_write_string("\r\nEnter new Year Published: ")
        local newYearPublished = bbs_read_string(4)
        updateGameInfoField(gameID, "YearPublished", newYearPublished)
    elseif choice == '5' then
        -- Edit Author Name
        bbs_write_string("\r\nEnter new Author Name: ")
        local newAuthorName = bbs_read_string(50)
        updateGameInfoField(gameID, "AuthorName", newAuthorName)
    else
        -- Cancel
        bbs_write_string("\r\nEdit canceled.\r\n")
    end

    bbs_pause()
end

function updateGameInfoField(gameID, field, value)
    local conn = connectToDatabase()
    local sql

    if field == "IsAdult" then
        sql = string.format("UPDATE GameInfo SET %s = %d WHERE GameID = %d", field, value, gameID)
    else
        sql = string.format("UPDATE GameInfo SET %s = '%s' WHERE GameID = %d", field, value, gameID)
    end

    local res, err = conn:execute(sql)

    if res then
        bbs_write_string("\r\n|10Game info updated successfully.|07\r\n")
    else
        bbs_write_string("\r\n|12Failed to update game info: " .. err .. "|07\r\n")
    end

    conn:close() -- Close the connection after the update
end

function displayGameOptions(gameID)
    -- Display options to edit or delete the selected game
    bbs_clear_screen()
    bbs_write_string("Selected Game Options\r\n")
    bbs_write_string("[1] Edit Game\r\n")
    bbs_write_string("[2] Delete Game\r\n")
    bbs_write_string("[3] Back\r\n")
    bbs_write_string("\r\nEnter choice: ")

    local choice = bbs_getchar()

    if choice == '1' then
        editGameInfo(gameID)
    elseif choice == '2' then
        deleteGameInfo(gameID)
    elseif choice == '3' then
        selectedGameID = nil
    else
        bbs_write_string("|12Invalid choice|07\r\n\r\n")
        bbs_pause()
    end
end

----------------------------------------------------------------
-- Games Instances (servers, categories, game code)
----------------------------------------------------------------

function manageGameInstances()
    -- Menu for managing specific game instances (GameInstances)
    -- Include options like List Game Instances, Add Game Instance, Edit Game Instance, Delete Game Instance
end

function addGame()
    bbs_clear_screen()
    bbs_write_string("Add New Game Instance\r\n")

    -- Select Game from GameInfo
    local gameId = selectGame()  -- Implement this function to choose a game

    -- Select Category
    local categoryId = selectCategory()  -- Implement this function to choose a category

    -- Select Server
    local serverId, serverType = selectServer()  -- Reuse the selectServer function

    -- Enter Game Code if server is Network
    local gameCode = nil
    if serverType == 'NETWORK' then
        bbs_write_string("\r\nEnter Game Code: ")
        gameCode = bbs_read_string(20)
    end

    -- Database connection and insertion
    local conn = connectToDatabase()
    if not conn then
        bbs_write_string("Failed to connect to the database.\r\n")
        bbs_pause()
        return
    end

    local sql = string.format("INSERT INTO GameInstances (GameID, CategoryID, ServerID, GameCode) VALUES (%d, %d, %d, '%s')",
                              gameId, categoryId, serverId, gameCode or "NULL")

    local res, err = conn:execute(sql)
    if not res then
        bbs_write_string("Failed to add game instance: " .. err .. "\r\n")
    else
        bbs_write_string("\r\nGame instance added successfully.\r\n")
    end

    conn:close()
    bbs_pause()
end

----------------------------------------------------------------
-- Create Database
----------------------------------------------------------------

function initializeDatabase()
    local conn = connectToDatabase()
    if not conn then
        bbs_write_string("Failed to connect to the database.\r\n")
        return
    end

    local sqlServers = [[
        CREATE TABLE IF NOT EXISTS Servers (
            ServerID INTEGER PRIMARY KEY AUTOINCREMENT,
            Name TEXT NOT NULL,
            IP TEXT,
            Port TEXT,
            Type TEXT NOT NULL,
            Tag TEXT,
            IsActive INTEGER DEFAULT 0
        );
    ]]

    local sqlCategories = [[
        CREATE TABLE IF NOT EXISTS Categories (
            CategoryID INTEGER PRIMARY KEY AUTOINCREMENT,
            Name TEXT NOT NULL,
            IsAdult INTEGER NOT NULL
        );
    ]]

    local sqlGameInfo = [[
        CREATE TABLE IF NOT EXISTS GameInfo (
            GameID INTEGER PRIMARY KEY AUTOINCREMENT,
            Title TEXT NOT NULL,
            Description TEXT,
            IsAdult INTEGER NOT NULL,
            YearPublished INTEGER,
            AuthorName TEXT
        );
    ]]

    local sqlGameInstances = [[
        CREATE TABLE IF NOT EXISTS GameInstances (
            InstanceID INTEGER PRIMARY KEY AUTOINCREMENT,
            GameID INTEGER,
            CategoryID INTEGER,
            ServerID INTEGER,
            GameCode TEXT,
            FOREIGN KEY (GameID) REFERENCES GameInfo(GameID),
            FOREIGN KEY (CategoryID) REFERENCES Categories(CategoryID),
            FOREIGN KEY (ServerID) REFERENCES Servers(ServerID)
        );
    ]]

    local res, err = conn:execute(sqlServers)
    if not res then
        bbs_write_string("Failed to create Servers table: " .. err .. "\r\n")
    end

    res, err = conn:execute(sqlCategories)
    if not res then
        bbs_write_string("Failed to create Categories table: " .. err .. "\r\n")
    end

    res, err = conn:execute(sqlGameInfo)
    if not res then
        bbs_write_string("Failed to create Games Info table: " .. err .. "\r\n")
    end

    res, err = conn:execute(sqlGameInstances)
    if not res then
        bbs_write_string("Failed to create Games Instance table: " .. err .. "\r\n")
    end

    -- Check if the GameInfo table is empty
    local sqlCheckGameInfo = "SELECT COUNT(*) AS GameInfoCount FROM GameInfo;"
    local cursor, err = conn:execute(sqlCheckGameInfo)
    if not cursor then
        bbs_write_string("Failed to check GameInfo table: " .. err .. "\r\n")
    end

    local row = cursor:fetch({}, "a")
    local gameInfoCount = tonumber(row.GameInfoCount)
    cursor:close()

    if seedData and gameInfoCount == 0 then
        seedGameInfoTableFromCSVFile("gm_db_seed_titles.csv", "|")
        seedCategoriesTableFromCSVFile("gm_db_seed_categories.csv", "|")
        seedServersTableFromCSVFile("gm_db_seed_servers.csv", "|")
        
    elseif seedData then
        bbs_write_string("Database seeding skipped because the GameInfo table is not empty.\r\n")
    else
        bbs_write_string("Proceeding without database seeding.\r\n")
    end

    conn:close()
end

function seedServersTableFromCSVFile(csvFileName, delimiter)
    local conn = connectToDatabase()
    if not conn then
        bbs_write_string("Failed to connect to the database for seeding.\r\n")
        return
    end

    -- Open the CSV file for reading
    local file = io.open(bbs_get_data_path() .. "/" .. csvFileName, "r")
    if not file then
        bbs_write_string("Failed to open CSV file '" .. bbs_get_data_path() .. "/".. csvFileName .. "' for reading.\r\n")
        conn:close()
        return
    end

    -- Read and parse each line of the CSV file
    for line in file:lines() do
        local rowData = {}
        for value in string.gmatch(line, '[^'..delimiter..']+') do
            table.insert(rowData, value)
        end

        if #rowData == 6 then
            local name = rowData[1]
            local ip = rowData[2]
            local port = rowData[3]
            local type = rowData[4]
            local tag = rowData[5]
            local isActive = tonumber(rowData[6]) or 0

            local sql = string.format("INSERT INTO Servers (Name, IP, Port, Type, Tag, IsActive) VALUES ('%s', '%s', '%s', '%s', '%s', %d)",
                name, ip, port, type, tag, isActive)

            local res, err = conn:execute(sql)
            if not res then
                bbs_write_string("Failed to insert data for server '" .. name .. "': " .. err .. "\r\n")
            else
                bbs_write_string("Data for server '" .. name .. "' inserted successfully.\r\n")
            end
        else
            bbs_write_string("Skipping invalid CSV line: " .. line .. "\r\n")
        end
    end

    file:close()
    conn:close()
end

function seedCategoriesTableFromCSVFile(csvFileName, delimiter)
    local conn = connectToDatabase()
    if not conn then
        bbs_write_string("Failed to connect to the database for seeding.\r\n")
        return
    end

    -- Open the CSV file for reading
    local file = io.open(bbs_get_data_path() .. "/" .. csvFileName, "r")
    if not file then
        bbs_write_string("Failed to open CSV file '" .. bbs_get_data_path() .. "/".. csvFileName .. "' for reading.\r\n")
        conn:close()
        return
    end

    -- Read and parse each line of the CSV file
    for line in file:lines() do
        local rowData = {}
        for value in string.gmatch(line, '[^'..delimiter..']+') do
            table.insert(rowData, value)
        end

        if #rowData == 2 then
            local name = rowData[1]
            local isAdult = rowData[2] == "Y" and 1 or 0

            local sql = string.format("INSERT INTO Categories (Name, IsAdult) VALUES ('%s', %d)",
                name, isAdult)

            local res, err = conn:execute(sql)
            if not res then
                bbs_write_string("Failed to insert data for category '" .. name .. "': " .. err .. "\r\n")
            else
                bbs_write_string("Data for category '" .. name .. "' inserted successfully.\r\n")
            end
        else
            bbs_write_string("Skipping invalid CSV line: " .. line .. "\r\n")
        end
    end

    file:close()
    conn:close()
end

-- seed GameInfo table from CSV file
function seedGameInfoTableFromCSVFile(csvFileName, delimiter)
    local conn = connectToDatabase()
    if not conn then
        bbs_write_string("Failed to connect to the database for seeding.\r\n")
        return
    end

    -- Open the CSV file for reading
    local file = io.open(bbs_get_data_path() .. "/" .. csvFileName, "r")
    if not file then
        bbs_write_string("Failed to open CSV file '" .. bbs_get_data_path() .. "/".. csvFileName .. "' for reading.\r\n")
        conn:close()
        return
    end

    -- Read and parse each line of the CSV file
    for line in file:lines() do
        local rowData = {}
        for value in string.gmatch(line, '[^'..delimiter..']+') do
            table.insert(rowData, value)
        end

        if #rowData == 5 then
            local title = rowData[1]
            local description = rowData[2]
            local yearPublished = tonumber(rowData[3])
            local authorName = rowData[4]
            local isAdult = rowData[5] == "Y" and 1 or 0

            local sql = string.format("INSERT INTO GameInfo (Title, Description, YearPublished, AuthorName, IsAdult) VALUES ('%s', '%s', %d, '%s', %d)",
                title, description, yearPublished, authorName, isAdult)

            local res, err = conn:execute(sql)
            if not res then
                bbs_write_string("Failed to insert data for game '" .. title .. "': " .. err .. "\r\n")
            else
                bbs_write_string("Data for game '" .. title .. "' inserted successfully.\r\n")
            end
        else
            bbs_write_string("Skipping invalid CSV line: " .. line .. "\r\n")
        end
    end

    file:close()
    conn:close()
end

----------------------------------------------------------------------
-- Main menu
----------------------------------------------------------------------

function displayMainMenu()
    menuHeader("Main Menu")
    bbs_write_string("|02[|101|02] Servers|07\r\n")
    bbs_write_string("|02[|102|02] Categories|07\r\n")
    bbs_write_string("|02[|103|02] Games Database|07\r\n")  
    bbs_write_string("|02[|104|02] Games Menus|07\r\n")  
    bbs_write_string("|08[|07Q|08] Exit|07\r\n")
    bbs_write_string("\r\n|06Cmd? ")
    local choice = bbs_getchar()
    return choice
end

----------------------------------------------------------------------
-- Main loop
----------------------------------------------------------------------
bbs_write_string("\x1b[?25l") --hide the cursor
initializeDatabase()
while true do
    local choice = displayMainMenu()

    if choice == '1' then
        listServers()
    elseif choice == '2' then
        listCategories() 
    elseif choice == '3' then
        listGameInfo()  -- This menu manages Game Titles
    elseif choice == '4' then
        manageGameInstances()  -- This menu manages Game Instances
    elseif choice:lower() == 'q' then
        break
    else
        bbs_write_string("|12Invalid choice|07\r\n\r\n")
        bbs_pause()
    end
end
bbs_write_string("\x1b[?25h") --show cursor