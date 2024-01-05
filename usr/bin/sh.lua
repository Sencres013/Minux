local gpu = component.proxy(component.list("gpu")())
local resX, resY = gpu.getResolution()
local cursorX, cursorY = 1, 1

gpu.fill(1, 1, resX, resY, " ")

function writeChar(chr)
    checkArg(1, chr, "string")
    
    gpu.set(cursorX, cursorY, chr)

    cursorY = cursorX == resX and cursorY + 1 or cursorY
    cursorX = cursorX == resX and 1 or cursorX + 1
    
    if cursorY > resY then
        gpu.fill(gpu.get(1, 1) == ">" and 2 or 1, 1, resX, 1, " ")
        gpu.copy(2, 2, resX, resY - 1, 0, -1)
        for i = 2, resY do
            gpu.copy(1, i, 1, 1, 0, -1)
        end
        gpu.fill(1, resY, resX, 1, " ")
        cursorY = resY
    end
end

writeChar(">")
writeChar(" ")

local command = ""

while true do
    local result = table.pack(computer.pullSignal())

    if result[1] == "key_down" then
        if result[4] == 28 then
            --coroutine.resume(require("process").load(command))

            if cursorX ~= 1 then
                cursorY = cursorY + 1
            end

            cursorX = 1

            if cursorY > resY then
                gpu.fill(gpu.get(1, 1) == ">" and 2 or 1, 1, resX, 1, " ")
                gpu.copy(2, 2, resX, resY - 1, 0, -1)
                for i = 2, resY do
                    gpu.copy(1, i, 1, 1, 0, -1)
                end
                gpu.fill(1, resY, resX, 1, " ")
                cursorY = resY
            end

            writeChar(">")
            writeChar(" ")
        elseif result[4] == 14 then
            if not (gpu.get(1, cursorY) == ">" and cursorX == 3) then
                if cursorX ~= 1 then
                    cursorX = cursorX - 1
                else
                    cursorX = resX
                    cursorY = cursorY - 1
                end
                gpu.set(cursorX, cursorY, " ")
            end
        elseif result[3] >= 32 and result[3] <= 126 then
            writeChar(string.char(result[3]))
            command = command .. string.char(result[3])
        end
    end
end