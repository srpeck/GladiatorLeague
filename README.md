Gladiator League
================

Twitch.tv IRC client/bot in Lua built to support a gaming league. When player stats are saved, they automatically update the website [gladiatorleague.github.io](https://gladiatorleague.github.io/).

Dependencies
------------
[Lua](http://www.lua.org/) and [LuaSocket](http://w3.impa.br/~diego/software/luasocket/) or [Lua for Windows](https://code.google.com/p/luaforwindows/).

To run
------
1. Modify main.lua for your Twitch.tv channel and credentials.
2. Run main.lua to start the IRC client/bot.

    main.lua | tee -a server.log

3. Use Twitch.tv chat for administration.

    !quit 
            Saves state to files and shuts down Twitch IRC bot.

    !save
            Saves state to files and updates the gladiatorleague.github.io website with new state (note that you will first have to clone the repo locally per setup.sh).

    !auth [name] managers
            Adds the named person to the list of Gladiator Managers, authorizing them to use those chat commands.

Detailed instructions for running on Windows in INSTRUCTIONS.txt.
