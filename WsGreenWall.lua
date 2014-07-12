-----------------------------------------------------------------------------------------------
-- Client Lua Script for WsGreenWall
-- Copyright (c) NCsoft. All rights reserved
-----------------------------------------------------------------------------------------------
 
require "Window"
 
-----------------------------------------------------------------------------------------------
-- WsGreenWall Module Definition
-----------------------------------------------------------------------------------------------
local WsGreenWall = {} 
 
-----------------------------------------------------------------------------------------------
-- Constants
-----------------------------------------------------------------------------------------------

--
-- Debugging levels
--
local D_NONE = 0
local D_ERROR = 1
local D_WARNING = 2
local D_NOTICE = 3
local D_INFO = 4
local D_DEBUG = 5

--
-- Default configuration values
--
local defaultOptions = {
    bTag            = true,
    bAchievement    = false,
    bRoster         = true,
    bRank           = false,
    bOfficerChat    = false,
    DebugLevel      = D_NONE,
 }
 
 
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

		self.timer = ApolloTimer.Create(10.0, true, "OnTimer", self)

		-- Do additional Addon initialization here
	end
end

-----------------------------------------------------------------------------------------------
-- WsGreenWall Functions
-----------------------------------------------------------------------------------------------
-- Define general functions here

-- on SlashCommand "/greenwall"
function WsGreenWall:OnCli(cmdStr, argStr)
    self:OpenConfigForm()
end

-- on timer
function WsGreenWall:OnTimer()
	-- Do your timer-related stuff here.
end


-----------------------------------------------------------------------------------------------
-- WsGreenWallForm Functions
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
    
    self.wndMain:Invoke()
end

-- Toggle handling
function WsGreenWall:OnToggleOption(handler, control)
    local name = control:GetName()
    local index = string.gsub(name, "ToggleOption(%w+)", "b%1")
    Print('name: ' .. name .. ', index: ' .. index)
    
    self.scratch[index] = not self.scratch[index]
    self.wndMain:FindChild(name):SetCheck(self.scratch[index])
end

function WsGreenWall:OnToggleOptionAchievement()
    if self.scratch.bAchievement then
        self.scratch.bAchievement = false
    else
        self.scratch.bAchievement = true
    end
    self.wndMain:FindChild("ToggleOptionAchievement"):SetCheck(self.scratch.bAchievement)
end

function WsGreenWall:OnToggleOptionRoster()
    if self.scratch.bRoster then
        self.scratch.bRoster = false
    else
        self.scratch.bRoster = true
    end
    self.wndMain:FindChild("ToggleOptionRoster"):SetCheck(self.scratch.bRoster)
end

function WsGreenWall:OnToggleOptionRank()
    if self.scratch.bRank then
        self.scratch.bRank = false
    else
        self.scratch.bRank = true
    end
    self.wndMain:FindChild("ToggleOptionRank"):SetCheck(self.scratch.bRank)
end

function WsGreenWall:OnToggleOptionOfficerChat()
    if self.scratch.bOfficerChat then
        self.scratch.bOfficerChat = false
    else
        self.scratch.bOfficerChat = true
    end
    self.wndMain:FindChild("ToggleOptionOfficerChat"):SetCheck(self.scratch.bOfficerChat)
end

-- when the OK button is clicked
function WsGreenWall:OnOK()
    -- save the new config set
    for k, v in pairs(self.scratch) do
        self.options[k] = v
    end

	self.wndMain:Close() -- hide the window
end

-- when the Cancel button is clicked
function WsGreenWall:OnCancel()
	self.wndMain:Close() -- hide the window
end


-----------------------------------------------------------------------------------------------
-- WsGreenWall Instance
-----------------------------------------------------------------------------------------------
local WsGreenWallInst = WsGreenWall:new()
WsGreenWallInst:Init()
