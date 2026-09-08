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
            title = "\27[mapst_factionrelation]",
            dataSample = "\27[faction_argon]\27[faction_argon]\27[faction_argon]",
            sortProperty = "factionText",
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
            sortProperty = "markup",
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
        { property = "factionText", ascending = true },
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

    m.state = {
        currentPage = 1,
        sortParameters = { { property = "factionText", ascending = true } },
        filters = {
            factions = {},
            -- @TODO: Currently not changeable by player, but maybe think about adding support for it in the future.
            minDistance = 0,
            maxDistance = m.config.maxDistanceFilterLimit,
            type = 0,
        },
    }

    -- @TODO: Candidate for deduplicatioin or simplification
    --     This pattern is used in a couple of different places in the code, and it might be useful to deduplicate it. Another thing that could be considered is
    --     getting rid of this mapping altogether and just using iteration over m.state.sortParameters if performance hit is minimal.
    -- Make parameters accessible by referencing the property, thus avoiding having to traverse the list all the time.
    m.state.sortParametersBy = {}
    for priority, parameter in ipairs(m.state.sortParameters) do
        -- Do not show column sorting priority when sorting by a singular player-selected column.
        if #m.state.sortParameters > 1 then
            parameter.priority = priority
        end
        m.state.sortParametersBy[parameter.property] = parameter
    end

    -- Keep track of widgets that might require updates after their creation.
    m.widgets = {}

    for _, column in ipairs(m.config.wareColumns) do
        column.width = column.fixedWidth and m.calculateRequiredColumnTextWidth(column.title, column.dataSample) or nil
    end

    -- Keep track of how much volume different wares take up per unit.
    m.menu.prepareEconomyWares()
    m.state.wareVolume = {}
    for _, ware in pairs(m.menu.economyWares) do
        m.state.wareVolume[ware] = GetWareData(ware, "volume")
    end

    m.menu.registerCallback("createRightBar_on_start", m.registerRightBar)
    m.menu.registerCallback("createInfoFrame2_on_menu_infoModeRight", m.createMenu)

    -- Store references to original functions.
    m.original.setSectorFilter = m.menu.setSectorFilter
    m.original.filterTradeWares = m.menu.filterTradeWares

    -- Override original functions with custom implementation.
    m.menu.setSectorFilter = m.override.setSectorFilter
    m.menu.filterTradeWares = m.override.filterTradeWares
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
    local height = Helper.viewHeight - leftPadding - rightPadding

    local frame = Helper.createFrameHandle(
        m.menu,
        {
            x = leftPadding,
            y = topPadding,
            width = Helper.viewWidth - leftPadding - rightPadding,
            height = Helper.viewHeight - topPadding - bottomPadding,
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

    row[12]:createText(" ", { y = Helper.scaleY((Helper.standardButtonHeight - Helper.standardTextHeight) / 2), halign = "center" })
    m.widgets.offersAge = row[12]

    row[13]:createButton():setText("Refresh", { halign = "center" })
    row[13].handlers.onClick = function()
        m.updateOffers(m.state.pageSize, true, false, false)
        m.menu.refreshInfoFrame2()
    end


    -- Pagination controls
    -- ===================
    local row = ftable:addRow(true, { fixed = true })

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
    row[12].handlers.onEditBoxDeactivated = function(_, text, textChanged)
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
    row[1].handlers.onClick = function()
        local factions = GetLibrary("factions")
        local options = {}
        for _, faction in ipairs(factions) do
            if faction.id ~= "player" then
                table.insert(options, { id = faction.id, text = faction.name, state = m.state.filters.factions[faction.id] })
            end
        end

        -- @TODO: This sorts by the faction icon instead of the name, which may not be expected by the player.
        table.sort(options, function(a, b) return a.text < b.text end)

        -- @TODO: May get nil when using joystick mode.
        local x, y = GetLocalMousePosition()
        x = x + Helper.viewWidth / 2
        y = Helper.viewHeight / 2 - y
        m.createMultiValuePicker(x, y, 280, "Select Factions", options, m.setFactionFilter)
    end

    -- Distance filter
    local options = {}
    for range = 0, m.config.maxDistanceFilterLimit do
        -- Extra whitespace at end of text helps align the text with text in data rows.
        table.insert(options, { id = tostring(range), text = tostring(range) .. "j ", icon = "", displayremoveoption = false, align = "right" })
    end

    row[4]:createDropDown(
        options,
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
        m.state.filters.maxDistance = tonumber(id)
        m.updateOffers(m.state.pageSize, false, true, true)
        m.menu.refreshInfoFrame2()
    end

    -- Ware filter
    local filterText = m.getFilterText(m.filter.mapSearchWares)
    row[5]:createButton({bgColor = Color["row_background"]}):setText(filterText, { color = Color["text_normal"] })
    row[5].handlers.onClick = function()
        local options = {}
        local setting, filteredWares = m.menu.getTradeWareFilter(true)
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

        table.sort(options, function(a, b) return a.text < b.text end)
        local x, y = GetLocalMousePosition()
        x = x + Helper.viewWidth / 2
        y = Helper.viewHeight / 2 - y
        m.createMultiValuePicker(x, y, 280, "Select Wares", options, m.setWareFilter)
    end

    -- Offer type filter
    local options = {
        -- @NOTE: ID 0 does _not_ correspond to offer.type == 0 (offer.type == 0 is _probably_ not possible).
        { id = "0", text = "All", icon = "", displayremoveoption = false},
        { id = "1", text = "Buys", icon = "", displayremoveoption = false},
        { id = "2", text = "Sells", icon = "", displayremoveoption = false},
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
        m.state.filters.type = tonumber(id)
        m.updateOffers(m.state.pageSize, false, true, true)
        m.menu.refreshInfoFrame2()
    end

    -- Amount filter by volume
    row[9]:createButton({bgColor = Color["row_background"]}):setText(filterText, { color = Color["text_normal"] })
    row[9]:setText(m.getFilterText(m.filter.mapTradeVolume), { halign = "right" })
    row[9].handlers.onClick = function()
        local setting = m.menuConfig.layersettings.layer_trade[4]
        local currentVolume = m.menu.getFilterOption("trade_volume", setting.savegame)
        local currentVolumeInfo = m.getTradeVolumeInfo(currentVolume) or m.getTradeVolumeInfo(0)
        local nextVolume = currentVolumeInfo.nextVolume

        m.menu.setFilterOption("layer_trade", setting, "trade_volume", nextVolume)
        m.updateOffers(m.state.pageSize, false, true, true)
	m.menu.refreshMainFrame = true
    end
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
                parameter = { property = column.sortProperty, ascending = true }
                table.insert(m.state.sortParameters, parameter)
            end

            -- @TODO: Candidate for deduplication or simplification.
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
    local row = ftable:addRow(false)
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
        row[1]:createText(offer.factionText)
        row[2]:createText(offer.stationText)
        row[3]:createText(offer.sectorText)
        row[4]:createText(offer.distanceText, { halign = "right" })
        row[5]:createText(offer.wareText)
        row[6]:createText(offer.typeText)
        row[7]:createText(offer.priceText, { halign = "right" })
        row[8]:createText(offer.markupText, { halign = "right" })
        row[9]:createText(offer.amountText, { halign = "right" })
    end
end


--- Returns list of all active trade offers known to player, including various metadata or text rendering.
--
-- @return [table{faction = component<faction>, factionText = string, station = component<station>, stationText = string,
--     sector = component<sector>, sectorText = string, distance = number, distanceText = string, ware = component<ware>, wareText = string,
--     type = 1|2|nil, typeText = string, price = number, priceText = string, markup = number, markupText = string,
--     amount = number, amountText = string}]  List of active trade offers.
--
function m.getTradeOffers()
    local offers = {}
    local currencySuffix = " " .. ReadText(1001, 101)

    local clusters = GetClusters(true) or {}
    for _, cluster in ipairs(clusters) do
        local sectors = GetSectors(cluster)
        for _, sector in ipairs(sectors) do
            local stations = GetContainedStations(sector, true) or {}
            local sectorName = GetComponentData(sector, "name")
            local playerSector = C.GetContextByClass(C.GetPlayerID(), "sector", false)
            local jumpDistance = FindJumpRoute(ConvertStringTo64Bit(tostring(playerSector)), sector)
            for _, station in ipairs(stations) do
                local trades = GetTradeList(station) or {}
                local stationOwner = GetComponentData(station, "owner")
                local stationOwnerIcon = GetFactionData(stationOwner, "icon")
                for _, trade in ipairs(trades) do
                    local averagePrice = GetWareData(trade.ware, "avgprice")
                    local markup = 1 - trade.price/averagePrice
                    table.insert(
                        offers,
                        {
                            faction = stationOwner,
                            -- @TODO: Consider using dedicated factionIcon property in order to be able to sort by actual faction name.
                            factionText = string.format("\27[%s]", stationOwnerIcon),
                            station = trade.station,
                            stationText = trade.stationname,
                            sector = sector,
                            sectorText = sectorName,
                            distance = jumpDistance,
                            distanceText = tostring(jumpDistance) .. "j",
                            ware = trade.ware,
                            wareText = trade.name,
                            type = trade.isbuyoffer and 1 or trade.isselloffer and 2 or nil,
                            typeText = trade.isbuyoffer and "Buys" or trade.isselloffer and "Sells" or "None",
                            price = trade.price,
                            -- Arguments: price, includeFraction, includeComma, ?, ?
                            priceText = ConvertMoneyString(trade.price, true, true, 0, true) .. currencySuffix,
                            markup = markup,
                            markupText = string.format("%.2f%%", markup * 100),
                            amount = trade.amount,
                            amountText = tostring(trade.amount),
                        }
                    )
                end
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
    m.widgets.offersAge.properties.text = Helper.getPassedTime(m.state.offersAge)
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
-- @param options [{ id = string, text = string, state = bool }] List of options to show.
-- @param callback function(id = string, state = bool) Callback function to call anytime a checkbox is ticked by the player.
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
            x = offsetX,
            y = offsetY,
        }
    )

    ftable:setColWidth(1, m.menuConfig.mapRowHeight)

    local row = ftable:addRow(true, { fixed = true })
    row[1]:createCheckBox(allOptionsEnabled, { height = m.menuConfig.mapRowHeight })
    row[1].handlers.onClick = function(_, state)
        for _, row in ipairs(ftable.rows) do
            C.SetCheckBoxChecked2(row[1].id, state, true)
        end
        callback(nil, state, options)
    end
    row[2]:createText(title, Helper.headerRowCenteredProperties)

    for _, option in ipairs(options) do
        local row = ftable:addRow(true)
        row[1]:createCheckBox(option.state, { height = Helper.standardTextHeight, width = Helper.standardTextHeight })
        row[1].handlers.onClick = function(_, state) callback(option.id, state) end
        row[2]:createText(option.text)
    end

    m.menu.contextMenuMode = "marketanalytics-multivaluepicker"
    m.menu.contextFrame = frame
    m.menu.contextFrame:display()
end


--- Sets filter for trade offers based on factions.
--
-- @param id string|nil Faction identifier (as returned by GetLibrary("factions")). If nil, state is applied against all factions defined via passed-in options.
-- @param state bool Whether trade offers belonging to this faction should be shown or not.
-- @param options [{id = string, text = string, state = bool}] Complete list of possible faction options
--
function m.setFactionFilter(id, state, options)
    if id then
        m.state.filters.factions[id] = state or nil
    elseif state then
        for _, option in ipairs(options) do
            m.state.filters.factions[option.id] = state
        end
    else
        -- Clear factions filter.
        m.state.filters.factions = {}
    end

    m.updateOffers(m.state.pageSize, false, true, true)
    m.menu.refreshInfoFrame2()
end


--- Sets filter for trade offers based on wares filtered via map menu.
--
-- Syncs the changes into map search.
--
-- @param id string|nil Ware identifier (as returned by GetLibrary("wares")). If nil, state is applied against all wares defined via passed-in options.
-- @param state bool Whether trade offers for this ware should be shown or not.
-- @param options [{id = string, text = string, state = bool}] Complete list of possible ware options.
--
function m.setWareFilter(id, state, options)
    local wares = id and {{id = id}} or options
    local setting, mapFilteredWares = m.menu.getTradeWareFilter(true)

    for _, ware in ipairs(wares) do
        local found = false
        for i, filteredWare in ipairs(mapFilteredWares) do
            if ware.id == filteredWare then
                found = i
                break
            end
        end

        if state and not found then
            m.menu.setFilterOption("layer_trade", setting, setting.id, ware.id)
        elseif not state and found then
            m.menu.removeFilterOption(setting, setting.id, found)
        end
    end

    m.updateOffers(m.state.pageSize, false, true, true)
    m.menu.refreshMainFrame = true
end


--- Generates trade volume threshold information for passed-in volume.
--
-- May return nil if the passed-in volume is no longer valid.
--
-- @param volume number Trade volume for which to get information.
--
-- @return { name = string, text = string, mouseOverText = string, nextVolume = number }|nil Trade volume information/representation.
--
function m.getTradeVolumeInfo(volume)
    m.state.volumeInfoCache = m.state.volumeInfo or {}
    local volumeInfo = m.state.volumeInfoCache[volume]

    -- Invalidate the cache.
    -- @NOTE: Why the hell can this change over time?
    --     Initial attempts to cache the information during initialisation have failed - mainly because the returned threshold values seems to change once the
    --     game has fully loaded. Volume parameter probably depends on current state of explored/known universe and available trades or maybe available/visible
    --     ship sizes.
    if not volumeInfo then
        local volumeParameter = C.GetMapTradeVolumeParameter()
        local volumeIcon = string.format("\27[%s]", ffi.string(volumeParameter.icon))
        local volumeColorActive = Helper.convertColorToText({
            r = volumeParameter.color.red,
            g = volumeParameter.color.green,
            b = volumeParameter.color.blue,
            a = volumeParameter.color.alpha
        })
        local volumeColorInactive = Helper.convertColorToText(Color["text_inactive"])

        m.state.volumeInfoCache = {
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

    return m.state.volumeInfoCache[volume] or nil
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
    local setting, wares = m.menu.getTradeWareFilter(true)

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
            text = "\27[mapst_factionrelation]"
        else
            local icons = {}
            for faction, _ in pairs(m.state.filters.factions) do
                table.insert(icons, string.format("\27[faction_%s]", faction))
            end
            table.sort(icons)

            text = table.concat(icons, "")

            if C.GetTextWidth(text, Helper.standardFont, Helper.standardFontSize) > m.config.wareColumns[1].width then
                text = string.format("(%s)", #icons)
            end
        end

    elseif filter == m.filter.mapTradeVolume then
        local volume = m.menu.getFilterOption("trade_volume", m.menuConfig.layersettings.layer_trade[4].savegame)
        local volumeInfo = m.getTradeVolumeInfo(volume) or m.getTradeVolumeInfo(0)
        text = volumeInfo.text

    elseif filter == m.filter.mapSearchWares then
        local _, wares = m.menu.getTradeWareFilter(true)
        local names = {}
        for _, ware in ipairs(wares) do
            table.insert(names, GetWareData(ware, "name"))
        end

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
    if m.state.filters.type == 0 then
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
    local volume = m.menu.getFilterOption("trade_volume", m.menuConfig.layersettings.layer_trade[4].savegame)

    return offer.amount * m.state.wareVolume[offer.ware] >= volume
end


-- Override functions
-- ==================


--- Update offers and redraw the market analytics when player changes the map menu sector filters.
--
function m.override.setSectorFilter(...)
    m.original.setSectorFilter(...)
    if m.menu.searchTableMode == "marketanalytics" then
        m.updateOffers(m.state.pageSize, false, true, true)
        m.menu.refreshInfoFrame2()
    end
end


--- Update offers and redraw the market analytics when player changes the map menu trade ware filters.
--
function m.override.filterTradeWares(...)
    m.original.filterTradeWares(...)
    if m.menu.searchTableMode == "marketanalytics" then
        m.updateOffers(m.state.pageSize, false, true, true)
        m.menu.refreshInfoFrame2()
    end
end


m.init()
