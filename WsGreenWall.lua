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
local SHA256 = nil
 
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

local function Str2Hex(s)
    local h = string.gsub(s, ".", function (c) return string.format("%02x", string.byte(c)) end)
    return h
end

local function Num2Str(x, n)
    local s = ""
    for i = 1, n do
        local rem = x % 256
        s = string.char(rem) .. s
        x = (x - rem) / 256
    end
    return s
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

function WsGreenWall:DebugBundle(tBundle, rx)
    self:Debug(string.format("%s(%d) %s/%s encrypted=%s nonce=%s",
            rx and "Rx" or "Tx",
            tBundle.type,
            tBundle.confederation,
            tBundle.guild_tag,
            tBundle.encrypted and "true" or "false",
            tBundle.nonce == nil and "" or Str2Hex(tBundle.nonce)
        ))
    for _, segment in ipairs(tBundle.message.arMessageSegments) do
        self:Debug(string.format(" => %s", string.gsub(segment.strText, "[^%g ]", ".")))
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
		"Crypto:Cipher:Salsa20-1.0",
		"Crypto:Hash:SHA256-1.0"
	}
    Apollo.RegisterAddon(self, bHasConfigureFunction, strConfigureButtonText, tDependencies)
end
 

-----------------------------------------------------------------------------------------------
-- WsGreenWall OnLoad
-----------------------------------------------------------------------------------------------
function WsGreenWall:OnLoad()
    -- load libraries
    Salsa20 = Apollo.GetPackage("Crypto:Cipher:Salsa20-1.0").tPackage
    SHA256 = Apollo.GetPackage("Crypto:Hash:SHA256-1.0").tPackage
    
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
        local conf = self:ParseInfoMessage(text)
        if conf.confederation and conf.channel then
            self.confederation = conf.confederation
            if conf.guild_tag then
                self.guild_tag = conf.guild_tag
            else
                self.guild_tag = self.guild:GetName()
            end
            self:Debug("confederation = " .. self.confederation)
            self:Debug("guild_tag = " .. self.guild_tag)

            self:ChannelConnect(CHAN_GUILD, conf.channel, conf.key)

            -- Configuration is complete
            self.ready = true
            self.timer:Stop()
        end 
    end

end

function WsGreenWall:ParseInfoMessage(text)
    local conf = {}
    for _, op in ipairs({"c", "s"}) do
        local argstr = string.match(text, "GW" .. op .. "%[([^%[%]]+)%]")
        if argstr then
            local arg = {}
            for token in string.gmatch(argstr, "[^|]+") do
                table.insert(arg, token)
            end
            if op == "c" then
                conf.confederation = arg[1]
                conf.channel = arg[2]
                conf.guild_tag = arg[3]
            elseif op == "s" then
                conf.key = arg[1] and SHA256.hash(arg[1])
            end
        end
    end
    return conf
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
    self:DebugBundle(tBundle)
    if tBundle.confederation == self.confederation and tBundle.guild ~= self.guild then
        local chanId = tBundle.type
        if type(self.channel[chanId]) ~= nil then
            if tBundle.guild_tag ~= self.guild_tag then
                -- Process the recieved chat message.
                local message = tBundle.message
                if tBundle.encrypted then
                    message = self:DecryptMessage(message, self.channel[chanId].key, tBundle.nonce)
                end
                
                if self.options.bTag then
                    message = self:TagMessage(message, tBundle.guild_tag)
                end

                -- Generate an event for the received chat message.
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

function WsGreenWall:GenerateNonce(chanId)
    local timestamp = os.time()
    local counter   = 0
    if self.channel[chanId].n.ts < timestamp then
        self.channel[chanId].n.ts  = timestamp
        self.channel[chanId].n.ctr = 0
    else
        timestamp = self.channel[chanId].n.ts
        counter = self.channel[chanId].n.ctr + 1
        self.channel[chanId].n.ctr = counter
    end
    local nonce = Num2Str(self.channel[chanId].n.id, 4)
    nonce = nonce .. Num2Str(timestamp, 3)
    nonce = nonce .. Num2Str(counter, 1)
    return nonce
end

function WsGreenWall:EncryptMessage(tMessage, key, nonce)
    local function f(t)
        return Salsa20.encrypt_table(key, nonce, t, 8) 
    end
    return self:TransmogrifyMessage(tMessage, f)
end

function WsGreenWall:DecryptMessage(tMessage, key, nonce)
    local function f(t)
        return Salsa20.decrypt_table(key, nonce, t, 8) 
    end
    return self:TransmogrifyMessage(tMessage, f)
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
            self.channel[id].key     = key
            self.channel[id].n = { 
                id  = GameLib:GetPlayerUnit():GetId(),
                ts  = 0,
                ctr = 0,
            }
            self:Debug(string.format("connected to bridge channel: %s, key: %s", name, Str2Hex(key)))
        else
            self.channel[id].encrypt = false
            self.channel[id].key     = nil
            self.channel[id].nstate  = nil
            self:Debug(string.format("connected to bridge channel: %s", name))
        end
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

                if self.channel[id].encrypt then
                    local nonce = self:GenerateNonce(id)
                    tBundle.message = self:EncryptMessage(message, self.channel[id].key, nonce)
                    tBundle.nonce = nonce
                    tBundle.encrypted = true
                end

                self.channel[id].handle:SendMessage(tBundle)

                self:DebugBundle(tBundle, false)
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

