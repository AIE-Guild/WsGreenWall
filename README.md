WsGreenWall
===========

Guild chat bridging for WildStar.

Distribution
------------

This WildStar addon is currently available on [GitHub](https://github.com).

[https://github.com/AIE-Guild/WsGreenWall](https://github.com/AIE-Guild/WsGreenWall)


Installation
------------

1. Copy the files into the following directory.

    %APPDATA%\NCSOFT\WildStar\Addons\WsGreenWall

2. Start the WildStar client.

3. Run the command `/greenwall` or `/gw` to bring up the configuration window.


Configuration
-------------

WsGreenWall is designed to require minimal configuration.  Only the guild officers are required to do any configuration to get the addon to work properly.

The required configuration for the "confederation" of guilds is a single line in the Additional Info section of the Guild tab in the Social window.  The line should be of the following format.

    GWc:<confederation>:<guild_tag>:<channel_name>:<encryption_key>

The elements are as follows:

- confederation -- The name of the confederation of guilds, this much match in all guild configurations.
- guild_tag -- A short nickname for the guild that will be prepended to messages shown in other confederation guilds when tagging is enabled.
- channel_name -- The name of the hidden channel used to transport messages between confederation guilds.
- encryption_key -- An optional key to be used for encrypting messages between confederation guilds.  **This is currently not implemented.**

Example:

    GWc:Blue Sun:AIE:BlueSunBridge:
