WsGreenWall
===========

Guild chat bridging for WildStar.

Distribution
------------

This WildStar addon is currently available on GitHub.

[https://github.com/AIE-Guild/WsGreenWall](https://github.com/AIE-Guild/WsGreenWall)


Glossary
--------

- **Bridge** - The communication channel which is used to pass chat messages between co-guilds.  This is not visible to the users.
- **Cipher** - An algorithm which is used to encrypt and decrypt messages.
- **Co-Guild** - A guild which belongs to the confederation.
- **Confederation** - A collection of guilds which share a common guild chat.
- **Tag** - A short nickname for a co-guild that may be displayed when a message is displayed from a member of that co-guild.


Installation
------------

1. Copy the files into the following directory.

    %APPDATA%\NCSOFT\WildStar\Addons\WsGreenWall

2. Start the WildStar client.

3. Run the command `/greenwall` or `/gw` to bring up the configuration window.


Configuration
-------------

WsGreenWall is designed to require minimal configuration. *The configuration below only needs to be done by guild officers to build a confederation of guilds.*

The configuration commands are placed in the Additional Info section of the Guild tab in the Social window.

### Confederation (Required)

#### Syntax

    GWc="<confederation_name>|<channel_name>|<guild_tag>"

- *confederation_name* -- This is an identifier for the confederation.  It may include any printable character other than double quotes of the "|" character.
- *channel_name* -- This is the name of the channel used for guild chat bridging. It may include letters, numbers, dashes, and underscores.
- *guild_tag* -- [Optional] This specifies a short nickname for the guild which will show up when members of other co-guilds in the confederation enable tagging. It may include any printable character other than double quotes of the "|" character.

#### Examples

    GWc="Blue Sun|bsc38839"
    GWc="Weyland Yutani|wyGChat|public_relations"


### Security (Optional)

#### Syntax

    GWs="<encryption_key>"

- *encryption_key* -- This is a text string that will be used as a key for encrypted communications between co-guilds. It may include any printable character other than double quotes of the "|" character.
 
#### Example

    GWs="gears coal herb carriage"


