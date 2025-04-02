TurtleMail = TurtleMail or {}
local m = TurtleMail

if m.Calendar then return end

---@class Calendar
---@field show fun( data: table, date: number, anchor: table, on_select: function )
---@field hide fun()
---@field is_visible fun():boolean

local M = {}

function M.new()
  local BTN_WIDTH = 25
  local BTN_HEIGHT = 20

  local calendar
  local set_year, set_month
  local year_dd, month_dd
  local date_data = {}
  local months = {}
  local days = {}
  local select_func

  for i = 1, 12 do
    local timestamp = time( { year = 2025, month = i, day = 1 } )
    months[ i ] = date( "%B", timestamp )
  end

  local function get_end_day_of_month( year, month )
    if month == 2 then
      if (mod( year, 4 ) == 0 and mod( year, 100 ) ~= 0) or mod( year, 400 ) == 0 then
        return 29
      else
        return 28
      end
    elseif month == 4 or month == 6 or month == 9 or month == 11 then
      return 30
    else
      return 31
    end
  end

  ---@alias DatePart
  ---| "Year"
  ---| "Month"
  ---| "Day"

  ---@param part DatePart
  local function get_valid_dates( part )
    local valid = {}
    for i, v in ipairs( date_data ) do
      local year = tonumber( date( "%Y", v.timestamp ) )
      local month = tonumber( date( "%m", v.timestamp ) )
      local day = tonumber( date( "%d", v.timestamp ) )

      if year and month and day then
        if part == "Day" and year == set_year and month == set_month then
          valid[ day ] = valid[ day ] and valid[ day ] + 1 or 1
        elseif part == "Month" and year == set_year then
          valid[ month ] = true
        elseif part == "Year" then
          valid[ year ] = true
        end
      end
    end

    return valid
  end

  local function refresh()
    local current_month = { year = set_year, month = set_month, day = "01" }
    local skip_days = date( "%w", time( current_month ) )
    local end_day = get_end_day_of_month( tonumber( set_year ), tonumber( set_month ) )

    for i = 1, 42 do
      days[ i ]:SetText( "" )
      days[ i ]:Disable()
      days[ i ]:Hide()
    end

    local valid_days = get_valid_dates( "Day" )
    for i = 1, end_day do
      local day = days[ i + skip_days ]
      local d = i
      day:SetText( i )

      if valid_days[ i ] then
        day.mails = valid_days[ i ]
        day:Enable()
      end
      day:Show()

      day:SetScript( "OnClick", function()
        local timestamp = time( { year = set_year, month = set_month, day = d } )
        if select_func then
          select_func( timestamp )
        end
        calendar:Hide()
      end )
    end

    if tonumber( skip_days + end_day ) < 36 then
      calendar:SetHeight( 150 )
    else
      calendar:SetHeight( 170 )
    end

    m.api.UIDropDownMenu_SetText( months[ set_month ], month_dd )
    m.api.UIDropDownMenu_SetText( set_year, year_dd )
  end

  local function pfui_skin()
    if m.pfui_skin_enabled then
      m.api.pfUI.api.SkinDropDown( year_dd, nil, nil, nil, true )
      year_dd:SetPoint( "TOPLEFT", -5, -5 )
      m.api.pfUI.api.SkinDropDown( month_dd, nil, nil, nil, true )
      month_dd:SetPoint( "TOPLEFT", 79, -5 )
      m.api.UIDropDownMenu_SetWidth( 70, month_dd )

      for i = 1, 42 do
        local button = days[ i ]
        m.api.pfUI.api.SkinButton( button )
        button:SetWidth( BTN_WIDTH - 1 )
        button:SetHeight( BTN_HEIGHT - 1 )
      end
    end
  end

  ---@param parent table
  ---@param index number
  local function create_date_button( parent, index )
    local button = m.api.CreateFrame( "Button", "TurtleMailCalendarDay" .. index .. "Button", parent, "UIPanelButtonTemplate" )
    button:SetWidth( BTN_WIDTH )
    button:SetHeight( BTN_HEIGHT )
    button:GetFontString():SetFont( m.pfui_skin_enabled and m.api.pfUI.font_default or "Fonts/FRIZQT__.TTF", 9 )
    button:GetFontString():SetTextColor( 1, 1, 1, 1 )

    local orig_disable = button.Disable
    button.Disable = function( self )
      orig_disable( self )
      button:GetFontString():SetTextColor( 0.5, 0.5, 0.5, 1 )
    end

    local orig_enable = button.Enable
    button.Enable = function( self )
      orig_enable( self )
      button:GetFontString():SetTextColor( 1, 1, 1, 1 )
    end

    button:SetScript( "OnEnter", function()
      m.api.GameTooltip:SetOwner( this, "ANCHOR_RIGHT" )
      m.api.GameTooltip:SetText( button.mails .. " mail" .. (button.mails > 1 and "s" or ""), 1, 1, 1, 1, true )
      m.api.GameTooltip:Show()
    end )

    button:SetScript( "OnLeave", function()
      m.api.GameTooltip:Hide()
    end )

    return button
  end

  ---@param parent table
  ---@param name DatePart
  ---@param on_select function
  ---@return table
  local function create_dropdown( parent, name, on_select )
    local dropdown = m.api.CreateFrame( "Frame", "TurtleMailDropdown" .. name, parent, "UIDropDownMenuTemplate" )

    m.api.UIDropDownMenu_Initialize( dropdown, function()
      local valid_dates = get_valid_dates( name )
      local info = {}

      for i in pairs( valid_dates ) do
        info.arg1 = i
        info.arg2 = name == "Month" and months[ i ] or i
        info.value = info.arg1
        info.text = info.arg2

        info.func = function( index, value )
          m.api.UIDropDownMenu_SetText( value, dropdown )
          m.api.CloseDropDownMenus()
          on_select( index, value )
        end

        m.api.UIDropDownMenu_AddButton( info )
      end
    end )

    return dropdown
  end

  local function create_calendar()
    local frame = m.api.CreateFrame( "Frame", "TurtleMailCalendarFrame" )
    frame:SetFrameStrata( "FULLSCREEN_DIALOG" )
    frame:SetWidth( 195 )
    frame:SetHeight( 170 )
    frame:SetBackdrop( {
      bgFile = "Interface/Buttons/WHITE8x8",
      edgeFile = "Interface/Buttons/WHITE8x8",
      tile = false,
      tileSize = 0,
      edgeSize = 0.5,
      insets = { left = 0, right = 0, top = 0, bottom = 0 }
    } )

    frame:SetBackdropColor( 0, 0, 0, 0.9 )
    frame:SetBackdropBorderColor( .4, .4, .4, 0.9 )
    frame:EnableMouse( true )
    frame:Hide()
    m.api.tinsert( m.api.UISpecialFrames, frame:GetName() )

    frame:SetScript( "OnLeave", function()
      if m.api.MouseIsOver( frame ) then
        return
      end
      calendar:Hide()
    end )

    year_dd = create_dropdown( frame, "Year", function( _, v )
      set_year = v
      refresh()
    end )
    year_dd:SetPoint( "TOPLEFT", -12, -5 )
    m.api.UIDropDownMenu_SetWidth( 55, year_dd )

    month_dd = create_dropdown( frame, "Month", function( v )
      set_month = v
      refresh()
    end )
    month_dd:SetPoint( "TOPLEFT", 70, -5 )
    m.api.UIDropDownMenu_SetWidth( 85, month_dd )

    for i = 1, 42 do
      table.insert( days, create_date_button( frame, i ) )
    end

    for i = 1, 6 do
      for j = 1, 7 do
        days[ (i - 1) * 7 + j ]:SetPoint( "TOPLEFT", frame, 10 + (j - 1) * BTN_WIDTH, -40 - (i - 1) * BTN_HEIGHT )
        days[ (i - 1) * 7 + j ]:Disable()
      end
    end

    pfui_skin()
    return frame
  end

  local function show( data, current_date, anchor, on_select )
    date_data = data
    set_year = tonumber( date( "%Y", current_date ) )
    set_month = tonumber( date( "%m", current_date ) )
    select_func = on_select

    if not calendar then
      calendar = create_calendar()
    end

    if m.pfui_skin_enabled then
      calendar:SetPoint( "TOPRIGHT", anchor, "BOTTOMRIGHT", 125, -4 )
    else
      calendar:SetPoint( "TOPRIGHT", anchor, "BOTTOMRIGHT", 100, 1 )
    end

    refresh()
    calendar:Show()
  end

  local function hide()
    if calendar then
      calendar:Hide()
    end
  end

  local function is_visible()
    if calendar then
      return calendar:IsVisible()
    end
    return false
  end

  ---@type Calendar
  return {
    show = show,
    hide = hide,
    is_visible = is_visible
  }
end

m.Calendar = M
return M
