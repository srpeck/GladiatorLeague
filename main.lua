local socket = require "socket"
local json = require "json"
local gamesfile = io.open("gameresults.json", "a+")
local wagersfile = io.open("wagerresults.json", "a+")
local playersfile = io.open("playerstate.json", "r")
local raw = false
if playersfile then raw = playersfile:read() end
print(os.date() .. " Loading")
print(raw)
local init = {}
if raw then init = json.decode(raw) end
local admins = init.a or {gladiatorleague = {}}
local managers = init.m or {bifswat = {w = 0, l = 0}, gladiatorleague = {w = 0, l = 0}}
local gladiators = init.g or {}
local bettors = init.b or {}
if playersfile then playersfile:close() end
playersfile = io.open("playerstate.json", "w+")
if raw then
    playersfile:write(raw)
    playersfile:flush()
end
local available, inchannel, games, wagers = {}, {}, {}, {}
local tcp = socket.tcp()
local channel = "#gladiatorleague"
tcp:connect(socket.dns.toip("irc.twitch.tv"), 6667)
tcp:send("PASS your_password_here\r\n")
tcp:send("NICK gladiatorleague\r\n")
tcp:send("JOIN " .. channel .. "\r\n")

function broadcast(message)
    local s = "PRIVMSG " .. channel .. " :" .. message .. "\r\n"
    tcp:send(s)
    print("< " .. s)
end

function table_size(t)
    local c = 0
    for k, v in pairs(t) do c = c + 1 end
    return c
end

local quit = false
while not quit do
    line = tcp:receive("*l")
    if line then
        print("> " .. line)
        if line:find("PING ") then
            local s = "PONG " .. line:sub((string.find(line, "PING ") + 5)) .. "\r\n"
            tcp:send(s)
            print("< " .. s)
        elseif line:find("JOIN") then
            inchannel[line:match("^:(%S+)!")] = {}
        elseif line:find("PART") then -- Sometimes happens even if people remain in twitch.tv channel...
            local parted = line:match("^:(%S+)!")
            inchannel[parted], available[parted] = nil
        elseif line:find(":!up ") or line:find(":!down ") then
            local voter, vote, gladiator, gamename = line:match("^:(%S+)!.* :!(%S+) (%S+) (%S+)$")
            if games[gamename] and voter ~= gladiator then
                for mgr, team in pairs(games[gamename]) do
                    for glad, votes in pairs(games[gamename][mgr]) do
                        if gladiator == glad and voter ~= mgr then
                            table.insert(games[gamename][mgr][glad][vote], voter)
                            break
                        end
                    end
                end
            end
        elseif line:find(":!available ") then
            local gladiator, ingamename = line:match("^:(%S+)!.* :!available (.*)$")
            if gladiator and ingamename then
                if gladiators[gladiator] then
                    available[gladiator] = gladiators[gladiator]
                    available[gladiator].name = ingamename
                else
                    gladiators[gladiator] = {name = ingamename, rank = 0, w = 0, l = 0, streak = 0}
                    available[gladiator] = gladiators[gladiator]
                end
            end
        elseif line:find(":!bet ") then
            local bettor, amount, odds1, odds2, description = line:match("^:(%S+)!.* :!bet (%d+) (%d+)-(%d+) (.*)$") -- e.g., "!bet 10 5-1 bifswat takes first blood"
            if not bettors[bettor] then
                bettors[bettor] = {gp = 100, reserved = 0} -- Currently, everyone starts with 100GP
            end
            if bettors[bettor].gp >= amount * odds2 then
                local wager_id = #wagers + 1
                wagers[wager_id] = {bettor = bettor, amount = amount, odds1 = odds1, odds2 = odds2, description = description, bettime = os.time()}
                broadcast("Wager ID " .. wager_id .. ": " .. bettor .. " bets " .. amount .. "GP at " .. odds1 .. " to " .. odds2 .. " odds '" .. description .. "'. Any takers? !take [Wager ID]")
            end
        elseif line:find(":!take ") then
            local taker, wager = line:match("^:(%S+)!.* :!take (%d+)$")
            if taker then
                if not bettors[taker] then -- TODO BUG
                    bettors[taker] = {gp = 100, reserved = 0} -- Currently, everyone starts with 100GP
                end
            end
            local w = wagers[tonumber(wager)]
            if w and bettors[taker].gp >= w.amount * w.odds1 then
                w.taker = taker
                w.taketime = os.time()
                bettors[w.bettor].gp = bettors[w.bettor].gp - w.amount * w.odds2 
                bettors[w.bettor].reserved = w.amount * w.odds2
                bettors[taker].gp = bettors[taker].gp - w.amount * w.odds1 
                bettors[taker].reserved = w.amount * w.odds1
                wagersfile:write(json.encode(w) .. ",\n") -- Written to file before completed just in case moderator cannot arbitrate until later
                wagersfile:flush()
                broadcast("Wager ID " .. wager .. ": " .. taker .. " takes bet '" .. w.description .. "'.")
            end
        elseif line:find(":!result ") then
            local moderator, wager, winner = line:match("^:(%S+)!.* :!result (%d+) (%S+)$")
            local w = wagers[tonumber(wager)]
            if managers[moderator] and w and bettors[winner] then
                w.winner = winner
                w.wintime = os.time()
                bettors[w.bettor].reserved = bettors[w.bettor].reserved - w.amount * w.odds2
                bettors[w.taker].reserved = bettors[w.taker].reserved - w.amount * w.odds1
                bettors[winner].gp = bettors[winner].gp + w.amount * w.odds2 + w.amount * w.odds1
                wagersfile:write(json.encode(w) .. ",\n")
                wagersfile:flush()
                broadcast("Wager ID " .. wager .. " won by " .. winner .. ".")
            end
        elseif line:find(":!cancel ") then
            local moderator, wager, reason = line:match("^:(%S+)!.* :!cancel (%d+)(.*)$")
            local w = wagers[tonumber(wager)]
            if managers[moderator] and w then
                w.canceltime = os.time()
                bettors[w.bettor].reserved = bettors[w.bettor].reserved - w.amount * w.odds2
                bettors[w.bettor].gp = bettors[w.bettor].gp + w.amount * w.odds2
                if w.taker then
                    bettors[w.taker].reserved = bettors[w.taker].reserved - w.amount * w.odds1
                    bettors[w.taker].gp = bettors[w.taker].gp + w.amount * w.odds1
                end
                wagersfile:write(json.encode(w) .. ",\n")
                wagersfile:flush()
                local s = "Wager ID " .. wager .. " canceled by " .. moderator .. ". "
                if reason then s = s .. reason end
                broadcast(s)
            end
        elseif line:find(":!pick ") then
            local picker = line:match("^:(%S+)!")
            if managers[picker] then
                local picked, gamename = line:match("^.* :!pick (%S+) (%S+)$")
                if available[picked] and games[gamename] then -- Check if pick in gladiators group and available needed? Player confirmation?
                    if not games[gamename][picker] then
                        games[gamename][picker] = {}
                    end
                    if table_size(games[gamename][picker]) < 5 then
                        games[gamename][picker][picked] = {up = {}, down = {}}
                        available[picked] = nil
                        broadcast("Picked " .. picked .. " for " .. picker .. "'s team in " .. gamename)
                        if table_size(games[gamename][picker]) == 5 then
                            local msg = picker .. "'s team for '" .. gamename .. "': "
                            for k, v in pairs(games[gamename][picker]) do
                                msg = msg .. k .. ", "
                            end
                            msg = msg:sub(0, #msg - 2) .. ". Vote for a gladiator to live (!up) or die (!down) - e.g., !up [gladiator] [gamename]."
                            broadcast(msg)
                        end
                    end
                end
            end
        elseif line:find(":!challenge ") then
            local challenger = line:match("^:(%S+)!")
            if managers[challenger] then
                local challenged, gamename = line:match("^.* :!challenge (%S+) (%S+)$")
                if managers[challenged] and not games[gamename] then
                    games[gamename] = {}
                    games[gamename][challenger], games[gamename][challenged] = {}, {}
                    broadcast("Starting new game: '" .. gamename .. "'. Use !pick [gladiator] [gamename]. Top 10 available gladiators:")
                    table.sort(available, function(a, b) return a.streak < b.streak end)
                    local c = 0
                    for k, v in pairs(available) do
                        if c < 10 then 
                            broadcast(k .. " (current streak: " .. v.streak .. ")")
                            c = c + 1
                        else break end
                    end
                end
            end
        elseif line:find(":!win ") then
            local reporter = line:match("^:(%S+)!")
            if managers[reporter] then
                local victor, gamename = line:match("^.* :!win (%S+) (%S+)$")
                if managers[victor] and games[gamename] then
                    if games[gamename][victor] and table_size(games[gamename][victor]) == 5 and table_size(games[gamename][loser]) == 5 then
                        games[gamename].win = victor
                        local loser
                        for k, v in pairs(games[gamename]) do
                            if k ~= victor then
                                loser = k
                                break
                            end
                        end
                        if loser then -- Require screenshot/replay URL or game ID for proof? Timer-based voting?
                            games[gamename].name = gamename
                            games[gamename].time = os.time()
                            managers[loser].l = managers[loser].l + 1
                            managers[victor].w = managers[victor].w + 1
                            for glad, votes in pairs(games[gamename][victor]) do 
                                gladiators[glad].streak = gladiators[glad].streak + 1
                                gladiators[glad].w = gladiators[glad].w + 1
                            end
                            local msg = loser .. "'s team lost " .. gamename .. " against " .. victor .. "'s team. Resulting votes for gladiators' lives: "
                            for glad, votes in pairs(games[gamename][loser]) do
                                msg = msg .. glad .. ((#votes.up > #votes.down) and " lives " or " dies ") .. "(" .. #votes.up .. " up, " .. #votes.down .. " down), "
                                gladiators[glad].streak = (#votes.up > #votes.down) and gladiators[glad].streak or 0
                                gladiators[glad].l = gladiators[glad].l + 1
                            end
                            gamesfile:write(json.encode(games[gamename]) .. ",\n")
                            gamesfile:flush()
                            playersfile:seek("set")
                            playersfile:write(json.encode({a = admins, m = managers, g = gladiators, b = bettors}))
                            playersfile:flush()
                            broadcast(msg:sub(0, #msg - 2))
                        end
                    end
                end
            end
        elseif line:find(":!auth ") then
            local admin = line:match("^:(%S+)!")
            if admins[admin] then
                local user, group = line:match("^.* :!auth (%S+) (%S+)$")
                if user and group == "managers" then
                    managers[user] = {w = 0, l = 0}
                    broadcast(user .. " added to Managers group. Commands available: !challenge [manager] [gamename], !pick [gladiator] [gamename].")
                end
            end
        elseif line:find(":!save") then
            local admin = line:match("^:(%S+)!.* :!save$")
            if admins[admin] then
                local filename = "playerstate" .. os.date("%Y%m%d%H%M%S") .. ".json"
                local f = io.open(filename, "w+")
                f:write(json.encode({a = admins, m = managers, g = gladiators, b = bettors}))
                f:flush()
                f:close()
                os.execute("cp " .. filename .. " ../githubsite/playerstate.json")
                os.execute("git --git-dir ../githubsite/.git --work-tree ../githubsite add .")
                os.execute("git --git-dir ../githubsite/.git --work-tree ../githubsite commit -m \"" .. filename .. "\"")
                os.execute("git --git-dir ../githubsite/.git --work-tree ../githubsite push origin master")
            end
        elseif line:find(":!quit") then
            local admin = line:match("^:(%S+)!")
            if admins[admin] then
                quit = true
            end
        end
    end
    io.flush()
    socket.sleep(0.01)
end

wagersfile:close()
gamesfile:close()
playersfile:seek("set")
playersfile:write(json.encode({a = admins, m = managers, g = gladiators, b = bettors}))
playersfile:flush()
playersfile:close()
print(os.date() .. " Closing down.")
