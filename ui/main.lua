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

    local titleTable = m.createHeaderTable(m.menu.infoFrame2, 0, 0)
    local waresTable = m.createWaresTable(m.menu.infoFrame2, 0, titleTable:getVisibleHeight() + Helper.borderSize * 2)

    m.renderData(waresTable)
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


--- Render the ware data in the ware listing table.
--
-- @param ftable table Table descriptor.
--
function m.renderData(ftable)
    -- @TODO: Temporary placeholder for testing initial rendering.
    local row = ftable:addRow(true, { fixed = true })
    row[1]:createText("\27[faction_argon]")
    row[2]:createText("ARG Microchip Factory")
    row[3]:createText("Argon Prime")
    row[4]:createText("0j", { halign = "right" })
    row[5]:createText("Microchips")
    row[6]:createText("Sell")
    row[7]:createText("1000.22 Cr", { halign = "right" })
    row[8]:createText("-12%", { halign = "right" })
    row[9]:createText("23123", { halign = "right" })
end


m.init()
