--[[-------------------------------------------------------------------------------------------

WsGreenWall -- Guild chat bridging for WildStar.

The MIT License (MIT)

Copyright (c) 2014 Mark Rogaski

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

--]]-------------------------------------------------------------------------------------------
 
-----------------------------------------------------------------------------------------------
-- System libraries
-----------------------------------------------------------------------------------------------
require "Window"
require "os"

-----------------------------------------------------------------------------------------------
-- Included libraries
-----------------------------------------------------------------------------------------------
local Salsa20 = nil
 
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

local function DeepCopy(orig)
    local orig_type = type(orig)
    local copy
    if orig_type == 'table' then
        copy = {}
        for orig_key, orig_value in next, orig, nil do
            copy[DeepCopy(orig_key)] = DeepCopy(orig_value)
        end
        setmetatable(copy, DeepCopy(getmetatable(orig)))
    else -- number, string, boolean, etc
        copy = orig
    end
    return copy
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
    self.ready          = false
    self.player         = nil
    self.guild          = nil
    self.confederation  = nil
    self.guild_tag      = nil
    self.channel = {}
    self.channel[CHAN_GUILD] = {
        desc    = "Guild",
        name    = "",
        handle  = nil,
        encrypt = false,
        key     = nil,
        ts      = 0,
        ctr     = 0,
        queue   = {},
        target  = nil,
    }
    self.channel[CHAN_OFFICER] = {
        desc    = "GuildOfficer",
        name    = "",
        handle  = nil,
        encrypt = false,
        key     = nil,
        ts      = 0,
        ctr     = 0,
        queue   = {},
        target  = nil,
    }

    return o
end

function WsGreenWall:Init()
	local bHasConfigureFunction = false
	local strConfigureButtonText = ""
	local tDependencies = {
		"Crypto:Salsa20-1.0",
	}
    Apollo.RegisterAddon(self, bHasConfigureFunction, strConfigureButtonText, tDependencies)
end
 

-----------------------------------------------------------------------------------------------
-- WsGreenWall OnLoad
-----------------------------------------------------------------------------------------------
function WsGreenWall:OnLoad()
    -- load libraries
    Salsa20 = Apollo.GetPackage("Crypto:Salsa20-1.0").tPackage
    
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

        -- Start the timer
		self.timer = ApolloTimer.Create(1.0, true, "OnTimer", self)

		-- Do additional Addon initialization here
	    self.channel[CHAN_GUILD].target   = GetChannel(ChatSystemLib.ChatChannel_Guild)
        self.channel[CHAN_OFFICER].target = GetChannel(ChatSystemLib.ChatChannel_GuildOfficer)
	end
end


-----------------------------------------------------------------------------------------------
-- Configuration
-----------------------------------------------------------------------------------------------
function WsGreenWall:GetGuildConfiguration()
    assert(self.player ~= nil)
    
    -- Check guild membership
    if self.guild == nil then
        for _, guild in pairs(GuildLib.GetGuilds()) do
            if guild:GetType() == GuildLib.GuildType_Guild then
                self.guild = guild
                self:Debug("guild = " .. guild:GetName())
            end
        end
    end
    
    if self.guild == nil then
        self.timer:Stop()
    else
        local text = self.guild:GetInfoMessage()
        local chanName, chanKey
        self.confederation, self.guild_tag, chanName, chanKey = self:ParseInfoMessage(text)
        if self.confederation ~= nil and chanName ~= nil then
            if self.guild_tag == nil then
                self.guild_tag = self.guild:GetName()
            end
            self:Debug("confederation = " .. self.confederation)
            self:Debug("guild_tag = " .. self.guild_tag)

            self:ChannelConnect(CHAN_GUILD, chanName, chanKey)

            -- Configuration is complete
            self.ready = true
            self.timer:Stop()
        end 
    end

end

function WsGreenWall:ParseInfoMessage(text)
    local conf, tag, chan, key
    conf, chan, tag = string.match(text, "GWc:([%w _-]+):([%w_-]+):([%w _-]*):")
    if conf ~= nil then
        key = string.match(text, "GWe:([^:]+)")        
    end
    return conf, tag, chan, key
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
    if self.player == nil then
        self.player = GameLib.GetPlayerUnit()
        if self.player ~= nil then
            self:Debug("player = " .. self.player:GetName())
            self:GetGuildConfiguration()
        end
    elseif not self.ready then
        self:GetGuildConfiguration()
    else
        self.timer:Stop()
    end
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


-----------------------------------------------------------------------------------------------
-- Event Handlers
-----------------------------------------------------------------------------------------------

function WsGreenWall:OnGuildInfoMessageUpdate(guild)
    self:GetGuildConfiguration()
end

function WsGreenWall:OnBridgeMessage(channel, tBundle, strSender)
    if tBundle.confederation == self.confederation and tBundle.guild ~= self.guild then
        local chanId = tBundle.type
        if type(self.channel[chanId]) ~= nil then
            self:Debug(string.format("%s.Rx(%s, %s, %s)", 
                    self.channel[chanId].desc,
                    tBundle.confederation,
                    tBundle.guild_tag,
                    tBundle.message.arMessageSegments[1].strText))
            if tBundle.guild_tag ~= self.guild_tag then
                -- Generate and event for the received chat message.
                local message = tBundle.message
                if self.options.bTag then
                    message = self:TagMessage(message, tBundle.guild_tag)
                end
                Event_FireGenericEvent("ChatMessage", self.channel[chanId].target, message)
            end
        end
    end
end

function WsGreenWall:OnChatMessage(channel, tMsg)
    local chanName = channel:GetName()
    local chanType = channel:GetType()
    if chanType == ChatSystemLib.ChatChannel_Guild or 
            chanType == ChatSystemLib.ChatChannel_GuildOfficer then
        if tMsg.bSelf and tMsg.strSender == self.player:GetName() then
            local chanId = ChanType2Id(chanType)
            self:ChannelEnqueue(chanId, tMsg)
            self:Debug(string.format("%s.queue(%s)", 
                    self.channel[chanId].desc,  tMsg.arMessageSegments[1].strText))
            self:ChannelFlush(chanId)
        end
    end
end


-----------------------------------------------------------------------------------------------
-- Translation
-----------------------------------------------------------------------------------------------

function WsGreenWall:TransmogrifyMessage(tMessage, f)
    local clone = DeepCopy(tMessage)
    for k, v in pairs(clone) do
        if k == "arMessageSegments" then
            local t = {}
            for i, segment in ipairs(v) do
                t[i] = segment.strText
            end
            t = f(t)
            for i, segment in ipairs(v) do
                segment.strText = t[i]
            end
        end
    end
    return clone
end

function WsGreenWall:TagMessage(tMessage, tag)
    local function AddTag(x)
        local z = {}
        for i, s in ipairs(x) do
            z[i] = string.format("<%s> %s", tag, s)
        end
        return z
    end
    
    return self:TransmogrifyMessage(tMessage, AddTag)
end

function WsGreenWall:GenerateNonce()
    local timestamp = os.time()
    local counter   = 0
    if self.channel[chanId].ts < timestamp then
        self.channel[chanId].ts  = timestamp
        self.channel[chanId].ctr = 0
    else
        timestamp = self.channel[chanId].ts
        counter = self.channel[chanId].ctr + 1
        self.channel[chanId].ctr = counter
    end
    return bit32.lrotate(bit32.band(self.channel[chanId].id, 0xFFFFFFFF), 32) +
           bit32.lrotate(bit32.band(timestamp, 0xFFFFFFF), 4) +
           bit32.band(counter, 0xF)
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
        if key ~= nil then
            self.channel[id].encrypt = true
            self.channel[id].key     = string.sub(string.rep(key, math.ceil(32 / string.len(key))), 1, 32)
            self.channel[id].nstate  = { 
                id  = GameLib:GetPlayerUnit():GetId(),
                ts  = 0,
                ctr = 0,
            }
        else
            self.channel[id].encrypt = false
            self.channel[id].key     = nil
            self.channel[id].nstate  = nil
        end
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
    if self.channel[id].handle ~= nil then
        if table.getn(self.channel[id].queue) > 0 then
            self:Debug(string.format("flushing channel %d (%d)",
                       id, table.getn(self.channel[id].queue)))
            while table.getn(self.channel[id].queue) > 0 do
                local message = self:ChannelDequeue(id)
                local tBundle = {
                    confederation   = self.confederation,
                    guild           = self.guild,
                    guild_tag       = self.guild_tag,
                    type            = id,
                    encrypted       = false,
                    nonce           = nil,
                    message         = message,
                }
                self.channel[id].handle:SendMessage(tBundle)
                self:Debug(string.format("%s.Tx(%s, %s, %s)",
                        self.channel[id].desc,
                        tBundle.confederation,
                        tBundle.guild_tag,
                        message.arMessageSegments[1].strText))
            end
            self:Debug(string.format("channel %d queue empty", id))
        end            
    end
end


-----------------------------------------------------------------------------------------------
-- WsGreenWall Instance
-----------------------------------------------------------------------------------------------

local WsGreenWallInst = WsGreenWall:new()
WsGreenWallInst:Init()

