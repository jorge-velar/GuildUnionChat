# GuildUnion

**Unite several guilds into one big community.** Everyone talks in a shared guild chat as if it were a single guild, while each guild keeps its own ranks, officers and rules.

Built for **WoW Forever**. Available in **English and Spanish** (it follows your game language).

> **Beta:** the addon is being tested with real guilds right now. If something breaks, type `/gu errors` and send the text.

## Install

Copy the `GuildUnion` folder into `World of Warcraft\_forever_\Interface\AddOns\` so that you end up with `AddOns\GuildUnion\GuildUnion.toc`, then restart the game. Or install it from CurseForge.

## Features

- **Shared guild chat** – what you write in /g reaches every guild of the community, with the guild tag in front: `<TAG> [Name]: message`.
- **Inside Blizzard's guild window** – messages from the other guilds appear in the Guild & Communities chat, and GuildUnion adds its own tab there.
- **Officers online** – see the online guild masters and officers of every guild.
- **Chat history (30 days)** – officers can search the chat by player or text and open the conversation around any message.
- **Moderation** – officers can mute players across the whole community, with a reason and a duration.
- **Pinned message** – officers can pin a message at the top of the guild chat.
- **Chat tabs** – Guild, Group Finder and Officers tabs are created automatically, and each tab keeps writing to its own chat.
- **Group finder across guilds** – `/buscargrupo message` posts to every guild at once.
- **Protected channel** – the community uses a hidden, password-protected channel; outsiders are detected and removed. The password is never shown in chat.

## Setup (guild masters, once)

1. In the **Guild Information** of **every** guild, add one line per guild (the same lines in all guilds):

       GU:t:Community Name
       GU:g:Exact Guild Name One:TAG1
       GU:g:Exact Guild Name Two:TAG2

2. In the **officer note** of the guild master of **each** guild, add the channel and its password (letters and numbers only, up to 26 characters for the channel):

       GU:c:Channel:password

3. Done. Officers read the channel from the note; everyone else gets it automatically from a guildmate who already has it.

## Commands

- `/gu` – open or close the GuildUnion tab (the guild window must be open)
- `/gu status` – connection status (channel, links, other guilds)
- `/gu sendchannel Name` – send the channel to someone who is waiting for it (the password is not shown)
- `/gu confirm TAG` – officers: trust the member list received from another guild
- `/gu pin text` – officers: pin a message (`/gu pin clear` to remove it)
- `/gu language en` / `/gu language es` – change the language
- `/gu errors` – show and copy the addon errors
- `/buscargrupo message` – post in the Group Finder of every guild

The minimap button opens the GuildUnion tab; **J** opens the guild window as usual.

## For developers

- `ARCHITECTURE.md` explains how the addon works inside (in Spanish).
- `LEEME.md` is the full user manual (in Spanish).

## License

MIT – see `LICENSE.txt`. Libraries in `Libs` keep their own licenses.
