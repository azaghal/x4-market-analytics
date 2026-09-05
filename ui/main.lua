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


--- Static configuration for the menu.
m.config = {
    -- Columns shown for the wares listings.
    wareColumns = {
        {
            id = "faction",
            index = 1,
            title = "\27[mapst_factionrelation]",
            dataSample = "\27[faction_argon]",
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
            sortProperty = "offerTypeText",
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
        { property = "offerTypeText", ascending = true },
        { property = "price", ascending = true },
        { property = "markup", ascending = true },
        { property = "amount", ascending = true },
    },

    -- @TODO: The fucking font implements superscript only for digits 1, 2, and 3
    --     (facepalm) Unbelievable... Find an alternative way to mark the order instead...
    -- Column indicators when sorting by player-indicated order.
    sortOrderIndicators = {"¹", "²", "³", "⁴", "⁵", "⁶", "⁷", "⁸", "⁹"}
}


--- Initialises the mod.
--
function m.init()
    m.menu = Helper.getMenu("MapMenu")
    m.menuConfig = m.menu.uix_getConfig()

    m.state = {
        currentPage = 1,
        sortParameters = { { property = "factionText", ascending = true } },
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

    m.menu.registerCallback("createRightBar_on_start", m.registerRightBar)
    m.menu.registerCallback("createInfoFrame2_on_menu_infoModeRight", m.createMenu)
end


--- Registers custom button on the map menu's right bar used to access market analytics.
--
-- @param menuConfig { * = * } Map menu configuration.
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

    m.updateOffers(offersPageSize, false)
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
-- @param frame { * = * } Frame descriptor where the table should be created.
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
-- @param frame { * = * } Frame descriptor where the table should be created.
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
        m.updateOffers(m.state.pageSize, true)
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


--- Creates listing table for the wares.
--
-- @param frame { * = * } Frame descriptor where the tabkle should be created.
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

            local sortParameters = m.generateFullSortParameters(m.state.sortParameters)
            table.sort(m.state.offers, function(a, b) return m.compareOffers(a, b, sortParameters) end)
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

            local sortParameters = m.generateFullSortParameters(m.state.sortParameters)
            table.sort(m.state.offers, function(a, b) return m.compareOffers(a, b, sortParameters) end)
            m.menu.refreshInfoFrame2()
        end
    end

    return ftable
end


--- Render offers in the ware listing table.
--
-- @param ftable { * = * } Table descriptor.
--
function m.renderOffers(ftable)
    local from = 1 + m.state.pageSize * (m.state.currentPage - 1)
    local to = math.min(#m.state.offers, m.state.pageSize * m.state.currentPage)

    for index = from, to do
        local offer = m.state.offers[index]
        local row = ftable:addRow(true, { fixed = true })
        row[1]:createText(offer.factionText)
        row[2]:createText(offer.stationText)
        row[3]:createText(offer.sectorText)
        row[4]:createText(offer.distanceText, { halign = "right" })
        row[5]:createText(offer.wareText)
        row[6]:createText(offer.offerTypeText)
        row[7]:createText(offer.priceText, { halign = "right" })
        row[8]:createText(offer.markupText, { halign = "right" })
        row[9]:createText(offer.amountText, { halign = "right" })
    end
end


--- Returns list of all active trade offers known to player, including various metadata or text rendering.
--
-- @return [table{faction = component<faction>, factionText = string, station = component<station>, stationText = string,
--     sector = component<sector>, sectorText = string, distance = number, distanceText = string, ware = component<ware>, wareText = string,
--     offerType = nil|1|2|3, offerTypeText = string, price = number, priceText = string, markup = number, markupText = string,
--     amount = number, amountText = string}] List of active trade offers.
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
                            offerType = trade.isbuyoffer and trade.isselloffer and 3 or trade.isbuyoffer and 2 or trade.isselloffer and 1 or nil,
                            offerTypeText = trade.isbuyoffer and "Buys" or trade.isselloffer and "Sells" or "None",
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
--
function m.updateOffers(pageSize, forceRefresh)
    if not m.state.offers or forceRefresh then
        m.state.offers = m.getTradeOffers()
        m.state.offersAge = C.GetCurrentGameTime()
        local sortParameters = m.generateFullSortParameters(m.state.sortParameters)
        table.sort(m.state.offers, function(a, b) return m.compareOffers(a, b, sortParameters) end)
    end

    m.state.pageSize = pageSize
    m.state.pageCount = math.ceil(#m.state.offers / m.state.pageSize)
    m.state.currentPage = math.min(m.state.currentPage, m.state.pageCount)
end


--- Updates menu controls (text etc) based on current state.
--
function m.updateControls()
    m.widgets.currentPage.properties.text.text = string.format("%s / %s", m.state.currentPage, m.state.pageCount)
    m.widgets.offersAge.properties.text = Helper.getPassedTime(m.state.offersAge)
end


--- Comparator for sorting trade offers.
--
-- Trade offers are sorted using the passed-in parameters. Sorting parameters are processed in provided order until a first non-equal match between the two
-- offers can be established.
--
-- @param a { * = * } Offer entry.
-- @param b { * = * } Offer entry.
-- @param parameters {{ property = string, ascending = bool}} List of parameters to use for comparing the trade offers.
-- @param parameterIndex number Index of parameter in the parameters list to use for current comparison operation.
--
-- @return bool Whether the first offer should be placed before the second offer.
--
function m.compareOffers(a, b, parameters, parameterIndex)
    parameterIndex = parameterIndex or 1
    local parameter = parameters[parameterIndex]

    if not parameter then
        return false
    end

    if a[parameter.property] == b[parameter.property] then
        return m.compareOffers(a, b, parameters, parameterIndex + 1)
    elseif parameter.ascending then
        return a[parameter.property] < b[parameter.property]
    else
        return a[parameter.property] > b[parameter.property]
    end
end


--- Generates full list of sort parameters, starting with passed-in parameters and continuing with remaining unused default sort parameters.
--
-- @param parameters {{ property = string, ascending = bool }} List of preferred sort parameters.
--
-- @return {{ property = string, ascending = bool }} Full list of sort parameters.
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

    local titleWidth = Helper.scaleX(C.GetTextWidth(title, Helper.standardFont, Helper.standardFontSize))
    local dataWidth = Helper.scaleX(C.GetTextWidth(data, Helper.standardFont, Helper.standardFontSize))
    local sortIndicatorWidth = Helper.scaleX(C.GetTextWidth(sortIndicator, Helper.standardFont, Helper.standardFontSize))

    local maximumWidth = math.max(titleWidth + sortIndicatorWidth, dataWidth) + Helper.standardTextOffsetx

    return maximumWidth
end


m.init()
