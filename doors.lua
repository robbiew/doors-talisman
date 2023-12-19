-- Import necessary libraries
-- luarocks install luasql-sqlite3
local sqlite3 = require("luasql.sqlite3")

-- Function to connect to the database
function connectToDatabase()
    local env = sqlite3.sqlite3()
    local path = bbs_get_data_path() .. "/doors.db"
    local conn = env:connect(path)
    return conn
end

-- ANSI Escape Code Function for Cursor Positioning
function positionCursor(row, col)
    bbs_write_string(string.format("\x1b[%d;%df", row, col))
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
    -- This can be made more sophisticated based on your requirements
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

function displayMainMenu()
    bbs_clear_screen()
    bbs_write_string("|03Door Manager v1.0|07\r\n")
    bbs_write_string("|11Main Menu|07\r\n")
    bbs_write_string("|08------------------------------------------------------------------------------|07\r\n")
    bbs_write_string("|02[|101|02] Servers|07\r\n")
    bbs_write_string("|02[|102|02] Categories|07\r\n")
    bbs_write_string("|02[|103|02] Games|07\r\n")
    bbs_write_string("|08[|07Q|08] Exit|07\r\n")
    bbs_write_string("\r\n|06Cmd? ")
    local choice = bbs_getchar()
    return choice
end

----------------------------------------------------------------
-- Server Management
----------------------------------------------------------------

function manageServers()

    while true do
        bbs_clear_screen()
        listServers()
      
        bbs_write_string("\r\n|02[|101|02] Edit|07\r\n")
        bbs_write_string("|02[|102|02] Add|07\r\n")
        bbs_write_string("|02[|103|02] Delete|07\r\n")
        bbs_write_string("|08[|07Q|08] Back|07\r\n")
        bbs_write_string("\r\n|06Cmd? ")
        local choice = bbs_getchar()

        if choice == '1' then
            editServer()  
        elseif choice == '2' then
            addServer()  
        elseif choice == '3' then
            deleteServer()  
        elseif choice:lower() == 'q' then
            break
        else
            bbs_write_string("Invalid choice, please try again.\r\n")
            bbs_pause()
        end
    end
end

function listServers()
    local conn = connectToDatabase()
    local cursor = conn:execute("SELECT ServerID, Name, IP, Port, Type, Tag, IsActive FROM Servers")
    bbs_clear_screen()
    bbs_write_string("|03Door Manager v1.0|07\r\n")
    bbs_write_string("|11Servers |07> |15List|07\r\n")
    bbs_write_string("|08------------------------------------------------------------------------------|07\r\n")
    bbs_write_string("ID  Name         Type     Address          Port   Tag   Active\r\n")
    bbs_write_string("--------------------------------------------------------------\r\n")
    local row = cursor:fetch({}, "a")
    while row do
        local ip = row.IP or "--"
        local port = row.Port or "--"
        local tag = row.Tag or "--"
        local isActive = row.IsActive == 1 and "YES" or "NO"
        bbs_write_string(string.format("%-3d %-12s %-8s %-16s %-6s %-5s %-3s\r\n", 
                                      row.ServerID, row.Name:sub(1, 12), row.Type, ip:sub(1, 16), port, tag, isActive))
        row = cursor:fetch(row, "a")
    end
    cursor:close()
    conn:close()

end

function addServer()
    bbs_clear_screen()
    bbs_write_string("|03Door Manager v1.0|07\r\n")
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
    bbs_clear_screen()

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
                        bbs_write_string("\r\n|12Invalid choice. Please select a valid option.|07\r\n")
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

function manageCategories()
    while true do
        bbs_clear_screen()
        bbs_write_string("|11Category Management|07\r\n")
        bbs_write_string("|08------------------------------------------------------------------------------|07\r\n")
        listCategories()
        bbs_write_string("\r\n|02[|101|02] Edit|07\r\n")
        bbs_write_string("|02[|102|02] Add|07\r\n")
        bbs_write_string("|02[|103|02] Delete|07\r\n")
        bbs_write_string("|08[|07Q|08] Back|07\r\n")
        bbs_write_string("\r\n|06Cmd? ")
        local choice = bbs_getchar()

        if choice == '1' then
            editCategory()
        elseif choice == '2' then
            addCategory()  
        elseif choice == '3' then
            deleteCategory()  
        elseif choice:lower() == 'q' then
            break
        else
            bbs_write_string("Invalid choice, please try again.\r\n")
            bbs_pause()
        end
    end
end

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

-- ANSI Escape Code Function for Cursor Positioning
function positionCursor(row, col)
    bbs_write_string(string.format("\x1b[%d;%df", row, col))
end

function listCategories()
    local conn = connectToDatabase()
    if not conn then
        bbs_write_string("Failed to connect to the database.\r\n")
        return
    end

    -- Query to fetch all categories
    local sql = "SELECT CategoryID, Name, IsAdult FROM Categories ORDER BY Name;"
    local cursor, err = conn:execute(sql)

    if not cursor then
        bbs_write_string("Failed to fetch categories: " .. err .. "\r\n")
        conn:close()
        return
    end

    bbs_clear_screen()
    bbs_write_string("|03Door Manager v1.0|07\r\n")
    bbs_write_string("|11Categories |07> |15List|07\r\n")
    bbs_write_string("|08------------------------------------------------------------------------------|07\r\n")
    
    local categories = {}
    local maxRowsPerColumn = 13  -- Set the maximum rows per column

    local row = cursor:fetch({}, "a")
    while row do
        local isAdultText = row.IsAdult == 1 and "Yes" or "No"
        local name = string.sub(row.Name, 1, 15) -- Limit name to 15 characters
        table.insert(categories, string.format("%-3d %-26s %-5s\r\n", row.CategoryID, name, isAdultText))
        row = cursor:fetch(row, "a")
    end

    cursor:close()
    conn:close()

    local numCategories = #categories
    local numColumns = 2
    local numRows = math.ceil(numCategories / numColumns)
    
    -- Print headers
    positionCursor(4, 1)
    bbs_write_string("ID  Name                       Adult    ID  Name                        Adult\r\n")
    bbs_write_string("------------------------------------    -------------------------------------\r\n")

    -- Print categories in two columns with a maximum number of rows per column
    local rowOffset = 5
    local colSpacing = 42

    for i = 1, numRows do
        for j = 1, numColumns do
            local index = (i - 1) * numColumns + j
            if index <= numCategories then
                positionCursor(i + rowOffset, (j - 1) * colSpacing + 1)
                bbs_write_string(categories[index])
            end
        end
        if i == maxRowsPerColumn then
            break  -- Stop printing after reaching the maximum rows per column
        end
    end
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
-- Games Management
----------------------------------------------------------------

function manageGames()
    while true do
        bbs_clear_screen()
        bbs_write_string("|11Game Management|07\r\n")
        bbs_write_string("|08------------------------------------------------------------------------------|07\r\n")
        bbs_write_string("1. Manage Game Info\r\n")
        bbs_write_string("2. Manage Game Instances\r\n")
        bbs_write_string("\r\n[Q] Return to Main Menu\r\n")
        bbs_write_string("\r\nEnter choice: ")
        local choice = bbs_getchar()

        if choice == '1' then
            manageGameInfo()
        elseif choice == '2' then
            manageGameInstances()
        elseif choice:lower() == 'q' then
            break
        else
            bbs_write_string("Invalid choice, please try again.\r\n")
            bbs_pause()
        end
    end
end

----------------------------------------------------------------
-- Games Info (metadata about the game)
----------------------------------------------------------------

function manageGameInfo()
    while true do
        bbs_clear_screen()
        bbs_write_string("|11Game Info Management|07\r\n")
        bbs_write_string("|08------------------------------------------------------------------------------|07\r\n")
        bbs_write_string("1. List Game Info\r\n")
        bbs_write_string("2. Add New Game Info\r\n")
        bbs_write_string("\r\n[Q] Return to Previous Menu\r\n")
        bbs_write_string("\r\nEnter choice: ")
        local choice = bbs_getchar()

        if choice == '1' then
            listGameInfo()
        elseif choice == '2' then
            addGameInfo()
        elseif choice:lower() == 'q' then
            break
        else
            bbs_write_string("Invalid choice, please try again.\r\n")
            bbs_pause()
        end
    end
end

function addGameInfo()
    bbs_clear_screen()
    bbs_write_string("Add New Game Info\r\n")

    -- Collecting game information from the user
    bbs_write_string("Enter Game Title: ")
    local title = bbs_read_string(50)

    bbs_write_string("\r\nEnter Game Description: ")
    local description = bbs_read_string(100)

    bbs_write_string("\r\nIs this game for adults only? [Y]es / [N]o: ")
    local isAdult = (bbs_getchar():upper() == 'Y') and 1 or 0

    bbs_write_string("\r\nEnter Year Published: ")
    local yearPublished = tonumber(bbs_read_string(4))

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

    conn:close()
    bbs_pause()
end

function listGameInfo()
    local conn = connectToDatabase()
    if not conn then
        bbs_write_string("Failed to connect to the database.\r\n")
        return
    end

    local sql = "SELECT GameID, Title, YearPublished, AuthorName FROM GameInfo ORDER BY Title;"
    local cursor, err = conn:execute(sql)

    if not cursor then
        bbs_write_string("Failed to fetch game info: " .. err .. "\r\n")
        conn:close()
        return
    end

    bbs_clear_screen()
    bbs_write_string("List of Game Info:\r\n")
    bbs_write_string("ID  Title               Year  Author       \r\n")
    bbs_write_string("------------------------------------------------------------\r\n")

    local row = cursor:fetch({}, "a")
    while row do
        -- Truncate fields to fit the display
        local title = row.Title:sub(1, 20)  -- Truncate title to 20 characters
        local author = row.AuthorName:sub(1, 15)  -- Truncate author name to 15 characters

        -- Format the output string
        local output = string.format("%-4d%-20s%-6d%-15s", row.GameID, title, row.YearPublished, author)
        bbs_write_string(output .. "\r\n")
        row = cursor:fetch(row, "a")
    end

    cursor:close()
    conn:close()
    bbs_pause()
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

    conn:close()
end

----------------------------------------------------------------------
-- Main loop
----------------------------------------------------------------------

initializeDatabase()
while true do
    local choice = displayMainMenu()

    if choice == '1' then
        manageServers()
    elseif choice == '2' then
        manageCategories() 
    elseif choice == '3' then
        manageGames()
    elseif choice:lower() == 'q' then
        break
    else
        bbs_write_string("\r\nInvalid choice, please try again.\r\n")
        bbs_pause()
    end
end
