# Quasar
A library for creating "virtual" Minecraft servers in Lua.  
Supports Minecraft 1.21.7/8 (protocol 772). If you wish to support clients of other (older) versions, use a proxy in front of the server.

Currently in development, not ready for normal usage.

# Features
- Players joining & seeing eachother
- Chunk loading from region files
- Block breaking/placing, persistent through client chunks unloading
- Authentication/Encryption, player skins & skin layers
- Player animations (arm swing, shifting)
- Entities spawnable
- Multiple dimensions & players able to travel between them
- Vanilla Registry data, incl. block states, items, packets, etc.

# Planned features
- Chunk generation (very simple terrain) (in progress)
- Survival block breaking
- Helper for block placing from items (item id & facing -> blockstate)
- Item GUIs
- [Dialogs](https://minecraft.wiki/w/Dialog)
  - Lua state inspector using dialogs
- Command syntax tree
- Removing Copas (and thus LuaSec) dependency (perhaps it remains as an option?)

## back burner planned features
- Chunk saving?
- Actual inventories (with items)
  - Survival inventory support (moving items)
  - Chest/external inventories (moving items within & between)
  - Creative inventory support
- Entity behavior framework (easier control of entity movement, animations, interactions)
- Optional implementation of performance-critical components in C (Connection, Chunk, NBT?, Anvil?)
- Dimensions in their own threads w/ Lua Lanes or similar (optional)
- Dimensions distributed across multiple physical computers? (perhaps best left to proxy software & just transferring the player)

# Dependencies
- [Copas](https://lunarmodules.github.io/copas/index.html)
- [LuaSocket](https://lunarmodules.github.io/luasocket/index.html)
- [Lua OpenSSL](https://25thandclement.com/~william/projects/luaossl.html)
```sh
luarocks install luasocket
luarocks install copas
luarocks install luaossl
```

# License
Copyright © Penguin_Spy 2024-2025  

This Source Code Form is subject to the terms of the Mozilla Public
License, v. 2.0. If a copy of the MPL was not distributed with this
file, You can obtain one at https://mozilla.org/MPL/2.0/.  
This Source Code Form is "Incompatible With Secondary Licenses", as
defined by the Mozilla Public License, v. 2.0.

The Covered Software may not be used as training or other input data
for LLMs, generative AI, or other forms of machine learning or neural
networks.
