gpu = component.proxy(component.list("gpu")())
gpubound = gpu.bind(component.list("screen")() or "", true)
resX, resY = gpu.getResolution()
cursorY = 1
status = gpubound and function(message, state)
    local function scroll()
        gpu.copy(1, 2, resX, resY - 1, 0, -1)
        gpu.fill(1, resY, resX, 1, " ")
    end

    local function wrapAround(message, cursorX)
        cursorY = cursorY + 1

        if cursorY > resY then
            cursorY = resY
            scroll()
        end

        gpu.set(1, cursorY, message)
    end

    if cursorY > resY then
        cursorY = resY
        scroll()
    end

    local cursorX = 10

    if state then
        gpu.set(1, cursorY, state == 0 and "[  " or "[")
        gpu.setForeground(state == 0 and 0x00FF00 or 0xFF0000)
        gpu.set(state == 0 and 4 or 2, cursorY, state == 0 and "OK" or "FAILED")
        gpu.setForeground(0xFFFFFF)
        gpu.set(state == 0 and 6 or 8, cursorY, state == 0 and "  ] " or "] ")
    end

    gpu.set(cursorX, cursorY, message)

    if #message + 9 > resX then
        wrapAround(message:sub(resX - 8))
        message = message:sub(resX * 2 - 8)

        while #message > 0 do
            wrapAround(message)
            message = message:sub(resX + 1)
        end
    end

    cursorY = cursorY + 1
end or function() end

if gpubound then
    gpu.fill(1, 1, resX, resY, " ")
end
status("Bound GPU to screen", 0)

status("Searching for internet card")
firstFailure, internet = true
repeat
    computer.pullSignal(0)
    internet = component.proxy(component.list("internet")() or "")

    if firstFailure and not internet then
        firstFailure = false
        status("No internet card found", 1)
        status("Waiting for insertion of internet card...")
    end
until internet
status("Internet card found", 0)

if not internet.isHttpEnabled() then
    status("HTTP is not enabled. Please enable it in the configuration file", 1)
    status("Shutting down...")
    sleep(5)
    computer.shutdown()
end

function sleep(seconds)
    local deadline = computer.uptime() + seconds

    repeat
        computer.pullSignal(deadline - computer.uptime())
    until computer.uptime() >= deadline
end

status("Fetching main chunk")
local handle = internet.request("https://raw.githubusercontent.com/Sencres013/Minux/master/boot/installer/main.lua")
local data, chunk = ""

local connected
repeat
    computer.pullSignal(0)
    connected = handle.finishConnect()
until connected

status("Reading chunk data")
repeat
    chunk = handle.read(math.huge)
    data = data .. (chunk or "")
until not chunk

handle.close()

if data == "" then
    status("Failed reading chunk data", 1)
    status("Rebooting...")
    sleep(5)
    computer.shutdown(true)
end

status("Loading chunk")
local result, err = load(data, "=installer", "t", _ENV)

if not result then
    status("Failed loading chunk: \"" .. err .. "\"", 1)
    status("Rebooting...")
    sleep(5)
    computer.shutdown(true)
else
    status("Loaded chunk", 0)
    return result()
end