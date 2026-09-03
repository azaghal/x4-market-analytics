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
            width = Helper.scaleX(Helper.standardTextHeight) + Helper.standardTextOffsetx,
            text = "\27[mapst_factionrelation]",
        },
        {
            id = "station",
            index = 2,
            width = nil,
            text = "Station",
        },
        {
            id = "sector",
            index = 3,
            width = nil,
            text = "Sector",
        },
        {
            id = "distance",
            index = 4,
            width = Helper.scaleX(C.GetTextWidth("999j", Helper.standardFont, Helper.standardFontSize)) + Helper.standardTextOffsetx,
            text = "Distance",
        },
        {
            id = "ware",
            index = 5,
            width = nil,
            text = "Ware",
        },
        {
            id = "type",
            index = 6,
            width = Helper.scaleX(C.GetTextWidth("Buy / Sell", Helper.standardFont, Helper.standardFontSize)) + Helper.standardTextOffsetx,
            text = "Type",
        },
        {
            id = "price",
            index = 7,
            width = Helper.scaleX(C.GetTextWidth("99999.99 Cr", Helper.standardFont, Helper.standardFontSize)) + Helper.standardTextOffsetx,
            text = "Price",
        },
        {
            id = "markup",
            index = 8,
            width = Helper.scaleX(C.GetTextWidth("+99.99%", Helper.standardFont, Helper.standardFontSize)) + Helper.standardTextOffsetx,
            text = "Markup",
        },
        {
            id = "amount",
            index = 9,
            width = Helper.scaleX(C.GetTextWidth("999999", Helper.standardFont, Helper.standardFontSize)) + Helper.standardTextOffsetx,
            text = "Amount",
        },
    },
}


--- Initialises the mod.
--
function m.init()
    m.menu = Helper.getMenu("MapMenu")
    m.menuConfig = m.menu.uix_getConfig()

    m.state = {
        currentPage = 1,
    }

    -- Keep track of widgets that might require updates after their creation.
    m.widgets = {}

    m.menu.registerCallback("createRightBar_on_start", m.registerRightBar)
    m.menu.registerCallback("createInfoFrame2_on_menu_infoModeRight", m.createMenu)
end


--- Registers custom button on the map menu's right bar used to access market analytics.
--
-- @param menuConfig table Map menu configuration.
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
-- @param frame table Frame descriptor where the table should be created.
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
-- @param frame table Frame descriptor where the table should be created.
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
-- @param frame table Frame descriptor where the tabkle should be created.
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
        row[index]:createText(column.text)
    end

    return ftable
end


--- Render offers in the ware listing table.
--
-- @param ftable table Table descriptor.
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
                            offerTypeText = trade.isbuyoffer and trade.isselloffer and "Buy/Sell" or trade.isbuyoffer and "Buy" or trade.isselloffer and "Sell" or "",
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


m.init()
