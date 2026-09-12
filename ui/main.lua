local ffi = require("ffi")
local C = ffi.C
ffi.cdef[[
]]


-- General functions and implementation
-- ====================================


--- Convenience wrapper for debug output using string.format().
--
-- @param string Formating string for string.format.
-- @param any* Formating string parameters.
--
local function _debug(...)
    DebugError(string.format(...))
end


local enum = {
    offertype = {
        ["any"] = 0,
        ["buy"] = 1,
        ["sell"] = 2,
    }
}


local m = {}

-- Tracks original menu functions.
m.original = {}
-- Overrides for original menu function.
m.override = {}
-- Filter functions for trade offers.
m.filter = {}

--- Static configuration for the menu.
m.config = {
    -- Columns shown for the wares listings.
    wareColumns = {
        {
            id = "faction",
            index = 1,
            title = "Faction",
            dataSample = "\27[faction_argon]\27[faction_argon]\27[faction_argon]",
            sortProperty = "factionName",
            fixedWidth = true,
        },
        {
            id = "station",
            index = 2,
            title = "Station",
            dataSample = "HAT Argon Trading Station",
            sortProperty = "stationText",
            fixedWidth = false,
        },
        {
            id = "sector",
            index = 3,
            title = "Sector",
            dataSample = "Argon Prime",
            sortProperty = "sectorText",
            fixedWidth = false,
        },
        {
            id = "distance",
            index = 4,
            title = "Distance",
            dataSample = "999j",
            sortProperty = "distance",
            fixedWidth = true,
        },
        {
            id = "ware",
            index = 5,
            title = "Ware",
            dataSample = "Advanced Electronics",
            sortProperty = "wareText",
            fixedWidth = false,
        },
        {
            id = "type",
            index = 6,
            title = "Type",
            dataSample = "Sells",
            sortProperty = "typeText",
            fixedWidth = true,
        },
        {
            id = "price",
            index = 7,
            title = "Price",
            dataSample = "99999.99 Cr",
            sortProperty = "price",
            fixedWidth = true,
        },
        {
            id = "markup",
            index = 8,
            title = "Markup",
            dataSample = "+99.99%",
            sortProperty = "markupSort",
            fixedWidth = true,
        },
        {
            id = "amount",
            index = 9,
            title = "Amount",
            dataSample = "999999",
            sortProperty = "amount",
            fixedWidth = true,
        },
    },

    -- Default parameters for sorting trade offers.
    defaultSortParameters = {
        { property = "factionName", ascending = true },
        { property = "stationText", ascending = true },
        { property = "sectorText", ascending = true },
        { property = "distance", ascending = true },
        { property = "wareText", ascending = true },
        { property = "typeText", ascending = true },
        { property = "price", ascending = true },
        { property = "markup", ascending = true },
        { property = "amount", ascending = true },
    },

    -- @TODO: The fucking font implements superscript only for digits 1, 2, and 3
    --     (facepalm) Unbelievable... Find an alternative way to mark the order instead...
    -- Column indicators when sorting by player-indicated order.
    sortOrderIndicators = {"¹", "²", "³", "⁴", "⁵", "⁶", "⁷", "⁸", "⁹"},

    -- Upper limit for the maximum distance filter.
    maxDistanceFilterLimit = 10,
}


--- Initialises the mod.
--
function m.init()
    m.menu = Helper.getMenu("MapMenu")
    m.menuConfig = m.menu.uix_getConfig()

    m.initData()

    -- UI Extensions and HUD events.
    m.menu.registerCallback("createRightBar_on_start", m.registerRightBar)
    m.menu.registerCallback("createInfoFrame2_on_menu_infoModeRight", m.createMenu)

    -- Store references to original functions.
    m.original.setSectorFilter = m.menu.setSectorFilter
    m.original.filterTradeWares = m.menu.filterTradeWares
    m.original.filterTradeVolume = m.menu.filterTradeVolume
    m.original.filterTradeRelation = m.menu.filterTradeRelation

    -- Override original functions with custom implementation.
    m.menu.setSectorFilter = m.override.setSectorFilter
    m.menu.filterTradeWares = m.override.filterTradeWares
    m.menu.filterTradeVolume = m.override.filterTradeVolume
    m.menu.filterTradeRelation = m.override.filterTradeRelation
end


--- Initialises various data structures, states, and caches.
--
function m.initData()
    -- If function is invoked during loading, the necessary data is still not available, schedule the call once data has been fully loaded instead.
    -- @NOTE: This is more of a hack, but so far it seems to work fine.
    if C.GetPlayerID() == 0 then
        registerForEvent("gameLoadingDone", getElement("Scene.UIContract"), m.initData)
        return
    end

    local playerSector = C.GetContextByClass(C.GetPlayerID(), "sector", false)
    m.state = {
        currentPage = 1,
        sortParameters = { { property = "factionName", ascending = true } },
        filters = {
            factions = {},
            -- @TODO: Currently not changeable by player, but maybe think about adding support for it in the future.
            minDistance = 0,
            maxDistance = m.config.maxDistanceFilterLimit,
            type = 0,
        },
        referenceSector = ConvertStringToLuaID(tostring(playerSector)),
    }

    -- Make parameters accessible by sort property.
    -- @NOTE: Keep this snippet in sync with other occurance or deduplicate this code.
    m.state.sortParametersBy = {}
    for priority, parameter in ipairs(m.state.sortParameters) do
        -- Do not show column sorting priority when sorting by a singular player-selected column.
        if #m.state.sortParameters > 1 then
            parameter.priority = priority
        else
            parameter.priority = nil
        end
        m.state.sortParametersBy[parameter.property] = parameter
    end

    -- Keep track of widgets that might require updates after their creation.
    m.widgets = {}

    for _, column in ipairs(m.config.wareColumns) do
        column.width = column.fixedWidth and m.calculateRequiredColumnTextWidth(column.title, column.dataSample) or nil
    end

    m.cache = {
        factions = {},
        volumeInfo = {},
        wareVolume = {},
    }
    m.updateCache()
end


--- Registers custom button on the map menu's right bar used to access market analytics.
--
-- @param menuConfig {*} Map menu configuration.
--
function m.registerRightBar(menuConfig)
    -- Bail out if the button has already been registered.
    for _, entry in ipairs(menuConfig.rightBar) do
        if entry.mode =="marketanalytics" then
            return
        end
    end

    local entry = {
        name = "Market Analytics",
        icon = "mapst_fs_trade",
        mode = "marketanalytics",
        helpOverlayID = "map_sidebar_marketanalytics",
        helpOverlayText = "Market analytics allows you to browse, filter, and sort trade offers by various criteria.",
    }

    table.insert(menuConfig.rightBar, { spacing = true })
    table.insert(menuConfig.rightBar, entry)
end


--- Creates the market analytics menu.
--
function m.createMenu()
    if m.menu.searchTableMode ~= "marketanalytics" then
        return
    end

    m.menu.infoFrame2 = m.createFrame()

    local verticalOffset = 0

    local titleTable = m.createHeaderTable(m.menu.infoFrame2, 0, verticalOffset)
    verticalOffset = verticalOffset + titleTable:getVisibleHeight() + Helper.borderSize * 2

    local controlsTable = m.createControlsTable(m.menu.infoFrame2, 0, verticalOffset)
    verticalOffset = verticalOffset + controlsTable:getVisibleHeight() + Helper.borderSize * 2

    local waresTable = m.createWaresTable(m.menu.infoFrame2, 0, verticalOffset)
    verticalOffset = verticalOffset + waresTable:getVisibleHeight() + Helper.borderSize * 2

    local offersAvailableHeight = m.menu.infoFrame2.properties.height - verticalOffset
    local offersPageSize = math.floor(offersAvailableHeight / (Helper.scaleY(Helper.standardTextHeight) + Helper.borderSize))

    m.updateOffers(offersPageSize, false, false, false)
    m.renderOffers(waresTable)
    m.updateControls()
end


--- Creates frame for the market analytics menu.
--
-- Frame is created manually instead of relying on vanilla's menu.createInfoFrame2() in order to have more space available for the menu than what the rightbar
-- menus usually have.
--
-- @return table Frame descriptor.
--
function m.createFrame()
    -- Avoid overlap with the menus on the left side (property menus etc).
    local leftPadding = Helper.frameBorder + Helper.borderSize + Helper.playerInfoConfig.width + Helper.borderSize
    -- Avoid overlap with the right-bar buttons.
    local rightPadding = Helper.borderSize + m.menu.sideBarWidth + Helper.borderSize + Helper.frameBorder
    -- Avoid overlap with the search box in upper-left corner, adding an additinal row of spacing.
    local topPadding = Helper.frameBorder + Helper.borderSize * 2 + (Helper.scaleY(Helper.standardButtonHeight) + Helper.borderSize) * 4
    -- Leave the standard gap at the bottom of the screen.
    local bottomPadding = Helper.frameBorder + Helper.borderSize

    local width = Helper.viewWidth - leftPadding - rightPadding
    local height = Helper.viewHeight - topPadding - bottomPadding

    local frame = Helper.createFrameHandle(
        m.menu,
        {
            x = leftPadding,
            y = topPadding,
            width = width,
            height = height,
            layer = m.menuConfig.infoFrameLayer2,
            standardButtons = {},
        }
    )
    frame:setBackground("solid", { color = Color["frame_background_semitransparent"]})

    return frame
end


--- Creates menu header table at the very top of the frame.
--
-- @param frame {*} Frame descriptor where the table should be created.
-- @param offsetX number Horisontal offset for created table relative to frame borders.
-- @param offsetY number Vertical offset for created table relative to frame borders.
--
-- @return table Table descriptor.
--
function m.createHeaderTable(frame, offsetX, offsetY)
    local ftable = frame:addTable(
        1,
        {
            tabOrder = 1,
            highlightMode = "off",
            backgroundID = "solid",
            backgroundColor = Color["frame_background_semitransparent"],
            reserveScrollBar = false,
            x = offsetX,
            y = offsetY,
        }
    )

    local row = ftable:addRow(false, { bgColor = Helper.defaultTitleBackgroundColor })
    row[1]:createText("Market Analytics", Helper.headerRowCenteredProperties)

    return ftable
end


--- Creates table with various menu controls (paginatioin, filters, etc).
--
-- @param frame {*} Frame descriptor where the table should be created.
-- @param offsetX number Horisontal offset for created table relative to frame borders.
-- @param offsetY number Vertical offset for created table relative to frame borders.
--
-- @return table Table descriptor.
--
function m.createControlsTable(frame, offsetX, offsetY)
    local ftable = frame:addTable(
        13,
        {
            tabOrder = 1,
            highlightMode = "off",
            backgroundID = "solid",
            backgroundColor = Color["frame_background_semitransparent"],
            reserveScrollBar = false,
            x = offsetX,
            y = offsetY,
        }
    )


    -- Miscellanous controls
    -- =====================
    local row = ftable:addRow(true, { fixed = true })
    row[1]:setColSpan(3):createButton():setText(GetComponentData(m.state.referenceSector, "name"), { halign = "center" })
    local pickerX = row.table.frame.properties.x + row[1]:getOffsetX()
    local pickerY = ftable.frame.properties.y + ftable.properties.y + ftable:getVisibleHeight()
    row[1].handlers.onClick = function()
        local options = {}
        for name, sector in pairs(m.cache.sectors) do
            table.insert(options, { id = sector, text = name, state = tostring(sector) == tostring(m.state.referenceSector) })
        end
        table.sort(options, function(a, b) return a.text < b.text end)
        m.createValuePicker(pickerX, pickerY, row[1]:setColSpan(3):getWidth(), "Select Reference Sector", options, m.setReferenceSector)
    end
    row[4]:createButton({ width = m.menuConfig.mapRowHeight + Helper.standardTextOffsetx }):setIcon("menu_reset_view")
    row[4].handlers.onClick = function()
        local playerSector = C.GetContextByClass(C.GetPlayerID(), "sector", false)
        m.setReferenceSector(ConvertStringToLuaID(tostring(playerSector)))
    end

    row[11]:createButton():setText("Reset", { halign = "center" })
    row[11].handlers.onClick = function() m.resetAllControls() end

    row[12]:createText(" ", { y = Helper.scaleY((Helper.standardButtonHeight - Helper.standardTextHeight) / 2), halign = "center" })
    m.widgets.offersAge = row[12]
    row[13]:createButton():setText("Refresh", { halign = "center" })
    row[13].handlers.onClick = function()
        m.updateOffers(m.state.pageSize, true, false, false)
        m.menu.refreshInfoFrame2()
    end


    -- Pagination controls
    -- ===================
    row = ftable:addRow(true, { fixed = true })

    row[11]:createButton():setText("\27[widget_arrow_left_01] Prev", { halign = "center" })
    row[11].handlers.onClick = function()
        m.state.currentPage = m.state.currentPage > 1 and m.state.currentPage - 1 or m.state.pageCount
        m.menu.refreshInfoFrame2()
    end
    m.widgets.previousPage = row[11]

    row[12]:createEditBox({ description = "description" }):setText("1 / 1", { halign = "center" })
    row[12].handlers.onEditBoxActivated = function(_)
        -- Prevent menu refresh while editing the text.
        m.menu.noupdate = true

        -- Show just the current page when starting the edit.
        C.SetEditBoxText(m.widgets.currentPage.id, tostring(m.state.currentPage))
    end
    row[12].handlers.onEditBoxDeactivated = function(_, text, _)
        -- Allow menu refresh at this point.
        m.menu.noupdate = nil

        local page = tonumber(text)
        if page and page ~= m.state.currentPage then
            m.state.currentPage = page
            m.menu.refreshInfoFrame2()
        else
            C.SetEditBoxText(m.widgets.currentPage.id, string.format("%s / %s", m.state.currentPage, m.state.pageCount))
        end
    end
    m.widgets.currentPage = row[12]

    row[13]:createButton():setText("Next \27[widget_arrow_right_01]", { halign = "center" })
    row[13].handlers.onClick = function()
        m.state.currentPage = m.state.currentPage < m.state.pageCount and m.state.currentPage + 1 or 1
        m.menu.refreshInfoFrame2()
    end
    m.widgets.nextPage = row[13]

    return ftable
end


--- Creates filter controls in the wares table.
--
-- @param ftable {*} Table descriptor for wares listing.
--
function m.createFilterControls(ftable)
    local row = ftable:addRow(true, { fixed = true })

    -- Factions filter
    local filterText = m.getFilterText(m.filter.factions)
    row[1]:createButton({bgColor = Color["row_background"]}):setText(filterText, { color = Color["text_normal"] })
    local pickerVerticalPosition = ftable.frame.properties.y + ftable.properties.y + ftable:getVisibleHeight()
    row[1].handlers.onClick = function()
        local options = {}
        for _, faction in pairs(m.cache.factions) do
            local text = string.format("%s\27[%s]  %s", Helper.convertColorToText(faction.color), faction.icon, faction.name)
            -- The "name" property is only used for sorting, it is not required for multi-value picker.
            table.insert(options, { id = faction.id, name = faction.name, text = text, state = m.state.filters.factions[faction.id] })
        end

        table.sort(options, function(a, b) return a.name < b.name end)

        local x = row.table.frame.properties.x + row[1]:getOffsetX()
        local y = pickerVerticalPosition
        m.createMultiValuePicker(x, y, row[1]:getWidth() + row[2]:getWidth(), "Select Factions", options, m.setFactionFilter)
    end
    row[1].handlers.onRightClick = function() return m.menu.closeContextMenu() or m.setFactionFilter({}) end

    -- Sector filter
    filterText = m.getFilterText(m.filter.mapSearchSectors)
    row[3]:createButton({bgColor = Color["row_background"]}):setText(filterText, { color = Color["text_normal"] })
    row[3].handlers.onClick = function()
        local options = m.generateSectorFilterOptions()
        -- Place selected sectors at top for easier access/overview since the list can get quite large.
        table.sort(options, function(a, b) return a.state == b.state and a.text < b.text or a.state and not b.state or false end)
        local x = row.table.frame.properties.x + row[3]:getOffsetX()
        local y = pickerVerticalPosition
        m.createMultiValuePicker(x, y, row[3]:getWidth() - Helper.borderSize, "Select Sectors", options, m.setSectorFilter)
    end
    row[3].handlers.onRightClick = function() return m.menu.closeContextMenu() or m.setSectorFilter({}) end

    -- Distance filter
    local distanceOptions = {}
    for range = 0, m.config.maxDistanceFilterLimit do
        -- Extra whitespace at end of text helps align the text with text in data rows.
        table.insert(distanceOptions, { id = tostring(range), text = tostring(range) .. "j ", icon = "", displayremoveoption = false, align = "right" })
    end

    row[4]:createDropDown(
        distanceOptions,
        {
            startOption = tostring(m.state.filters.maxDistance),
            height = Helper.standardButtonHeight,
            bgColor = Color["row_background"],
        }
    )
    row[4]:setTextProperties({ color = Color["text_normal"], halign = "right" })
    row[4].handlers.onDropDownActivated = function() m.menu.noupdate = true end
    row[4].handlers.onDropDownConfirmed = function(_, id)
        m.menu.noupdate = nil
        m.setMaxDistanceFilter(tonumber(id))
    end

    -- Ware filter
    filterText = m.getFilterText(m.filter.mapSearchWares)
    row[5]:createButton({bgColor = Color["row_background"]}):setText(filterText, { color = Color["text_normal"] })
    row[5].handlers.onClick = function()
        local options = {}
        local _, filteredWares = m.menu.getTradeWareFilter(true)
        for _, ware in pairs(m.menu.economyWares) do
            local state = false
            for _, filteredWare in ipairs(filteredWares) do
                if filteredWare == ware then
                    state = true
                    break
                end
            end
            table.insert(options, { id = ware, text = GetWareData(ware, "name"), state = state })
        end

        -- Place selected wares at top for easier access/overview since the list can get quite large.
        table.sort(options, function(a, b) return a.state == b.state and a.text < b.text or a.state and not b.state or false end)
        local x = row.table.frame.properties.x + row[5]:getOffsetX()
        local y = pickerVerticalPosition
        m.createMultiValuePicker(x, y, row[5]:getWidth() - Helper.borderSize, "Select Wares", options, m.setWareFilter)
    end
    row[5].handlers.onRightClick = function() return m.menu.closeContextMenu() or m.setWareFilter({}) end

    -- Offer type filter
    local options = {
        { id = tostring(enum.offertype.any),
          text = "Any", icon = "", displayremoveoption = false},
        { id = tostring(enum.offertype.buy),
          text = string.format("%s%s", Helper.convertColorToText(Color["trade_buyoffer"]), "Buys"), icon = "", displayremoveoption = false},
        { id = tostring(enum.offertype.sell),
          text = string.format("%s%s", Helper.convertColorToText(Color["trade_selloffer"]), "Sells"), icon = "", displayremoveoption = false},
    }
    row[6]:createDropDown(
        options,
        {
            startOption = tostring(m.state.filters.type),
            height = Helper.standardButtonHeight,
            bgColor = Color["row_background"],
        }
    )
    row[6].handlers.onDropDownActivated = function() m.menu.noupdate = true end
    row[6].handlers.onDropDownConfirmed = function(_, id)
        m.menu.noupdate = nil
        m.setTypeFilter(tonumber(id))
    end

    -- Amount filter by volume
    row[9]:createButton({bgColor = Color["row_background"]}):setText(filterText, { color = Color["text_normal"] })
    row[9]:setText(m.getFilterText(m.filter.mapTradeVolume), { halign = "right" })
    row[9].handlers.onClick = function()
        local volumeInfo = m.getTradeVolumeInfo() or m.getTradeVolumeInfo(0)
        m.setTradeVolumeFilter(volumeInfo.nextVolume)

        m.updateOffers(m.state.pageSize, false, true, true)
	m.menu.refreshMainFrame = true
    end
    row[9].handlers.onRightClick = function() return m.menu.closeContextMenu() or m.setTradeVolumeFilter() end
end


--- Creates listing table for the wares.
--
-- @param frame {*} Frame descriptor where the tabkle should be created.
-- @param offsetX number Horisontal offset for created table relative to frame borders.
-- @param offsetY number Vertical offset for created table relative to frame borders.
--
-- @return table Table descriptor.
--
function m.createWaresTable(frame, offsetX, offsetY)
    local ftable = frame:addTable(
        #m.config.wareColumns,
        {
            tabOrder = 1,
            highlightMode = "off",
            backgroundID = "solid",
            backgroundColor = Helper.color.semitransparent,
            reserveScrollBar = false,
            x = offsetX,
            y = offsetY,
        }
    )

    for index, column in ipairs(m.config.wareColumns) do
        if column.width then
            ftable:setColWidth(index, column.width)
        end
    end

    local row = ftable:addRow(true, { fixed = true, bgColor = Color["row_title_background"]})
    for index, column in ipairs(m.config.wareColumns) do
        local button = row[index]:createButton()
        button:setText(column.title)

        -- Adds sorting indicator cue for the player. Priority is used when player has explicitly selected secondary columns to use for sorting.
        if m.state.sortParametersBy[column.sortProperty] then
            local arrow = m.state.sortParametersBy[column.sortProperty].ascending and "\27[widget_arrow_down_01]" or "\27[widget_arrow_up_01]"
            local priority = m.state.sortParametersBy[column.sortProperty].priority
            button:setText2(string.format("%s%s", m.config.sortOrderIndicators[priority] or "", arrow), { halign = "right" })
        end

        -- Sort offers by clicked column. Reverse sorting order on subsequent clicks.
        button.handlers.onClick = function()
            local parameter = m.state.sortParametersBy[column.sortProperty]
            if parameter then
                parameter.ascending = not parameter.ascending
            else
                -- With new column selected for sorting, clear player's existing multi-sort selection.
                parameter = { property = column.sortProperty, ascending = true }
                m.state.sortParameters = { parameter }
                m.state.sortParametersBy = {}
                m.state.sortParametersBy[parameter.property] = parameter
            end

            m.updateOffers(m.state.pageSize, false, false, true)
            m.menu.refreshInfoFrame2()
        end

        -- Sort offers by player-indicated column ordering.
        button.handlers.onRightClick = function()
            local selected = m.state.sortParametersBy[column.sortProperty]

            -- Custom multi-column sorting is not in effect.
            if selected and #m.state.sortParameters == 1 then
                return
            end

            if selected then
                local newSortParameters = {}
                for _, parameter in ipairs(m.state.sortParameters) do
                    if selected.property ~= parameter.property then
                        table.insert(newSortParameters, parameter)
                    end
                end
                m.state.sortParameters = newSortParameters
            else
                local parameter = { property = column.sortProperty, ascending = true }
                table.insert(m.state.sortParameters, parameter)
            end

            -- Make parameters accessible by sort property, and include priority for rendering.
            -- @NOTE: Keep this snippet in sync with other occurance or deduplicate this code.
            m.state.sortParametersBy = {}
            for priority, parameter in ipairs(m.state.sortParameters) do
                -- Do not show column sorting priority when sorting by a singular player-selected column.
                if #m.state.sortParameters > 1 then
                    parameter.priority = priority
                else
                    parameter.priority = nil
                end
                m.state.sortParametersBy[parameter.property] = parameter
            end

            m.updateOffers(m.state.pageSize, false, false, true)
            m.menu.refreshInfoFrame2()
        end
    end

    m.createFilterControls(ftable)

    -- Separator line.
    row = ftable:addRow(false)
    row[1]:setColSpan(9):createText(" ", {cellBGColor = Color["row_background"], titleColor = Color["row_title"], height = 1})

    return ftable
end


--- Render offers in the ware listing table.
--
-- @param ftable {*} Table descriptor.
--
function m.renderOffers(ftable)
    if #m.state.filteredOffers == 0 then
        return
    end

    local from = 1 + m.state.pageSize * (m.state.currentPage - 1)
    local to = math.min(#m.state.filteredOffers, m.state.pageSize * m.state.currentPage)

    for index = from, to do
        local offer = m.state.filteredOffers[index]
        local row = ftable:addRow(true, { fixed = true })
        row[1]:createButton({height = m.menuConfig.mapRowHeight, bgColor = Color["row_background"]}):setText(offer.factionText)
        row[1].handlers.onClick = function() m.setFactionFilter({{id = offer.faction, state = true}}) end
        row[1].handlers.onRightClick = function() return m.menu.closeContextMenu() or m.setFactionFilter({{id = offer.faction, state = false}}, true) end

        row[2]:createText(offer.stationText)

        local truncatedText, mouseOverText = m.truncateText(offer.sectorText, row[3]:getWidth())
        row[3]:createButton({height = m.menuConfig.mapRowHeight, bgColor = Color["row_background"], mouseOverText = mouseOverText}):setText(truncatedText)
        row[3].handlers.onClick = function()
            if C.IsControlPressed() then
                m.setReferenceSector(offer.sector)
            else
                m.setSectorFilter({{id = offer.sector, state = true}})
            end
        end
        row[3].handlers.onRightClick = function() return m.menu.closeContextMenu() or m.setSectorFilter({{id = offer.sector, state = false}}, true) end

        row[4]:createText(offer.distanceText, { halign = "right" })

        truncatedText, mouseOverText = m.truncateText(offer.wareText, row[3]:getWidth())
        row[5]:createButton({height = m.menuConfig.mapRowHeight, bgColor = Color["row_background"], mouseOverText = mouseOverText}):setText(truncatedText)
        row[5].handlers.onClick = function() m.setWareFilter({{id = offer.ware, state = true}}) end
        row[5].handlers.onRightClick = function() return m.menu.closeContextMenu() or m.setWareFilter({{id = offer.ware, state = false}}, true) end

        row[6]:createText(offer.typeText)
        row[7]:createText(offer.priceText, { halign = "right" })
        row[8]:createText(offer.markupText, { halign = "right" })
        row[9]:createText(offer.amountText, { halign = "right" })
    end
end


--- Returns list of all active trade offers known to player, including various metadata or text rendering.
--
-- @return [table{faction = component<faction>, factionText = string, factionName = string, station = component<station>, stationText = string,
--     sector = component<sector>, sectorText = string, distance = number, distanceText = string, ware = component<ware>, wareText = string,
--     type = 1|2|nil, typeText = string, price = number, priceText = string, markup = number, markupText = string,
--     amount = number, amountText = string}]  List of active trade offers.
--
function m.getTradeOffers()
    local offers = {}
    local currencySuffix = " " .. ReadText(1001, 101)

    for sectorName, sector in pairs(m.cache.sectors) do
        local stations = GetContainedStations(sector, true) or {}
        local jumpDistance = FindJumpRoute(m.state.referenceSector, sector)
        local realDistance = C.GetDistanceBetween(ConvertStringTo64Bit(tostring(m.state.referenceSector)), ConvertStringTo64Bit(tostring(sector)))
        for _, station in ipairs(stations) do
            local trades = GetTradeList(station) or {}
            local stationOwner = GetComponentData(station, "owner")
            local stationOwnerIcon, stationOwnerColor = m.cache.factions[stationOwner].icon, m.cache.factions[stationOwner].color
            for _, trade in ipairs(trades) do
                local averagePrice = GetWareData(trade.ware, "avgprice")
                local markup = trade.price/averagePrice - 1
                local factionText = string.format("%s\27[%s]", Helper.convertColorToText(stationOwnerColor), stationOwnerIcon)
                local typeTextColor =
                    trade.isbuyoffer and Helper.convertColorToText(Color["trade_buyoffer"]) or
                    trade.isselloffer and Helper.convertColorToText(Color["trade_selloffer"]) or
                    ""
                local typeText = string.format("%s%s", typeTextColor, trade.isbuyoffer and "Buys" or trade.isselloffer and "Sells" or "None")
                local priceTextColor = Helper.convertColorToText(Helper.interpolatePriceColor(trade.ware, trade.price, trade.isselloffer))
                local priceText = string.format("%s%s%s", priceTextColor, ConvertMoneyString(trade.price, true, true, 0, true), currencySuffix)
                table.insert(
                    offers,
                    {
                        faction = stationOwner,
                        factionText = factionText,
                        factionName = trade.factionname,
                        station = trade.station,
                        stationText = trade.stationname,
                        sector = sector,
                        sectorText = sectorName,
                        distance = jumpDistance,
                        distanceText = tostring(jumpDistance) .. "j",
                        realDistance = realDistance,
                        ware = trade.ware,
                        wareText = trade.name,
                        type = trade.isbuyoffer and 1 or trade.isselloffer and 2 or nil,
                        typeText = typeText,
                        price = trade.price,
                        -- Arguments: price, includeFraction, includeComma, ?, ?
                        priceText = priceText,
                        markup = markup,
                        markupText = string.format("%.2f%%", markup * 100),
                        -- When sorting, markup has opposite meanings in terms of "quality" for buys/sells.
                        markupSort = trade.isbuyoffer and -markup or markup,
                        amount = trade.amount,
                        amountText = tostring(trade.amount),
                    }
                )
            end
        end
    end

    return offers
end


--- Updates menu offer data.
--
-- Offer data is cached in order to avoid expensive computation and lag.
--
-- @param pageSize number Number of offers to show per page.
-- @param forceRefresh bool Force refresh of cached data.
-- @param forceFilter bool Force filtering of cached data.
-- @param forceSort bool Force sorting of cached data.
--
function m.updateOffers(pageSize, forceRefresh, forceFilter, forceSort)
    if not m.state.offers or forceRefresh or forceFilter then
        m.updateCache()
    end

    if not m.state.offers or forceRefresh then
        m.state.offers = m.getTradeOffers()
        m.state.offersAge = C.GetCurrentGameTime()
        forceFilter = true
        forceSort = true
    end

    if forceFilter then
        m.state.filteredOffers = {}
        for _, offer in ipairs(m.state.offers) do
            local passed = true
            for _, filterFunction in pairs(m.filter) do
                if not filterFunction(offer) then
                    passed = false
                    break
                end
            end
            if passed then
                table.insert(m.state.filteredOffers, offer)
            end
        end
        forceSort = true
    end

    if forceSort then
        local sortParameters = m.generateFullSortParameters(m.state.sortParameters)
        table.sort(m.state.filteredOffers, function(a, b) return m.compareOffers(a, b, sortParameters) end)
    end

    m.state.pageSize = pageSize
    m.state.pageCount = math.ceil(#m.state.filteredOffers / m.state.pageSize)
    m.state.currentPage = math.min(m.state.currentPage, m.state.pageCount)

    -- This can happen with sequence: pageCount > 0 -> pageCount == 0 -> pageCount > 0.k
    if m.state.pageCount > 0 and m.state.currentPage == 0 then
        m.state.currentPage = 1
    end
end


--- Updates menu controls (text etc) based on current state.
--
function m.updateControls()
    m.widgets.currentPage.properties.text.text = string.format("%s / %s", m.state.currentPage, m.state.pageCount)

    local passedTime = C.GetCurrentGameTime() - m.state.offersAge
    local offersAgeColor =
        passedTime < 120 and Color["text_normal"] or
        passedTime < 300 and Color["text_neutral"] or
        passedTime < 900 and Color["text_warning"] or
        Color["text_negative"]
    m.widgets.offersAge.properties.text = string.format("%s%s", Helper.convertColorToText(offersAgeColor),Helper.getPassedTime(m.state.offersAge))
end


--- Comparator for sorting trade offers.
--
-- Sort parameters are attempted in the given order until a non-equality can be established.
--
-- @param a {*} Offer entry.
-- @param b {*} Offer entry.
-- @param sortParameters [{ property = string, ascending = bool}] List of parameters to use for comparing the trade offers.
--
-- @return bool Whether the first offer should be placed before the second offer.
--
function m.compareOffers(a, b, sortParameters)
    for _, parameter in ipairs(sortParameters) do
        if a[parameter.property] ~= b[parameter.property] then
            if parameter.ascending then
                return a[parameter.property] < b[parameter.property]
            else
                return a[parameter.property] > b[parameter.property]
            end
        end
    end

    return false
end


--- Generates full list of sort parameters, starting with passed-in parameters and continuing with remaining unused default sort parameters.
--
-- @param parameters [{ property = string, ascending = bool }] List of preferred sort parameters.
--
-- @return [{ property = string, ascending = bool }] Full list of sort parameters.
--
function m.generateFullSortParameters(parameters)
    local fullParameters = {}

    local seen = {}
    for _, parameter in ipairs(parameters) do
        table.insert(fullParameters, { property = parameter.property, ascending = parameter.ascending })
        seen[parameter.property] = true
        -- @NOTE: Use (hidden) real distance ordering to ensure consistent grouping of stations by sector when ordering by distance.
        if parameter.property == "distance" then
            table.insert(fullParameters, { property = "realDistance", ascending = parameter.ascending })
        end
    end

    for _, parameter in ipairs(m.config.defaultSortParameters) do
        if not seen[parameter.property] then
            table.insert(fullParameters, { property = parameter.property, ascending = parameter.ascending })
        end
    end

    return fullParameters
end


--- Calculates required column width to fit either title or data, taking into the account sorting indiactor as well.
--
-- @param title string Column title.
-- @param data string Sample data of maximum length that can end up in the column.
--
-- @return number Column width that can accomodate title with sorting indicator or data.
--
function m.calculateRequiredColumnTextWidth(title, data)
    local sortIndicator = "⁹\27[widget_arrow_down_01]"

    local titleWidth = C.GetTextWidth(title, Helper.standardFont, Helper.standardFontSize)
    local dataWidth = C.GetTextWidth(data, Helper.standardFont, Helper.standardFontSize)
    local sortIndicatorWidth = C.GetTextWidth(sortIndicator, Helper.standardFont, Helper.standardFontSize)

    local maximumWidth = math.max(titleWidth + sortIndicatorWidth, dataWidth) + Helper.standardTextOffsetx

    return maximumWidth
end


--- Creates context menu for picking multiple values.
--
-- @param x number Horisontal position where the menu should be shown (top-left corner).
-- @param y number Vertical position where the menu should be shown (top-left corner).
-- @param width number Total menu width.
-- @param title string Menu title to show in menu header.
-- @param options [{ id = any, text = string, state = bool }] List of options to show.
-- @param callback function([{id = any, state = bool}], append = bool) Callback function invoked when options change state.
--
function m.createMultiValuePicker(x, y, width, title, options, callback)
    local allOptionsEnabled = true
    for _, option in ipairs(options) do
        if not option.state then
            allOptionsEnabled = false
            break
        end
    end

    local frame = Helper.createFrameHandle(
        m.menu,
        {
            x = x,
            y = y,
            width = width,
            height = Helper.viewHeight - y - Helper.frameBorder,
            layer = m.menuConfig.contextFrameLayer,
            standardButtons = { close = true },
            closeOnUnhandledClick = true,
        }
    )
    local ftable = frame:addTable(
        2,
        {
            tabOrder = 1,
            highlightMode = "off",
            backgroundID = "solid",
            backgroundColor = Color["frame_background_black"],
            reserveScrollBar = false,
            x = Helper.borderSize,
            y = Helper.borderSize,
        }
    )

    ftable:setColWidth(1, m.menuConfig.mapRowHeight)

    local row = ftable:addRow(true, { fixed = true })
    row[1]:createCheckBox(allOptionsEnabled, { height = m.menuConfig.mapRowHeight })
    row[1].handlers.onClick = function(_, state)
        local changes = {}
        for _, checkboxRow in ipairs(ftable.rows) do
            C.SetCheckBoxChecked2(checkboxRow[1].id, state, true)
            if checkboxRow.rowdata and checkboxRow.rowdata ~= true then
                table.insert(changes, {id = checkboxRow.rowdata, state = state})
            end
        end
        callback(changes)
    end
    row[2]:createText(title, Helper.headerRowCenteredProperties)

    for _, option in ipairs(options) do
        row = ftable:addRow(option.id)
        row[1]:createCheckBox(option.state, { height = Helper.standardTextHeight, width = Helper.standardTextHeight })
        row[1].handlers.onClick = function(_, state) callback({{id = option.id, state = state}}, true) end
        row[2]:createText(option.text)
    end

    m.menu.contextMenuMode = "marketanalytics-multivaluepicker"
    m.menu.contextFrame = frame
    m.menu.contextFrame:display()
end


--- Creates context menu for picking a single option.
--
-- @param x number Horisontal position where the menu should be shown (top-left corner).
-- @param y number Vertical position where the menu should be shown (top-left corner).
-- @param width number Total menu width.
-- @param title string Menu title to show in menu header.
-- @param options [{ id = string, text = string, state = bool }] List of possible options. State can be used to denote currently active option(s).
-- @param callback function(id = string) Callback function to invoke on selection.
--
function m.createValuePicker(x, y, width, title, options, callback)
    local frame = Helper.createFrameHandle(
        m.menu,
        {
            x = x,
            y = y,
            width = width,
            height = Helper.viewHeight - y - Helper.frameBorder,
            layer = m.menuConfig.contextFrameLayer,
            standardButtons = { close = true },
            closeOnUnhandledClick = true,
        }
    )
    local ftable = frame:addTable(
        1,
        {
            tabOrder = 1,
            highlightMode = "off",
            backgroundID = "solid",
            backgroundColor = Color["frame_background_black"],
            reserveScrollBar = false,
            x = Helper.borderSize,
            y = Helper.borderSize,
        }
    )

    local row = ftable:addRow(true, { fixed = true })
    row[1]:createText(title, Helper.headerRowCenteredProperties)

    for _, option in ipairs(options) do
        row = ftable:addRow(true, { fixed = true })
        row[1]:createButton({ bgColor = option.state and Color["button_highlight_default"] or Color["button_background_default"] })
        row[1]:setText(option.text, { halign = "center" })
        row[1].handlers.onClick = function()
            callback(option.id)
            m.menu.closeContextMenu()
        end
    end

    m.menu.contextMenuMode = "marketanalytics-valuepicker"
    m.menu.contextFrame = frame
    m.menu.contextFrame:display()
end


--- Sets the trade offers factions filter.
--
-- @param settings [{id = string, state = bool}] List of settings to apply.
-- @param append bool Append to existing settings instead of replacing them.
--
function m.setFactionFilter(settings, append)
    if not append then
        m.state.filters.factions = {}
    end

    if append and next(m.state.filters.factions) == nil then
        local allNegative = true
        for _, setting in ipairs(settings) do
            if setting.state then
                allNegative = false
                break
            end
        end
        if allNegative then
            for _, faction in pairs(m.cache.factions) do
                m.state.filters.factions[faction.id] = true
            end
        end
    end

    for _, setting in ipairs(settings) do
        m.state.filters.factions[setting.id] = setting.state or nil
    end

    m.updateOffers(m.state.pageSize, false, true, true)
    m.menu.refreshInfoFrame2()
end


--- Sets the trade offers ware filter.
--
-- Ware filter changes are tracked and synced via map menu.
--
-- @param settings [{id = string, state = bool}]|nil List of settings to apply. Clears the filter if nil.
-- @param append bool Append to existing settings instead of replacing them.
--
function m.setWareFilter(settings, append)
    local mapFilterSetting, mapFilterWares = m.menu.getTradeWareFilter(true)
    local enabledWares = {}

    if not append then
        -- @NOTE: Workaround for setFilterOption closing context menu when passing-in multiple wares
        --
        --     Vanilla code closes the context menu if the setFilterOption function is invoked by passing-in a { wareid = _ } table. In context of this mod,
        --     this can end up with the multi-value picker context menu getting closed even when it should remain open, so just "suppress" the closeContextMenu
        --     function invocation by temporarily turning it into a no-op.
        --
        --     There is a couple of alternatives to this, but this one might be the least troublesome hack (opinions may change). One way is to set the wares
        --     one-by-one, but this creates a noticable delay/stutter in UI when a lot of wares are affected by the change. Second option is operating directly
        --     on the __CORE_DETAILMONITOR_MAPFILTER_SAVE["trade_wares"] table and invoking the mapFilterSetting.callback(mapFilterSetting), but that
        --     circumvents the main interface for changing filter options which feels less maintainable over the long run.
        --
        --     On another note, it looks like the table handling in vanilla's setFilterOption is specifically hard-coded for use with wares. Nice work,
        --     Egosoft. :P
        local originalCloseContextMenu = m.menu.closeContextMenu
        m.menu.closeContextMenu = function() end
        -- @NOTE: The passed-in {} table is not meant to be a _list_, but a dictionary where keys are enabled ware IDs (dictionary values do not matter).
        m.menu.setFilterOption("layer_trade", mapFilterSetting, mapFilterSetting.id, {})
        m.menu.closeContextMenu = originalCloseContextMenu
    else
        for _, ware in ipairs(mapFilterWares) do
            enabledWares[ware] = true
        end
    end

    if append and #mapFilterWares == 0 then
        local allNegative = true
        for _, setting in ipairs(settings) do
            if setting.state then
                allNegative = false
                break
            end
        end
        if allNegative then
            for _, ware in pairs(m.menu.economyWares) do
                enabledWares[ware] = true
            end
        end
    end

    for _, setting in ipairs(settings) do
        enabledWares[setting.id] = setting.state or nil
    end

    local originalCloseContextMenu = m.menu.closeContextMenu
    m.menu.closeContextMenu = function() end
    m.menu.setFilterOption("layer_trade", mapFilterSetting, mapFilterSetting.id, enabledWares)
    m.menu.closeContextMenu = originalCloseContextMenu

    m.updateOffers(m.state.pageSize, false, true, true)
    m.menu.refreshMainFrame = true
end


--- Generates trade volume threshold information for passed-in volume.
--
-- May return nil if the passed-in volume is no longer valid.
--
-- @param volume number|nil Trade volume for which to get information. If nil, returns the currently set trade volume info.
--
-- @return { name = string, text = string, mouseOverText = string, nextVolume = number }|nil Trade volume information/representation.
--
function m.getTradeVolumeInfo(volume)
    if volume == nil then
        volume = m.menu.getFilterOption("trade_volume", m.menuConfig.layersettings.layer_trade[4].savegame)
    end

    if not m.cache.volumeInfo[volume] then
        m.updateCache("volumeInfo")
    end

    return m.cache.volumeInfo[volume] or nil
end


--- Retrieves the volume of a single unit of requested ware.
--
-- @param ware string Ware name.
--
-- @return number Ware volume.
--
function m.getWareVolume(ware)
    if not m.cache.wareVolume[ware] then
        m.updateCache("wareVolume")
    end

    return m.cache.wareVolume[ware]
end


--- Generates sector filter options based on current sector filter state.
--
function m.generateSectorFilterOptions()
    local options = {}
    local filteredSectors = __CORE_DETAILMONITOR_MAPFILTER_SAVE["searchsectors"]

    for name, sector in pairs(m.cache.sectors) do
        local state = false
        for _, filteredSector in ipairs(filteredSectors) do
            if tostring(sector) == filteredSector then
                state = true
                break
            end
        end
        table.insert(options, { id = sector, text = name, state = state })
    end

    return options
end


--- Sets the trade offers sector filter.
--
-- Sector filter changes are tracked and synced via map menu.
--
-- @param settings [{id = component<sector>, state = bool}]|nil List of settings to apply. Clears the filter if nil.
-- @param append bool Append to existing settings instead of replacing them.
--
function m.setSectorFilter(settings, append)
    if not append then
        __CORE_DETAILMONITOR_MAPFILTER_SAVE["searchsectors"] = {}
    end

    if append and #__CORE_DETAILMONITOR_MAPFILTER_SAVE["searchsectors"] == 0 then
        local allNegative = true
        for _, setting in ipairs(settings) do
            if setting.state then
                allNegative = false
                break
            end
        end
        if allNegative then
            for _, sector in pairs(m.cache.sectors) do
                table.insert(__CORE_DETAILMONITOR_MAPFILTER_SAVE["searchsectors"], tostring(sector))
            end
        end
    end

    for _, setting in ipairs(settings) do
        local found = false
        for i, filteredSector in ipairs(__CORE_DETAILMONITOR_MAPFILTER_SAVE["searchsectors"]) do
            if tostring(setting.id) == filteredSector then
                found = i
                break
            end
        end

        if setting.state and not found then
            table.insert(__CORE_DETAILMONITOR_MAPFILTER_SAVE["searchsectors"], tostring(setting.id))
        elseif not setting.state and found then
            table.remove(__CORE_DETAILMONITOR_MAPFILTER_SAVE["searchsectors"], found)
        end
    end

    m.menu.setSectorFilter()
    m.updateOffers(m.state.pageSize, false, true, true)
    m.menu.refreshMainFrame = true
end


--- Updates miscellaneous cached data.
--
-- Trade offers are _explicitly_ and _purposefully_ not covered by this function.
--
-- @param cache string|nil Name of cache to update. If nil, all caches will be updated instead.
--
function m.updateCache(cache)
    if cache == "factions" or cache == nil then
        m.cache.factions = {}
        local factions = GetLibrary("factions")
        for _, faction in ipairs(factions) do
            faction.isenemy, faction.color = GetFactionData(faction.id, "isenemy", "color")
            m.cache.factions[faction.id] = faction
        end
    end

    -- @NOTE: Requires the game to finish loading.
    if cache == "volumeInfo" or cache == nil then
        local volumeParameter = C.GetMapTradeVolumeParameter()
        local volumeIcon = string.format("\27[%s]", ffi.string(volumeParameter.icon))
        local volumeColorActive = Helper.convertColorToText({
            r = volumeParameter.color.red,
            g = volumeParameter.color.green,
            b = volumeParameter.color.blue,
            a = volumeParameter.color.alpha
        })
        local volumeColorInactive = Helper.convertColorToText(Color["text_inactive"])

        m.cache.volumeInfo = {
            [0] = {
                name = "none",
                text = string.format("%s%s%s%s", volumeColorInactive, string.rep(volumeIcon, 3), volumeColorActive, string.rep(volumeIcon, 0)),
                mouseOverText = string.format("%s: %s", ReadText(1001, 8357), ReadText(1001, 8359)),
                volume = 0,
                nextVolume = volumeParameter.volume_s,
            },
            [volumeParameter.volume_s] = {
                name = "small",
                text = string.format("%s%s%s%s", volumeColorInactive, string.rep(volumeIcon, 2), volumeColorActive, string.rep(volumeIcon, 1)),
                mouseOverText = string.format("%s: %s", ReadText(1001, 8357), ReadText(1001, 2853)),
                volume = volumeParameter.volume_s,
                nextVolume = volumeParameter.volume_m,
            },
            [volumeParameter.volume_m] = {
                name = "medium",
                text = string.format("%s%s%s%s", volumeColorInactive, string.rep(volumeIcon, 1), volumeColorActive, string.rep(volumeIcon, 2)),
                mouseOverText = string.format("%s: %s", ReadText(1001, 8357), ReadText(1001, 2854)),
                volume = volumeParameter.volume_m,
                nextVolume = volumeParameter.volume_l,
            },
            [volumeParameter.volume_l] = {
                name = "large",
                text = string.format("%s%s%s%s", volumeColorInactive, string.rep(volumeIcon, 0), volumeColorActive, string.rep(volumeIcon, 3)),
                mouseOverText = string.format("%s: %s", ReadText(1001, 8357), ReadText(1001, 2855)),
                volume = volumeParameter.volume_l,
                nextVolume = 0,
            },
        }
    end

    -- @NOTE: Requires the game to finish loading.
    if cache == "wareVolume" or cache == nil then
        m.menu.prepareEconomyWares()
        m.cache.wareVolume = {}
        for _, ware in pairs(m.menu.economyWares) do
            m.cache.wareVolume[ware] = GetWareData(ware, "volume")
        end
    end

    -- @NOTE: Requires the game to finish loading (probably).
    if cache == "sectors" or cache == nil then
        m.cache.sectors = {}
        local clusters = GetClusters(true) or {}
        for _, cluster in ipairs(clusters) do
            local sectors = GetSectors(cluster)
            for _, sector in ipairs(sectors) do
                local name = GetComponentData(sector, "name")
                m.cache.sectors[name] = sector
            end
        end
    end
end


--- Sets the reference sector for calculating trade offer distances.
--
-- @param sector component<sector> Sector to set as reference.
--
function m.setReferenceSector(sector)
    m.state.referenceSector = sector
    m.updateOffers(m.state.pageSize, true, false, false)
    m.menu.refreshInfoFrame2()
end


--- Sets the maximum jump distance filter.
--
-- @param distance number|nil Distance in jumps. nil resets the filter to default value.
--
function m.setMaxDistanceFilter(distance)
    if not distance then
        m.state.filters.maxDistance = m.config.maxDistanceFilterLimit
    else
        m.state.filters.maxDistance = distance
    end

    m.updateOffers(m.state.pageSize, false, true, true)
    m.menu.refreshInfoFrame2()
end


--- Sets the offer type filter.
--
-- @param type_ enum.offertype|nil Offer type. nil resets the filter to default value.
--
function m.setTypeFilter(type_)
    m.state.filters.type = type_ or 0

    m.updateOffers(m.state.pageSize, false, true, true)
    m.menu.refreshInfoFrame2()
end


--- Sets the trade volume filter.
--
-- @param volume number|nil Trade volume to set the filter to. nil resets the filter to default value.
--
function m.setTradeVolumeFilter(volume)
    local setting = m.menuConfig.layersettings.layer_trade[4]
    m.menu.setFilterOption("layer_trade", setting, "trade_volume", volume or 0)

    m.updateOffers(m.state.pageSize, false, true, true)
    m.menu.refreshMainFrame = true
end


--- Resets all filters and sorting.
--
function m.resetAllControls()
    m.setFactionFilter({})
    m.setSectorFilter({})
    m.setMaxDistanceFilter()
    m.setWareFilter({})
    m.setTypeFilter()
    m.setTradeVolumeFilter()

    m.state.sortParameters = { { property = "factionName", ascending = true } }
    -- Make parameters accessible by sort property.
    -- @NOTE: Keep this snippet in sync with other occurance or deduplicate this code.
    m.state.sortParametersBy = {}
    for priority, parameter in ipairs(m.state.sortParameters) do
        -- Do not show column sorting priority when sorting by a singular player-selected column.
        if #m.state.sortParameters > 1 then
            parameter.priority = priority
        else
            parameter.priority = nil
        end
        m.state.sortParametersBy[parameter.property] = parameter
    end

    local playerSector = C.GetContextByClass(C.GetPlayerID(), "sector", false)
    m.setReferenceSector(ConvertStringToLuaID(tostring(playerSector)))

    m.state.currentPage = 1

    m.updateOffers(m.state.pageSize, false, false, false)
    m.menu.refreshInfoFrame2()
end


--- Truncates text to specified width, taking scaling into the account.
--
-- Useful for generating mouse-over text for buttons.
--
-- @param text string Text to truncate.
-- @param width number Maximum width the text should fit.
-- @param font string|nil Font used for width calculatioins. Defaults to Helper.standardFont.
-- @param fontSize string|nil Font size used for calculations. Defaults to Helper.standardFontSize.
--
-- @return (string, string) Truncated text and full text if text was truncated.
--
function m.truncateText(text, width, font, fontSize)
    font = font or Helper.standardFont
    fontSize = fontSize or Helper.standardFontSize

    fontSize = Helper.scaleFont(font, fontSize)
    local truncatedText = TruncateText(text, font, fontSize, width)

    return truncatedText, text ~= truncatedText and text or nil
end


-- Trade offer filters
-- ===================


--- Filters offer by sectors selected in the map menu.
--
-- @param offer {*} Offer to check.
--
-- @return bool true if the offer satisfies the filter, false otherwise.
--
function m.filter.mapSearchSectors(offer)
    local sectors = __CORE_DETAILMONITOR_MAPFILTER_SAVE["searchsectors"] or {}

    if #sectors == 0 then
        return true
    end

    for _, sector in ipairs(sectors) do
        if tostring(offer.sector) == sector then
            return true
        end
    end

    return false
end


--- Filters offer by wares selected in the map menu.
--
-- @param offer {*} Offer to check.
--
-- @return bool true if the offer satisfies the filter, false otherwise.
--
function m.filter.mapSearchWares(offer)
    local _, wares = m.menu.getTradeWareFilter(true)

    if #wares == 0 then
        return true
    end

    for _, ware in ipairs(wares) do
        if offer.ware == ware then
            return true
        end
    end

    return false
end


--- Filters offers by player-selected factions.
--
-- @param offer {*} Offer to check.
--
-- @return bool true if the offer satisfies the filter, false otherwise.
--
function m.filter.factions(offer)
    return next(m.state.filters.factions) == nil and true or not not m.state.filters.factions[offer.faction]
end


--- Generates textual representation for the passed-in filter based on current filter state.
--
-- @param filter function Filter function for which to generate status text.
--
-- @return string Textual representation of filter's current state.
--
function m.getFilterText(filter)
    local text = "err-nofiltermatch"

    if filter == m.filter.factions then
        if not next(m.state.filters.factions) then
            text = "Any"
        else
            local icons = {}
            for faction, _ in pairs(m.state.filters.factions) do
                local icon = m.cache.factions[faction].icon
                local color = m.cache.factions[faction].color
                table.insert(icons, string.format("%s\27[%s]", Helper.convertColorToText(color), icon))
            end
            table.sort(icons)

            text = table.concat(icons, "")

            if C.GetTextWidth(text, Helper.standardFont, Helper.standardFontSize) > m.config.wareColumns[1].width then
                text = string.format("\27[mapst_factionrelation] (%s)", #icons)
            end
        end

    elseif filter == m.filter.mapTradeVolume then
        local volumeInfo = m.getTradeVolumeInfo() or m.getTradeVolumeInfo(0)
        text = volumeInfo.text

    elseif filter == m.filter.mapSearchWares then
        local _, wares = m.menu.getTradeWareFilter(true)
        local names = {}
        for _, ware in ipairs(wares) do
            table.insert(names, GetWareData(ware, "name"))
        end
        table.sort(names)
        text = #names > 0 and table.concat(names, ", ") or "Any"

    elseif filter == m.filter.mapSearchSectors then
        local sectors = __CORE_DETAILMONITOR_MAPFILTER_SAVE["searchsectors"]
        local names = {}
        for _, sector in ipairs(sectors) do
            table.insert(names, GetComponentData(ConvertStringToLuaID(sector), "name"))
        end
        table.sort(names)
        text = #names > 0 and table.concat(names, ", ") or "Any"

    end

    return text
end


--- Filters offers by distance (jump gate/accelerator/super-highway) range.
--
-- @param offer {*} Offer to check.
--
-- @return bool true if the offer satisfies the filter, false otherwise.
--
function m.filter.distance(offer)
    return offer.distance >= m.state.filters.minDistance and offer.distance <= m.state.filters.maxDistance
end


--- Filters offers by offer type.
--
-- @param offer {*} Offer to check.
--
-- @return bool true if the offer satisfies the filter, false otherwise.
--
function m.filter.type(offer)
    if m.state.filters.type == enum.offertype.any then
        return true
    end

    return offer.type == m.state.filters.type
end


--- Filters offer by minimum trade offer volume selected in the map menu.
--
-- @param offer {*} Offer to check.
--
-- @return bool true if the offer satisfies the filter, false otherwise.
--
function m.filter.mapTradeVolume(offer)
    local volumeInfo = m.getTradeVolumeInfo()

    return offer.amount * m.getWareVolume(offer.ware) >= volumeInfo.volume
end


--- Filters offer by map trade relation (show enemy trades option).
--
-- @param offer {*} Offer to check.
--
-- @return bool true if the offer satisfies the filter, false otherwise.
--
function m.filter.mapRelation(offer)
    local showEnemyOffers = m.menu.getFilterOption("trade_relation_enemy", m.menuConfig.layersettings.layer_trade[6].savegame)

    return showEnemyOffers and true or not m.cache.factions[offer.faction].isenemy
end


-- Override functions
-- ==================


--- Update offers and redraw the market analytics when player changes the map menu sector filters.
--
function m.override.setSectorFilter(...)
    m.original.setSectorFilter(...)
    if m.state.filteredOffers then
        m.updateOffers(m.state.pageSize, false, true, true)
    end
    if m.menu.searchTableMode == "marketanalytics" then
        m.menu.refreshInfoFrame2()
    end
end


--- Update offers and redraw the market analytics when player changes the map menu trade ware filters.
--
function m.override.filterTradeWares(...)
    m.original.filterTradeWares(...)
    if m.state.filteredOffers then
        m.updateOffers(m.state.pageSize, false, true, true)
    end
    if m.menu.searchTableMode == "marketanalytics" then
        m.menu.refreshInfoFrame2()
    end
end


--- Update offers and redraw the market analytics when player changes the map menu trade relations filter (show enemy trades).
--
function m.override.filterTradeRelation(...)
    m.original.filterTradeRelation(...)
    if m.state.filteredOffers then
        m.updateOffers(m.state.pageSize, false, true, true)
    end
    if m.menu.searchTableMode == "marketanalytics" then
        m.menu.refreshInfoFrame2()
    end
end


--- Update offers and redraw the market analytics when player changes the map menu trade volume filters.
--
function m.override.filterTradeVolume(...)
    m.original.filterTradeVolume(...)
    if m.state.filteredOffers then
        m.updateOffers(m.state.pageSize, false, true, true)
    end
    if m.menu.searchTableMode == "marketanalytics" then
        m.menu.refreshInfoFrame2()
    end
end


m.init()
