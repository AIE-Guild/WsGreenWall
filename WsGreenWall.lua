-----------------------------------------------------------------------------------------------
-- WsGreenWall -- Guild chat bridging for WildStar.
-- Copyright (C) 2014  Mark Rogaski
-- 
-- This program is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.
-- 
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.
-- 
-- You should have received a copy of the GNU General Public License
-- along with this program.  If not, see <http://www.gnu.org/licenses/>
-----------------------------------------------------------------------------------------------
 
require "Window"
require "os"
 
-----------------------------------------------------------------------------------------------
-- WsGreenWall Module Definition
-----------------------------------------------------------------------------------------------
local WsGreenWall = {} 
 
-----------------------------------------------------------------------------------------------
-- Constants
-----------------------------------------------------------------------------------------------

local CHAN_GUILD    = 1
local CHAN_OFFICER  = 2

--
-- Default configuration values
--
local defaultOptions = {
    bTag            = true,
    bAchievement    = false,
    bRoster         = true,
    bRank           = false,
    bOfficerChat    = false,
    bDebug          = false,
}

 
-----------------------------------------------------------------------------------------------
-- Utility Functions
-----------------------------------------------------------------------------------------------

local function ChanType2Id(chanType)
    if chanType == ChatSystemLib.ChatChannel_Guild then
        return CHAN_GUILD
    elseif chanType == ChatSystemLib.ChatChannel_GuildOfficer then
        return CHAN_OFFICER
    end
    return
end

local function GetChannel(chanType)
    for _, v in pairs(ChatSystemLib.GetChannels()) do
        if v:GetType() == chanType then
            return v
        end
    end            
end


-----------------------------------------------------------------------------------------------
-- Initialization
-----------------------------------------------------------------------------------------------
function WsGreenWall:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self 

    -- initialize variables here
    self.options = {}
    for k, v in pairs(defaultOptions) do
        self.options[k] = v
    end 
    self.player         = nil
    self.guild          = nil
    self.confederation  = ""
    self.guild_tag      = ""
    self.channel = {}
    self.channel[CHAN_GUILD] = {
        desc    = "Guild",
        name    = "",
        handle  = nil,
        key     = nil,
        queue   = {},
        target  = nil,
    }
    self.channel[CHAN_OFFICER] = {
        desc    = "GuildOfficer",
        name    = "",
        handle  = nil,
        key     = nil,
        queue   = {},
        target  = nil,
    }

    return o
end

function WsGreenWall:Init()
	local bHasConfigureFunction = false
	local strConfigureButtonText = ""
	local tDependencies = {
		-- "UnitOrPackageName",
	}
    Apollo.RegisterAddon(self, bHasConfigureFunction, strConfigureButtonText, tDependencies)
end
 

-----------------------------------------------------------------------------------------------
-- WsGreenWall OnLoad
-----------------------------------------------------------------------------------------------
function WsGreenWall:OnLoad()
    -- load our form file
	self.xmlDoc = XmlDoc.CreateFromFile("WsGreenWall.xml")
	self.xmlDoc:RegisterCallback("OnDocLoaded", self)
end

-----------------------------------------------------------------------------------------------
-- WsGreenWall OnDocLoaded
-----------------------------------------------------------------------------------------------
function WsGreenWall:OnDocLoaded()

	if self.xmlDoc ~= nil and self.xmlDoc:IsLoaded() then
	    self.wndMain = Apollo.LoadForm(self.xmlDoc, "WsGreenWallForm", nil, self)
		if self.wndMain == nil then
			Apollo.AddAddonErrorText(self, "Could not load the main window for some reason.")
			return
		end
		
	    self.wndMain:Show(false, true)

		-- if the xmlDoc is no longer needed, you should set it to nil
		-- self.xmlDoc = nil
		
		-- Register handlers for events, slash commands and timer, etc.
		-- e.g. Apollo.RegisterEventHandler("KeyDown", "OnKeyDown", self)
		Apollo.RegisterSlashCommand("greenwall", "OnCli", self)
        Apollo.RegisterSlashCommand("gw", "OnCli", self)
        
        -- Register event handlers
        Apollo.RegisterEventHandler("GuildInfoMessage", "OnGuildInfoMessageUpdate", self)
        Apollo.RegisterEventHandler("ChatMessage", "OnChatMessage", self)

		-- self.timer = ApolloTimer.Create(10.0, true, "OnTimer", self)

		-- Do additional Addon initialization here
		self.player = GameLib.GetPlayerUnit()
		self:Debug("player = " .. self.player:GetName())
		for _, g in pairs(GuildLib.GetGuilds()) do
            if g:GetType() == GuildLib.GuildType_Guild then
		        self.guild = g
                self:Debug("guild = " .. self.guild:GetName())
		        self:GetGuildConfiguration(g:GetInfoMessage())
		    end
	    end
	    self.channel[CHAN_GUILD].target   = GetChannel(ChatSystemLib.ChatChannel_Guild)
        self.channel[CHAN_OFFICER].target = GetChannel(ChatSystemLib.ChatChannel_GuildOfficer)
	end
end

-----------------------------------------------------------------------------------------------
-- WsGreenWall Functions
------------------------------------o-----------------------------------------------------------
-- Define general functions here

-- on SlashCommand "/greenwall"
function WsGreenWall:OnCli(cmdStr, argStr)
    self:OpenConfigForm()
end

-- on timer
function WsGreenWall:OnTimer()
	-- Do your timer-related stuff here.
end

--
-- Configuration storage and loading
--
function WsGreenWall:OnSave(eLevel)
    if eLevel == GameLib.CodeEnumAddonSaveLevel.Character then
        local buffer = {}
        buffer.options = {}
        for k, v in pairs(self.options) do
            buffer.options[k] = v
        end
        return buffer
    end
end

function WsGreenWall:OnRestore(eLevel, buffer)
    local options = buffer.options
    if options ~= nil and type(options) == "table" then
        for k, v in pairs(options) do
            self.options[k] = v
        end
    end
end

function WsGreenWall:Debug(text, force)
    if force == nil then
        force = false
    end
    if text == nil then
        text = ""
    end
    if self.options.bDebug or force then
        Print("GreenWall: " .. text)
    end
end


-----------------------------------------------------------------------------------------------
-- Event Handlers
-----------------------------------------------------------------------------------------------

function WsGreenWall:OnGuildInfoMessageUpdate(guild)
    local text = guild:GetInfoMessage()
    self:GetGuildConfiguration(text)
end

function WsGreenWall:OnBridgeMessage(channel, tBundle, strSender)
    if tBundle.confederation == self.confederation and tBundle.guild ~= self.guild then
        local chanId = ChanType2Id(channel:GetType())
        self:Debug(string.format("%s.Rx(%s)", self.channel[chanId].desc, tBundle.message.strMsg))
        
        if self.options.tag then
            tBundle.message.strMsg = string.format("<%s> %s", tBundle.guild_tag, tBundle.message.strMsg)
        end
        
        -- Generate and event for the received chat message.
        Event_FireGenericEvent("ChatMessage", self.channel[chanId].target, tBundle.message.strMsg)
    end
end

function WsGreenWall:OnChatMessage(channel, tMsg)
    local chanName = channel:GetName()
    local chanType = channel:GetType()
    if chanType == ChatSystemLib.ChatChannel_Guild or 
            chanType == ChatSystemLib.ChatChannel_GuildOfficer then
        if tMsg.bSelf then
            local chanId = ChanType2Id(chanType)
            self:ChannelEnqueue(chanId, tMsg)
            self:Debug(string.format("%s.queue(%s)", 
                    self.channel[chanId].desc,  tMsg.arMessageSegments[1].strText))
            self:ChannelFlush(chanId)
        end
    end
end

-----------------------------------------------------------------------------------------------
-- Confederation Configuration
-----------------------------------------------------------------------------------------------

function WsGreenWall:GetGuildConfiguration(text)
    local str, conf, tag, chan_name, chan_key = string.match(text, "(GW:([%w _-]+):([%w _-]*):([%w_-]+):([%w_-]*))")
    if str ~= nil then
        self:Debug(string.format("loaded guild configuration; confederation: %s, tag: %s, channel: %s, key: %s",
                conf, tag, chan_name, chan_key))
        self.confederation  = conf
        self.guild_tag      = tag
        self:ChannelConnect(CHAN_GUILD, chan_name, chan_key)
    end
end


-----------------------------------------------------------------------------------------------
-- User Configuration
-----------------------------------------------------------------------------------------------

function WsGreenWall:OpenConfigForm()
    -- populate the configuration scratch pad
    self.scratch = {}
    for k, v in pairs(self.options) do
        self.scratch[k] = v
    end
    
    -- update the configuration form
    self.wndMain:FindChild("ToggleOptionTag"):SetCheck(self.scratch.bTag)
    self.wndMain:FindChild("ToggleOptionAchievement"):SetCheck(self.scratch.bAchievement)
    self.wndMain:FindChild("ToggleOptionRoster"):SetCheck(self.scratch.bRoster)
    self.wndMain:FindChild("ToggleOptionRank"):SetCheck(self.scratch.bRank)
    self.wndMain:FindChild("ToggleOptionOfficerChat"):SetCheck(self.scratch.bOfficerChat)
    self.wndMain:FindChild("ToggleOptionDebug"):SetCheck(self.scratch.bDebug)
    
    -- Future features
    self.wndMain:FindChild("ToggleOptionAchievement"):Enable(false)
    self.wndMain:FindChild("ToggleOptionRoster"):Enable(false)
    self.wndMain:FindChild("ToggleOptionRank"):Enable(false)
        
    self.wndMain:Invoke()
end

-- Toggle handling
function WsGreenWall:OnToggleOption(handler, control)
    local name = control:GetName()
    local index = string.gsub(name, "ToggleOption(%w+)", "b%1")
    self.scratch[index] = not self.scratch[index]
    self.wndMain:FindChild(name):SetCheck(self.scratch[index])
end

-- when the OK button is clicked
function WsGreenWall:OnOK()
    -- save the new config set
    for k, v in pairs(self.scratch) do
        self.options[k] = v
    end

    self:Debug("updated configuration")

	self.wndMain:Close() -- hide the window
end

-- when the Cancel button is clicked
function WsGreenWall:OnCancel()
	self.wndMain:Close() -- hide the window
end


-----------------------------------------------------------------------------------------------
-- Chat Channel Functions
-----------------------------------------------------------------------------------------------

function WsGreenWall:ChannelConnect(id, name, key)
    local handle = ICCommLib.JoinChannel(name, "OnBridgeMessage", self)
    
    if handle == nil then
        self:Debug(string.format("ERROR - cannot connect to bridge channel: %s", name))
    else
        self.channel[id].name   = name
        self.channel[id].handle = handle
        self.channel[id].key    = key
        self:Debug(string.format("connected to bridge channel: %s", name))
    end    
end

function WsGreenWall:ChannelEnqueue(id, data)
    table.insert(self.channel[id].queue, data)
end

function WsGreenWall:ChannelDequeue(id)
    if table.getn(self.channel[id].queue) > 0 then
        return table.remove(self.channel[id].queue, 1)
    end
end

function WsGreenWall:ChannelFlush(id)
    self:Debug(string.format("flushing channel %d", id))
    if self.channel[id].handle ~= nil then
        while table.getn(self.channel[id].queue) > 0 do
            local tMsg = self:ChannelDequeue(id)
            local tBundle = {
                confederation   = self.confederation,
                guild           = self.guild,
                guild_tag       = self.guild_tag,
                encrypted       = false,
                nonce           = nil,
                message         = tMsg,
            }
            self.channel[id].handle:SendMessage(tBundle)
            self:Debug(string.format("%s.Tx(%s)",
                    self.channel[id].desc, tMsg.arMessageSegments[1].strText))
        end            
    end
end


-----------------------------------------------------------------------------------------------
-- WsGreenWall Instance
-----------------------------------------------------------------------------------------------

local WsGreenWallInst = WsGreenWall:new()
WsGreenWallInst:Init()

