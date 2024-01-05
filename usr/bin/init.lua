local loadfile = ...

local cursorY = 1
local function status(message, state)
    if #message == 0 then
        cursorY = cursorY + 1
        return
    end

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
end

function dofile(file, fs, ...)
    checkArg(1, file, "string")
    checkArg(2, fs, "string", "table")

    local result, err = loadfile(file, fs)

    if result then
        return result(...)
    else
        error(debug.traceback(err))
    end
end

local bootFs = component.proxy(component.invoke(component.list("eeprom")(), "getData"))

local package = dofile("/lib/package.lua", bootFs)

package.require("sh")