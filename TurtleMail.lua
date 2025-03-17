local api = getfenv()
Mail = Mail or api.CreateFrame( 'Frame', nil, api.MailFrame )
local m = Mail
local getn = table.getn ---@diagnostic disable-line: deprecated
local function pack( ... ) return arg end

local ATTACHMENTS_MAX = 21
local ATTACHMENTS_PER_ROW_SEND = 7
local ATTACHMENTS_MAX_ROWS_SEND = 3

local INBOX_AUCTIONHOUSES = {
  [ "Stormwind Auction House" ] = true,
  [ "Alliance Auction House" ] = true,
  [ "Darnassus Auction House" ] = true,
  [ "Undercity Auction House" ] = true,
  [ "Thunder Bluff  Auction House" ] = true,
  [ "Horde Auction House" ] = true,
  [ "Blackwater Auction House" ] = true,
}

m.timer = 0
m.orig = {}
m.hooks = {}
m.hook = setmetatable( {}, { __newindex = function( _, k, v ) m.hooks[ k ] = v end } )
m.debug_enabled = false
api.TurtleMail_AutoCompleteNames = {}

function Mail.init()
  m.debug( "Mail.init" )
  m:SetScript( "OnUpdate", m.on_update )

  -- Register events
  m:SetScript( "OnEvent", function() m[ event ]() end )
  for _, event in { "ADDON_LOADED", "PLAYER_LOGIN", "UI_ERROR_MESSAGE", "CURSOR_UPDATE", "BAG_UPDATE", "MAIL_SHOW", "MAIL_CLOSED", "MAIL_SEND_SUCCESS", "MAIL_INBOX_UPDATE" } do
    m:RegisterEvent( event )
  end
end

function Mail.on_update()
  if not api.MailFrame or not api.MailFrame:IsVisible() then return end

  if m._cursorItem then
    m.debug( "on_update: cursorItem" )
    m.cursorItem = m._cursorItem
    m._cursorItem = nil
  end

  if m.sendmail_update then
    m.debug( "on_update: sendmail" )
    m.sendmail_update = nil
    if SendMail_sending then
      m.debug( "SendMail_sending" )
      SendMail_Send()
    end
  end

  if m.inbox_update then
    m.debug( "on_update: inbox_update" )
    m.inbox_update = false
    local _, _, _, _, _, COD, _, _, _, _, _, _, isGM = api.GetInboxHeaderInfo( m.inbox_index )
    if m.inbox_index > api.GetInboxNumItems() then
      if m.money_received > 0 then
        api.DEFAULT_CHAT_FRAME:AddMessage( string.format( "|cffabd473TurtleMail|r: %s%s.", m.format_money( m.money_received ), L[ "collected" ] ) )
      end
      Inbox_Abort()
    elseif Inbox_Skip or COD > 0 or isGM then
      Inbox_Skip = false
      m.inbox_index = m.inbox_index + 1
      m.inbox_update = true
    else
      Inbox_Open( m.inbox_index )
    end
  end

  if m.timer > 0 then
    m.timer = m.timer - 1
  elseif not Inbox_opening then
    m.timer = 200
    api.CheckInbox()
  end
end

function Mail.CURSOR_UPDATE()
  m.cursorItem = nil
end

function Mail.get_cursor_item()
  return Mail.cursorItem
end

---@param item table
function Mail.set_cursor_item( item )
  m._cursorItem = item
end

function Mail.BAG_UPDATE()
  if api.MailFrame:IsVisible() then
    api.SendMailFrame_Update()
  end
end

function Mail.MAIL_SHOW()
  if api.TurtleMail_Point then
    api.MailFrame:SetPoint( api.TurtleMail_Point.point, api.TurtleMail_Point.x, api.TurtleMail_Point.y )
  end

  m.timer = 0
  m.money_received = 0
  m.update_money( 0 )
end

function Mail.MAIL_CLOSED()
  Inbox_Abort()
  SendMail_sending = false
  SendMail_Clear()
end

function Mail.UI_ERROR_MESSAGE()
  if Inbox_opening then
    if arg1 == api.ERR_INV_FULL then
      Inbox_Abort()
    elseif arg1 == api.ERR_ITEM_MAX_COUNT then
      Inbox_skip = true
    end
  elseif SendMail_sending and (arg1 == api.ERR_MAIL_TO_SELF or arg1 == api.ERR_PLAYER_WRONG_FACTION or arg1 == api.ERR_MAIL_TARGET_NOT_FOUND or arg1 == api.ERR_MAIL_REACHED_CAP) then
    SendMail_sending = false
    SendMail_state = nil
    api.ClearCursor()
    m.orig.ClickSendMailItemButton()
    api.ClearCursor()
  end
end

function Mail.ADDON_LOADED()
  if arg1 ~= "TurtleMail" then return end

  local version = api.GetAddOnMetadata( "TurtleMail", "Version" )
  api.DEFAULT_CHAT_FRAME:AddMessage( string.format( "|cffabd473TurtleMail|r: Loaded(|cffeda55fv%s|r).", version ) )

  api.UIPanelWindows.MailFrame.pushable = 1
  api.UIPanelWindows.FriendsFrame.pushable = 2

  m.inbox_load()
  m.sendmail_load()
end

function Mail.PLAYER_LOGIN()
  m.debug( "PLAYER_LOGIN" )
  for k, v in m.hooks do
    m.orig[ k ] = api[ k ]
    api[ k ] = v
  end
  local key = api.GetCVar( "realmName" ) .. "|" .. api.UnitFactionGroup( "player" )
  api.TurtleMail_AutoCompleteNames[ key ] = api.TurtleMail_AutoCompleteNames[ key ] or {}
  for char, lastSeen in api.TurtleMail_AutoCompleteNames[ key ] do
    if api.GetTime() - lastSeen > 60 * 60 * 24 * 30 then
      api.TurtleMail_AutoCompleteNames[ key ][ char ] = nil
    end
  end

  m.add_auto_complete_name( api.UnitName( "player" ) )
end

function Mail.MAIL_SEND_SUCCESS()
  if SendMail_state then
    m.add_auto_complete_name( SendMail_state.to )
  end
  if SendMail_sending then
    m.sendmail_update = true
  end
end

function Mail.MAIL_INBOX_UPDATE()
  if Inbox_opening then
    m.inbox_update = true
  end
  
  for i = 1, 7 do
    local index = (i + (api.InboxFrame.pageNum - 1) * 7)
    if index <= api.GetInboxNumItems() then
      local _, _, sender, _, _, _, _, _, _, wasReturned = api.GetInboxHeaderInfo( index )
      if INBOX_AUCTIONHOUSES[ sender ] then
        api[ "TurtleMailAuctionIcon" .. i ]:Show()
      else
        api[ "TurtleMailAuctionIcon" .. i ]:Hide()
      end
      if wasReturned then
        api[ "TurtleMailReturnedArrow" .. i ]:Show()
      else
        api[ "TurtleMailReturnedArrow" .. i ]:Hide()
      end
    end
  end
end

---@param name string
function Mail.add_auto_complete_name( name )
  local key = api.GetCVar( "realmName" ) .. "|" .. api.UnitFactionGroup( "player" )
  api.TurtleMail_AutoCompleteNames[ key ][ name ] = api.GetTime()
end

function Mail.inbox_load()
  local btn = api.CreateFrame( "Button", nil, api.InboxFrame, "UIPanelButtonTemplate" )
  btn:SetPoint( "BOTTOM", -10, 90 )
  btn:SetText( api.OPENMAIL )
  btn:SetWidth( math.max( 120, 30 + ({ btn:GetRegions() })[ 1 ]:GetStringWidth() ) )
  btn:SetHeight( 25 )
  btn:SetScript( "OnClick", Inbox_OpenAll )

  api.MailFrame:SetMovable( true )
  api.MailFrame:SetScript( "OnDragStop", m.on_drag_stop )

  for i = 1, 7 do
    api[ "TurtleMailAuctionIcon" .. i .. "Texture" ]:SetVertexColor( api.NORMAL_FONT_COLOR.r, api.NORMAL_FONT_COLOR.g, api.NORMAL_FONT_COLOR.b )
    api[ "TurtleMailReturnedArrow" .. i .. "Texture" ]:SetVertexColor( api.NORMAL_FONT_COLOR.r, api.NORMAL_FONT_COLOR.g, api.NORMAL_FONT_COLOR.b )
  end
end

function Inbox_OpenAll()
  Inbox_opening = true
  Inbox_UpdateLock()
  Inbox_skip = false
  m.inbox_index = 1
  m.inbox_update = true
end

function Inbox_Abort()
  Inbox_opening = false
  Inbox_UpdateLock()
  m.inbox_update = false
end

function Mail.set_cod_text()
  local text = string.sub( api.COD_AMOUNT, 1, string.len( api.COD_AMOUNT ) - 1 )

  ---@diagnostic disable-next-line: undefined-global
  if not pfUI or not pfUI.version then
    text = string.match( text, "^(.-)%s+%S+$" )
  end

  if api.SendMailCODAllButton:GetChecked() then
    api.SendMailMoneyText:SetText( text .. " " .. L[ "each mail" ] .. ":" )
  else
    api.SendMailMoneyText:SetText( text .. " " .. L[ "1st mail" ] .. ":" )
  end
end

---@param copper number
function Mail.format_money( copper )
  local gold = math.floor( copper / 10000 )
  local silver = math.floor( (copper - gold * 10000) / 100 )
  local copper_remain = copper - (gold * 10000) - (silver * 100)

  local result = ""
  if gold > 0 then
    result = result .. string.format( "|cffffffff%d|cffffd700g|r ", gold )
  end
  if silver > 0 then
    result = result .. string.format( "|cffffffff%d|cffc7c7cfs|r ", silver )
  end
  if copper_remain > 0 or result == "" then
    result = result .. string.format( "|cffffffff%d|cffeda55fc|r ", copper_remain )
  end

  return result
end

---@param money number
function Mail.update_money( money )
  m.money_received = m.money_received + money
  api.MoneyReceived:SetText( L[ "Money received" ] .. ": " .. m.format_money( m.money_received ) )

  if m.money_received > 0 then
    api.MoneyReceived:Show()
  else
    api.MoneyReceived:Hide()
  end
end

function Mail.on_drag_stop()
  local f = api.MailFrame
  if not f then return end
  f:StopMovingOrSizing()

  local screen_width = api.GetScreenWidth()
  local screen_height = api.GetScreenHeight()
  local point, _, _, x, y = api.MailFrame:GetPoint()
  local nx, ny = x, y

  if f:GetLeft() < -10 then nx = -10 end
  if f:GetRight() > screen_width + 28 then nx = screen_width + 28 - f:GetWidth() end
  if f:GetTop() > screen_height + 10 then ny = 10 end
  if f:GetBottom() < -44 then ny = -screen_height + f:GetHeight() - 44 end

  if (nx ~= x or ny ~= y) then
    api.MailFrame:SetPoint( point, nx, ny )
  end

  api.TurtleMail_Point = { point = point, x = nx, y = ny }
end

do
  -- hack to prevent beancounter from deleting mail
  local TakeInboxMoney, TakeInboxItem, DeleteInboxItem = api.TakeInboxMoney, api.TakeInboxItem, api.DeleteInboxItem
  ---@param i number
  ---@param manual boolean?
  function Inbox_Open( i, manual )
    local _, _, _, _, money, _, _, _, read, _, _, _, _ = api.GetInboxHeaderInfo( i )
    if money and read or manual then
      m.update_money( money )
    end
    api.GetInboxText( i )

    TakeInboxMoney( i )
    TakeInboxItem( i )
    DeleteInboxItem( i )
  end
end

function Inbox_UpdateLock()
  for i = 1, 7 do
    api[ "MailItem" .. i .. "ButtonIcon" ]:SetDesaturated( Inbox_opening )
    if Inbox_opening then
      api[ "MailItem" .. i .. "Button" ]:SetChecked( nil )
    end
  end
end

function Mail.hook.GetInboxHeaderInfo( ... )
  local sender, canReply = arg[ 3 ], arg[ 12 ]
  if sender and canReply then
    m.add_auto_complete_name( sender )
  end
  return m.orig.GetInboxHeaderInfo( unpack( arg ) )
end

function Mail.hook.OpenMail_Reply( ... )
  api.TurtleMail_To = nil
  return m.orig.OpenMail_Reply( unpack( arg ) )
end

function Mail.hook.InboxFrame_Update()
  m.orig.InboxFrame_Update()
  for i = 1, 7 do
    -- hack for tooltip update
    api[ "MailItem" .. i ]:Hide()
    api[ "MailItem" .. i ]:Show()
  end

  local currentPage = api.InboxFrame.pageNum
  local totalPages = math.ceil( api.GetInboxNumItems() / api.INBOXITEMS_TO_DISPLAY )
  local text = totalPages > 0 and (currentPage .. "/" .. totalPages) or api.EMPTY
  api.InboxTitleText:SetText( api.INBOX .. " [" .. text .. "]" )

  Inbox_UpdateLock()
end

function Mail.hook.InboxFrame_OnClick( i )
  if Inbox_opening or arg1 == "RightButton" and ({ api.GetInboxHeaderInfo( i ) })[ 6 ] > 0 then
    this:SetChecked( nil )
  elseif arg1 == "RightButton" then
    Inbox_Open( i, true )
  else
    return m.orig.InboxFrame_OnClick( i )
  end
end

function Mail.hook.InboxFrameItem_OnEnter()
  m.orig.InboxFrameItem_OnEnter()
  if api.GetInboxItem( this.index ) then
    api.GameTooltip:AddLine( api.ITEM_OPENABLE, "", 0, 1, 0 )
    api.GameTooltip:Show()
  end
end

function Mail.hook.SendMailFrame_Update()
  local gap
  -- local last = 0 blizzlike
  local last = SendMail_NumAttachments()

  for i = 1, ATTACHMENTS_MAX do
    local btn = api[ "MailAttachment" .. i ]

    local texture, count
    if btn.item then
      texture, count = api.GetContainerItemInfo( unpack( btn.item ) )
    end
    if not texture then
      btn:SetNormalTexture( nil )
      api[ btn:GetName() .. "Count" ]:Hide()
      btn.item = nil
    else
      btn:SetNormalTexture( texture )
      if count > 1 then
        api[ btn:GetName() .. "Count" ]:Show()
        api[ btn:GetName() .. "Count" ]:SetText( count )
      else
        api[ btn:GetName() .. "Count" ]:Hide()
      end
    end
  end

  if SendMail_NumAttachments() > 0 then
    api.SendMailCODButton:Enable()
    api.SendMailCODButtonText:SetTextColor( api.NORMAL_FONT_COLOR.r, api.NORMAL_FONT_COLOR.g, api.NORMAL_FONT_COLOR.b )
    if SendMail_NumAttachments() > 1 and api.SendMailCODButton:GetChecked() then
      api.SendMailCODAllButton:Enable()
      api.SendMailCODAllButtonText:SetTextColor( api.NORMAL_FONT_COLOR.r, api.NORMAL_FONT_COLOR.g, api.NORMAL_FONT_COLOR.b )
      m.set_cod_text()
    else
      api.SendMailCODAllButton:Disable()
      api.SendMailCODAllButtonText:SetTextColor( api.GRAY_FONT_COLOR.r, api.GRAY_FONT_COLOR.g, api.GRAY_FONT_COLOR.b )
      api.SendMailMoneyText:SetText( api.AMOUNT_TO_SEND )
    end
  else
    api.SendMailSendMoneyButton:SetChecked( 1 )
    api.SendMailCODButton:SetChecked( nil )
    api.SendMailMoneyText:SetText( api.AMOUNT_TO_SEND )
    api.SendMailCODButton:Disable()
    api.SendMailCODButtonText:SetTextColor( api.GRAY_FONT_COLOR.r, api.GRAY_FONT_COLOR.g, api.GRAY_FONT_COLOR.b )
    api.SendMailCODAllButton:Disable()
    api.SendMailCODAllButtonText:SetTextColor( api.GRAY_FONT_COLOR.r, api.GRAY_FONT_COLOR.g, api.GRAY_FONT_COLOR.b )
  end

  api.MoneyFrame_Update( "SendMailCostMoneyFrame", api.GetSendMailPrice() * math.max( 1, SendMail_NumAttachments() ) )

  -- Determine how many rows of attachments to show
  local itemRowCount = 1
  local temp = last
  while temp > ATTACHMENTS_PER_ROW_SEND and itemRowCount < ATTACHMENTS_MAX_ROWS_SEND do
    itemRowCount = itemRowCount + 1
    temp = temp - ATTACHMENTS_PER_ROW_SEND
  end

  if not gap and temp == ATTACHMENTS_PER_ROW_SEND and itemRowCount < ATTACHMENTS_MAX_ROWS_SEND then
    itemRowCount = itemRowCount + 1
  end
  if api.SendMailFrame.maxRowsShown and last > 0 and itemRowCount < api.SendMailFrame.maxRowsShown then
    itemRowCount = api.SendMailFrame.maxRowsShown
  else
    api.SendMailFrame.maxRowsShown = itemRowCount
  end

  -- Compute sizes
  local cursorx = 0
  local cursory = itemRowCount - 1
  local marginxl = 8 + 6
  local marginxr = 40 + 6
  local areax = api.SendMailFrame:GetWidth() - marginxl - marginxr
  local iconx = api.MailAttachment1:GetWidth() + 2
  local icony = api.MailAttachment1:GetHeight() + 2
  local gapx1 = api.floor( (areax - (iconx * ATTACHMENTS_PER_ROW_SEND)) / (ATTACHMENTS_PER_ROW_SEND - 1) )
  local gapx2 = api.floor( (areax - (iconx * ATTACHMENTS_PER_ROW_SEND) - (gapx1 * (ATTACHMENTS_PER_ROW_SEND - 1))) / 2 )
  local gapy1 = 5
  local gapy2 = 6
  local areay = (gapy2 * 2) + (gapy1 * (itemRowCount - 1)) + (icony * itemRowCount)
  local indentx = marginxl + gapx2 + 17
  local indenty = 170 + gapy2 + icony - 13
  local tabx = (iconx + gapx1) - 3 --this magic number changes the attachment spacing
  local taby = (icony + gapy1)
  local scrollHeight = 249 - areay

  api.MailHorizontalBarLeft:SetPoint( "TOPLEFT", api.SendMailFrame, "BOTTOMLEFT", 2 + 15, 184 + areay - 14 )

  api.SendMailScrollFrame:SetHeight( scrollHeight )
  api.SendMailScrollChildFrame:SetHeight( scrollHeight )

  local SendMailScrollFrameTop = ({ api.SendMailScrollFrame:GetRegions() })[ 3 ]
  SendMailScrollFrameTop:SetHeight( scrollHeight )
  SendMailScrollFrameTop:SetTexCoord( 0, .484375, 0, scrollHeight / 256 )

  api.StationeryBackgroundLeft:SetHeight( scrollHeight )
  api.StationeryBackgroundLeft:SetTexCoord( 0, 1, 0, scrollHeight / 256 )


  api.StationeryBackgroundRight:SetHeight( scrollHeight )
  api.StationeryBackgroundRight:SetTexCoord( 0, 1, 0, scrollHeight / 256 )

  -- Set Items
  for i = 1, ATTACHMENTS_MAX do
    if cursory >= 0 then
      api[ "MailAttachment" .. i ]:Enable()
      api[ "MailAttachment" .. i ]:Show()
      api[ "MailAttachment" .. i ]:SetPoint( "TOPLEFT", "SendMailFrame", "BOTTOMLEFT", indentx + (tabx * cursorx),
        indenty + (taby * cursory) )

      cursorx = cursorx + 1
      if cursorx >= ATTACHMENTS_PER_ROW_SEND then
        cursory = cursory - 1
        cursorx = 0
      end
    else
      api[ "MailAttachment" .. i ]:Hide()
    end
  end

  api.SendMailFrame_CanSend()
end

function Mail.hook.SendMailRadioButton_OnClick( index )
  if (index == 1) then
    api.SendMailSendMoneyButton:SetChecked( 1 );
    api.SendMailCODButton:SetChecked( nil );
    api.SendMailMoneyText:SetText( api.AMOUNT_TO_SEND );
    api.SendMailCODAllButton:Disable()
    api.SendMailCODAllButtonText:SetTextColor( api.GRAY_FONT_COLOR.r, api.GRAY_FONT_COLOR.g, api.GRAY_FONT_COLOR.b )
  else
    api.SendMailSendMoneyButton:SetChecked( nil );
    api.SendMailCODButton:SetChecked( 1 );
    api.SendMailMoneyText:SetText( api.COD_AMOUNT );

    if SendMail_NumAttachments() > 1 then
      api.SendMailCODAllButton:Enable()
      api.SendMailCODAllButtonText:SetTextColor( api.NORMAL_FONT_COLOR.r, api.NORMAL_FONT_COLOR.g, api.NORMAL_FONT_COLOR.b )
      m.set_cod_text()
    end
  end
  api.PlaySound( "igMainMenuOptionCheckBoxOn" );
end

function Mail.hook.ClickSendMailItemButton()
  SendMail_SetAttachment( m.get_cursor_item() )
end

function Mail.hook.GetContainerItemInfo( bag, slot )
  local ret = pack( m.orig.GetContainerItemInfo( bag, slot ) )
  ret[ 3 ] = ret[ 3 ] or SendMail_Attached( bag, slot ) and 1 or nil
  return unpack( ret )
end

function Mail.hook.PickupContainerItem( bag, slot )
  if SendMail_Attached( bag, slot ) then return end
  if api.GetContainerItemInfo( bag, slot ) then m.set_cursor_item( { bag, slot } ) end
  return m.orig.PickupContainerItem( bag, slot )
end

function Mail.hook.SplitContainerItem( bag, slot, amount )
  if SendMail_Attached( bag, slot ) then return end
  return m.orig.SplitContainerItem( bag, slot, amount )
end

function Mail.hook.UseContainerItem( bag, slot, onself )
  if SendMail_Attached( bag, slot ) then return end
  if api.IsShiftKeyDown() or api.IsControlKeyDown() or api.IsAltKeyDown() then
    return m.orig.UseContainerItem( bag, slot, onself )
  elseif api.MailFrame:IsVisible() then
    api.MailFrameTab_OnClick( 2 )
    SendMail_SetAttachment { bag, slot }
  elseif api.TradeFrame:IsVisible() then
    for i = 1, 6 do
      if not api.GetTradePlayerItemLink( i ) then
        m.orig.PickupContainerItem( bag, slot )
        api.ClickTradeButton( i )
        return
      end
    end
  else
    return m.orig.UseContainerItem( bag, slot, onself )
  end
end

function Mail.hook.SendMailFrame_CanSend()
  if not SendMail_sending and string.len( api.SendMailNameEditBox:GetText() ) > 0 and (api.SendMailSendMoneyButton:GetChecked() and api.MoneyInputFrame_GetCopper( api.SendMailMoney ) or 0) + api.GetSendMailPrice() * math.max( 1, SendMail_NumAttachments() ) <= api.GetMoney() then
    MailMailButton:Enable()
  else
    MailMailButton:Disable()
  end
end

function MailMailButton_OnClick()
  api.MailAutoCompleteBox:Hide()

  api.TurtleMail_To = api.SendMailNameEditBox:GetText()
  api.SendMailNameEditBox:HighlightText()

  SendMail_state = {
    to = api.TurtleMail_To,
    subject = MailSubjectEditBox:GetText(),
    body = api.SendMailBodyEditBox:GetText(),
    money = api.MoneyInputFrame_GetCopper( api.SendMailMoney ),
    cod = api.SendMailCODButton:GetChecked(),
    attachments = SendMail_Attachments(),
    numMessages = math.max( 1, SendMail_NumAttachments() ),
  }

  SendMail_Clear()
  SendMail_sending = true
  SendMail_Send()
end

function Mail.sendmail_load()
  api.SendMailFrame:EnableMouse( false )
  api.SendMailFrame:CreateTexture( "MailHorizontalBarLeft", "BACKGROUND" )
  api.SendMailFrame:CreateTexture( "MailHorizontalBarRight", "BACKGROUND" )
  ---@diagnostic disable-next-line: undefined-global
  if not pfUI or not pfUI.version then
    api.MailHorizontalBarLeft:SetTexture( [[Interface\ClassTrainerFrame\UI-ClassTrainer-HorizontalBar]] )
    api.MailHorizontalBarLeft:SetWidth( 256 )
    api.MailHorizontalBarLeft:SetHeight( 16 )
    api.MailHorizontalBarLeft:SetTexCoord( 0, 1, 0, .25 )

    api.MailHorizontalBarRight:SetTexture( [[Interface\ClassTrainerFrame\UI-ClassTrainer-HorizontalBar]] )
    api.MailHorizontalBarRight:SetWidth( 75 )
    api.MailHorizontalBarRight:SetHeight( 16 )
    api.MailHorizontalBarRight:SetTexCoord( 0, .29296875, .25, .5 )
    api.MailHorizontalBarRight:SetPoint( "LEFT", api.MailHorizontalBarLeft, "RIGHT" )
  end

  do
    local background = ({ api.SendMailPackageButton:GetRegions() })[ 1 ]
    background:Hide()
    local count = ({ api.SendMailPackageButton:GetRegions() })[ 3 ]
    count:Hide()
    api.SendMailPackageButton:Disable()
    api.SendMailPackageButton:SetScript( "OnReceiveDrag", nil )
    api.SendMailPackageButton:SetScript( "OnDragStart", nil )
  end

  api.SendMailMoneyText:SetJustifyH( "LEFT" )
  api.SendMailMoneyText:SetPoint( "TOPLEFT", 0, 0 )
  api.SendMailMoney:ClearAllPoints()
  api.SendMailMoney:SetPoint( "TOPLEFT", api.SendMailMoneyText, "BOTTOMLEFT", 5, -5 )
  api.SendMailMoneyGoldRight:SetPoint( "RIGHT", 20, 0 )
  do ({ api.SendMailMoneyGold:GetRegions() })[ 9 ]:SetDrawLayer( "BORDER" ) end
  api.SendMailMoneyGold:SetMaxLetters( 7 )
  api.SendMailMoneyGold:SetWidth( 50 )
  api.SendMailMoneySilverRight:SetPoint( "RIGHT", 10, 0 )
  do ({ api.SendMailMoneySilver:GetRegions() })[ 9 ]:SetDrawLayer( "BORDER" ) end
  api.SendMailMoneySilver:SetWidth( 28 )
  api.SendMailMoneySilver:SetPoint( "LEFT", api.SendMailMoneyGold, "RIGHT", 30, 0 )
  api.SendMailMoneyCopperRight:SetPoint( "RIGHT", 10, 0 )
  do ({ api.SendMailMoneyCopper:GetRegions() })[ 9 ]:SetDrawLayer( "BORDER" ) end
  api.SendMailMoneyCopper:SetWidth( 28 )
  api.SendMailMoneyCopper:SetPoint( "LEFT", api.SendMailMoneySilver, "RIGHT", 20, 0 )
  api.SendMailSendMoneyButton:SetPoint( "TOPLEFT", api.SendMailMoney, "TOPRIGHT", 0, 12 )

  -- hack to avoid automatic subject setting and button disabling from weird blizzard code
  MailMailButton = api.SendMailMailButton
  api.SendMailMailButton = setmetatable( {}, { __index = function() return function() end end } )
  api.SendMailMailButton_OnClick = MailMailButton_OnClick
  MailSubjectEditBox = api.SendMailSubjectEditBox
  api.SendMailSubjectEditBox = setmetatable( {}, {
    __index = function( _, key )
      return function( _, ... )
        return MailSubjectEditBox[ key ]( MailSubjectEditBox, unpack( arg ) )
      end
    end,
  } )

  api.SendMailNameEditBox._SetText = api.SendMailNameEditBox.SetText
  function api.SendMailNameEditBox:SetText( ... )
    if not api.TurtleMail_To then
      return self:_SetText( unpack( arg ) )
    end
  end

  api.SendMailNameEditBox:SetScript( "OnShow", function()
    if api.TurtleMail_To then
      api.this:_SetText( api.TurtleMail_To )
    end
  end )
  api.SendMailNameEditBox:SetScript( "OnChar", function()
    api.TurtleMail_To = nil
    GetSuggestions()
  end )
  api.SendMailNameEditBox:SetScript( "OnTabPressed", function()
    if api.MailAutoCompleteBox:IsVisible() then
      if api.IsShiftKeyDown() then
        PreviousMatch()
      else
        NextMatch()
      end
    else
      MailSubjectEditBox:SetFocus()
    end
  end )
  api.SendMailNameEditBox:SetScript( "OnEnterPressed", function()
    if api.MailAutoCompleteBox:IsVisible() then
      api.MailAutoCompleteBox:Hide()
      this:HighlightText( 0, 0 )
    else
      MailSubjectEditBox:SetFocus()
    end
  end )
  api.SendMailNameEditBox:SetScript( "OnEscapePressed", function()
    if api.MailAutoCompleteBox:IsVisible() then
      api.MailAutoCompleteBox:Hide()
    else
      this:ClearFocus()
    end
  end )
  function api.SendMailNameEditBox.focusLoss()
    api.MailAutoCompleteBox:Hide()
  end

  api.SendMailCODAllButtonText:SetText( "  " .. L[ "All mails" ] )
  api.SendMailCODAllButton:SetScript( "OnClick", m.set_cod_text )

  do
    local orig_script = api.SendMailNameEditBox:GetScript( "OnTextChanged" )
    api.SendMailNameEditBox:SetScript( "OnTextChanged", function()
      local text = this:GetText()
      local formatted = string.gsub( string.lower( text ), "^%l", string.upper )
      if text ~= formatted then
        this:SetText( formatted )
      end
      return orig_script()
    end )
  end

  for _, editBox in { api.SendMailNameEditBox, api.SendMailSubjectEditBox } do
    editBox:SetScript( "OnEditFocusGained", function()
      this:HighlightText()
    end )
    editBox:SetScript( "OnEditFocusLost", function()
      (this.focusLoss or function() end)()
      this:HighlightText( 0, 0 )
    end )
    do
      local lastClick
      editBox:SetScript( "OnMouseDown", function()
        local x, y = api.GetCursorPosition()
        if lastClick and api.GetTime() - lastClick.t < .5 and x == lastClick.x and y == lastClick.y then
          this:SetScript( "OnUpdate", function()
            this:HighlightText()
            this:SetScript( "OnUpdate", nil )
          end )
        end
        lastClick = { t = api.GetTime(), x = x, y = y }
      end )
    end
  end
end

function SendMail_Attached( bag, slot )
  if not api.MailFrame:IsVisible() then return false end
  for i = 1, ATTACHMENTS_MAX do
    local btn = api[ "MailAttachment" .. i ]
    if btn.item and btn.item[ 1 ] == bag and btn.item[ 2 ] == slot then
      return true
    end
  end
  if SendMail_state then
    for _, attachment in SendMail_state.attachments do
      if attachment[ 1 ] == bag and attachment[ 2 ] == slot then
        return true
      end
    end
  end
end

function Mail.AttachmentButton_OnClick()
  local attachedItem = this.item
  local cursorItem = m.get_cursor_item()
  if SendMail_SetAttachment( cursorItem, this ) then
    if attachedItem then
      if arg1 == "LeftButton" then m.set_cursor_item( attachedItem ) end
      m.orig.PickupContainerItem( unpack( attachedItem ) )
      if arg1 ~= "LeftButton" then api.ClearCursor() end -- for the lock changed event
    end
  end
end

-- requires an item lock changed event for a proper update
function SendMail_SetAttachment( item, slot )
  if item and not SendMail_PickupMailable( item ) then
    api.ClearCursor()
    return
  elseif not slot then
    for i = 1, ATTACHMENTS_MAX do
      if not api[ "MailAttachment" .. i ].item then
        slot = api[ "MailAttachment" .. i ]
        break
      end
    end
  end
  if slot then
    if not (item or slot.item) then return true end
    slot.item = item
    api.ClearCursor()
    api.SendMailFrame_Update()
    return true
  end
end

function SendMail_PickupMailable( item )
  api.ClearCursor()
  m.orig.ClickSendMailItemButton()
  api.ClearCursor()
  m.orig.PickupContainerItem( unpack( item ) )
  m.orig.ClickSendMailItemButton()
  local mailable = api.GetSendMailItem() and true or false
  m.orig.ClickSendMailItemButton()
  return mailable
end

function SendMail_NumAttachments()
  local x = 0
  for i = 1, ATTACHMENTS_MAX do
    if api[ "MailAttachment" .. i ].item then
      x = x + 1
    end
  end
  return x
end

function SendMail_Attachments()
  local t = {}
  for i = 1, ATTACHMENTS_MAX do
    local btn = api[ "MailAttachment" .. i ]
    if btn.item then
      table.insert( t, btn.item )
    end
  end
  return t
end

function SendMail_Clear()
  local anyItem
  for i = 1, ATTACHMENTS_MAX do
    anyItem = anyItem or api[ "MailAttachment" .. i ].item
    api[ "MailAttachment" .. i ].item = nil
  end
  if anyItem then
    api.ClearCursor()
    api.PickupContainerItem( unpack( anyItem ) )
    api.ClearCursor()
  end
  MailMailButton:Disable()
  api.SendMailNameEditBox:SetText ""
  api.SendMailNameEditBox:SetFocus()
  MailSubjectEditBox:SetText ""
  api.SendMailBodyEditBox:SetText ""
  api.MoneyInputFrame_ResetMoney( api.SendMailMoney )
  api.SendMailRadioButton_OnClick( 1 )

  api.SendMailFrame_Update()
end

function SendMail_Send()
  local item = table.remove( SendMail_state.attachments, 1 )
  if item then
    api.ClearCursor()
    m.orig.ClickSendMailItemButton()
    api.ClearCursor()
    m.orig.PickupContainerItem( unpack( item ) )
    m.orig.ClickSendMailItemButton()

    if not api.GetSendMailItem() then
      api.DEFAULT_CHAT_FRAME:AddMessage( "|cffabd473TurtleMail|r: " .. api.ERROR_CAPS, 1, 0, 0 )
      return
    end
  end

  local amount = SendMail_state.money
  if amount > 0 then
    if not api.SendMailCODAllButton:GetChecked() then
      SendMail_state.money = 0
    end
    if SendMail_state.cod then
      api.SetSendMailCOD( amount )
    else
      SendMail_state.money = 0
      api.SetSendMailMoney( amount )
    end
  end

  local subject = SendMail_state.subject
  if subject == "" then
    if item then
      local itemName, itemTexture, stackCount, quality = api.GetSendMailItem()
      subject = itemName .. (stackCount > 1 and " (" .. stackCount .. ")" or "")
    else
      subject = "<" .. api.NO_ATTACHMENTS .. ">"
    end
  elseif SendMail_state.numMessages > 1 then
    subject = subject ..
        string.format( " [%d/%d]", SendMail_state.numMessages - getn( SendMail_state.attachments ),
          SendMail_state.numMessages )
  end

  api.SendMail( SendMail_state.to, subject, SendMail_state.body )

  if getn( SendMail_state.attachments ) == 0 then
    SendMail_sending = false
  end
end

do
  local inputLength
  local matches = {}
  local index

  local function complete()
    api.SendMailNameEditBox:SetText( matches[ index ] )
    api.SendMailNameEditBox:HighlightText( inputLength, -1 )
    for i = 1, api.MAIL_AUTOCOMPLETE_MAX_BUTTONS do
      local button = api[ "MailAutoCompleteButton" .. i ]
      if i == index then
        button:LockHighlight()
      else
        button:UnlockHighlight()
      end
    end
  end

  function PreviousMatch()
    if index then
      index = index > 1 and index - 1 or getn( matches )
      complete()
    end
  end

  function NextMatch()
    if index then
      ---@diagnostic disable-next-line: undefined-global
      index = mod( index, getn( matches ) ) + 1
      complete()
    end
  end

  function Mail.SelectMatch( i )
    index = i
    complete()
    api.MailAutoCompleteBox:Hide()
    api.SendMailNameEditBox:HighlightText( 0, 0 )
  end

  function GetSuggestions()
    local input = api.SendMailNameEditBox:GetText()
    inputLength = string.len( input )

    ---@diagnostic disable-next-line: undefined-field
    table.setn( matches, 0 )
    index = nil

    local autoCompleteNames = {}
    for name, time in api.TurtleMail_AutoCompleteNames[ api.GetCVar "realmName" .. "|" .. api.UnitFactionGroup "player" ] do
      table.insert( autoCompleteNames, { name = name, time = time } )
    end
    table.sort( autoCompleteNames, function( a, b ) return b.time < a.time end )

    local ignore = { [ api.UnitName "player" ] = true }
    local function process( name )
      if name then
        if not ignore[ name ] and string.find( string.upper( name ), string.upper( input ), nil, true ) == 1 then
          table.insert( matches, name )
        end
        ignore[ name ] = true
      end
    end
    for _, t in autoCompleteNames do
      process( t.name )
    end
    for i = 1, api.GetNumFriends() do
      process( api.GetFriendInfo( i ) )
    end
    for i = 1, api.GetNumGuildMembers( true ) do
      process( api.GetGuildRosterInfo( i ) )
    end

    ---@diagnostic disable-next-line: undefined-field
    table.setn( matches, math.min( getn( matches ), api.MAIL_AUTOCOMPLETE_MAX_BUTTONS ) )
    if getn( matches ) > 0 and (getn( matches ) > 1 or input ~= matches[ 1 ]) then
      for i = 1, api.MAIL_AUTOCOMPLETE_MAX_BUTTONS do
        local button = api[ "MailAutoCompleteButton" .. i ]
        if i <= getn( matches ) then
          button:SetText( matches[ i ] )
          button:GetFontString():SetPoint( "LEFT", button, "LEFT", 15, 0 )
          button:Show()
        else
          button:Hide()
        end
      end
      api.MailAutoCompleteBox:SetHeight( getn( matches ) * api.MailAutoCompleteButton1:GetHeight() + 35 )
      api.MailAutoCompleteBox:SetWidth( 120 )
      api.MailAutoCompleteBox:Show()
      index = 1
      complete()
    else
      api.MailAutoCompleteBox:Hide()
    end
  end
end

function Mail.dump( o )
  if not o then return "nil" end
  if type( o ) ~= 'table' then return tostring( o ) end

  local entries = 0
  local s = "{"

  for k, v in pairs( o ) do
    if (entries == 0) then s = s .. " " end
    local key = type( k ) ~= "number" and '"' .. k .. '"' or k
    if (entries > 0) then s = s .. ", " end
    s = s .. "[" .. key .. "] = " .. Mail.dump( v )
    entries = entries + 1
  end

  if (entries > 0) then s = s .. " " end
  return s .. "}"
end

function Mail.debug( m1, m2, m3 )
  if m.debug_enabled then
    local messages = ""
    for _, message in { m1, m2, m3 } do
      if message then
        messages = messages == "" and "" or messages .. ", "
        if type( message ) == 'table' then
          messages = messages .. Mail.dump( message )
        else
          messages = messages .. message
        end
      end
    end

    api.DEFAULT_CHAT_FRAME:AddMessage( string.format( "|cffabd473TurtleMail|r: %s", messages ) )
  end
end

Mail.init()
