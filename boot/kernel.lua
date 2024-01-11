-- local syscalls = {}

-- local function registerSyscall(name, callback)
--     checkArg(1, name, "string")
--     checkArg(2, callback, "function")

--     syscalls[name] = callback
-- end

-- local environment = {}

local function strToBytes(str)
    local bytes = 0

    for i = 1, #str do
        bytes = bytes + (str:sub(i, i):byte() << (i - 1) * 8)
    end

    return bytes
end

local drive = component.proxy(component.invoke(component.list("eeprom")(), "getData"))

local function readData(path)
    local currentPath, currentInode, entryOffset = "", 2, strToBytes(drive.readSector(11):sub(169, 172))
    
    for entry in path:gmatch("[^/]+") do
        local currentEntry, offset = drive.readSector((entryOffset + 1) * 2 - 1), 0
    
        while true do
            local nameLength = currentEntry:sub(7 + offset, 7 + offset):byte()
            local filename = currentEntry:sub(9 + offset, 9 + nameLength + offset - 1)
            nextInode = strToBytes(currentEntry:sub(1 + offset, 4 + offset))
    
            if filename == entry then
                currentPath = currentPath .. filename .. "/"
    
                if currentPath:sub(1, -2) == path then
                    local data = ""
    
                    for i = 1, 12 do
                        local dataBlock = strToBytes(drive.readSector(10 + math.ceil(nextInode / 4)):sub((nextInode - 1) % 4 * 128 + 41 + (i - 1) * 4, (nextInode - 1) % 4 * 128 + 40 + i * 4))
    
                        if dataBlock == 0 then
                            break
                        end
    
                        data = data .. drive.readSector((dataBlock + 1) * 2 - 1) .. drive.readSector((dataBlock + 1) * 2)
                    end
    
                    dataBlock = strToBytes(drive.readSector(10 + math.ceil(nextInode / 4)):sub((nextInode - 1) % 4 * 207, (nextInode - 1) % 4 * 210))
                    if dataBlock ~= 0 then
                        local indirectBlock, offset = drive.readSector((dataBlock + 1) * 2 - 1) .. drive.readSector((dataBlock + 1) * 2), 0
    
                        while true do end
                            dataBlock = strToBytes((drive.readSector((indirectBlock + 1) * 2 - 1) .. drive.readSector((indirectBlock + 1) * 2)):sub(1 + offset, 4 + offset))
    
                            if dataBlock == 0 then
                                break
                            end
    
                            data = data .. drive.readSector((dataBlock + 1) * 2 - 1) .. drive.readSector((dataBlock + 1) * 2)
                            offset = offset + 4
                        end
                    end
    
                    return data:match("[%g%s%p]+"), nextInode
                end
    
                entryOffset = strToBytes(drive.readSector(10 + math.ceil(nextInode / 4)):sub((nextInode - 1) % 4 * 128 + 41, (nextInode - 1) % 4 * 128 + 44))
                break
            end
    
            offset = offset + strToBytes(currentEntry:sub(5 + offset, 6 + offset))

            if offset >= 1024 then
                return ""
            end
        end
    
        currentInode = nextInode
    end
end

local function nextAvailableBit(bitmap)
    for i = 1, 1024 do
        local currentByte = bitmap:sub(i, i):byte()

        if currentByte ~= 0xFF then
            for j = 1, 8 do
                if currentByte & (1 << (j - 1)) ~= 1 << (j - 1) then
                    bitmap = bitmap:sub(1, i - 1) .. string.char(currentByte | (1 << (j - 1))) .. bitmap:sub(i + 1)

                    return (i - 1) * 8 + j, bitmap
                end
            end
        end
    end
end

local function bytesToStr(num, length)
    local bytes, limit = {}, 0

    local numCopy = num
    while numCopy > 0 do
        limit = limit + 1
        numCopy = numCopy >> 8
    end

    for i = 1, limit do
        bytes[i] = string.char((num >> (i - 1) * 8) & 0xFF)
    end

    while length > limit do
        table.insert(bytes, "\x00")
        length = length - 1
    end

    return table.concat(bytes)
end

local function writeData(inode, data)
    local inodeSector = drive.readSector(10 + math.ceil(inode / 4))
    local inodeData = inodeSector:sub((inode - 1) % 4 * 128 + 1, (inode - 1) % 4 * 128 + 128)

    local numBlocks = math.ceil(#data / 1024)
    local blockBitmap = drive.readSector(7) .. drive.readSector(8)

    for i = 1, 12 do
        if strToBytes(inodeData:sub(41 + (i - 1) * 4, 40 + i * 4)) == 0 then
            if i <= numBlocks then
                local blockAddr, newBlockBitmap = nextAvailableBit(blockBitmap)
                blockBitmap = newBlockBitmap

                drive.writeSector((blockAddr + 1) * 2 - 1, data:sub((i - 1) * 1024 + 1, (i - 1) * 1024 + 512))
                drive.writeSector((blockAddr + 1) * 2, data:sub((i - 1) * 1024 + 513, i * 1024))
            else
                break
            end
        else
            if i <= numBlocks then
                local blockAddr = inodeData:sub(41 + (i - 1) * 4, 40 + i * 4)

                drive.writeSector((blockAddr + 1) * 2 - 1, data:sub((i - 1) * 1024 + 1, (i - 1) * 1024 + 512))
                drive.writeSector((blockAddr + 1) * 2, data:sub((i - 1) * 1024 + 513, i * 1024))
            else
                inodeData = inodeData:sub(1, 40 + i * 4) .. bytesToStr(0x0, 4) .. inodeData:sub(45 + i * 4)
            end
        end
    end

    if inode - 1 % 4 == 0 then
        inodeSector = inodeData .. inodeSector:sub(129)
    elseif inode % 4 == 0 then
        inodeSector = inodeSector:sub(1, 384) .. inodeData
    else
        inodeSector = inodeSector:sub(1, (inode - 1) % 4 * 128) .. inodeData .. inodeSector:sub(inode % 4 * 128 + 1)
    end

    drive.writeSector(7, blockBitmap:sub(1, 512))
    drive.writeSector(8, blockBitmap:sub(513, 1024))
    drive.writeSector(10 + math.ceil(inode / 4), inodeSector)
end

local inEditor = false
local gpu = component.proxy(component.list("gpu")())
local resX, resY = gpu.getResolution()
local cursorX, cursorY = 1, 1

while true do
    local result = table.pack(computer.pullSignal())
    local data, buffer, inode = "", ""
    local dataLines = {}
    
    if result[1] == "key_down" then
        if result[4] == 28 then
            if not inEditor then
                data, inode = readData(buffer)

                if data ~= "" then
                    for line in data:gmatch("([^\n]+)\n?") do
                        table.insert(dataLines, line)
                    end

                    gpu.fill(1, 1, resX, resY, " ")

                    cursorX = 1
                    cursorY = 1

                    for line in dataLines do
                        gpu.set(1, cursorY, line)
                        cursorY = cursorY + 1
                    end

                    cursorY = 1

                    gpu.setBackground(0xFFFFFF)
                    gpu.setForeground(0x000000)
                    gpu.set(1, 1, gpu.get(1, 1))

                    inEditor = true
                end

                buffer = ""
            end
        elseif result[4] == 1 then
            if inEditor then
                writeData(inode, data)

                gpu.setBackground(0x000000)
                gpu.fill(1, 1, resX, resY, " ")

                inEditor = false
            end
        elseif result[3] >= 32 and result[3] <= 126 then
            if not inEditor then
                gpu.set(cursorX, 1, string.char(result[3]))
                cursorX = cursorX + 1

                buffer = buffer .. string.char(result[3])
            else
                cursorX = cursorX + 1
            end
        end

        if inEditor and result[4] == 200 or result[4] == 203 or result[4] == 205 or result[4] == 208 then
            gpu.setBackground(0x000000)
            gpu.setForeground(0xFFFFFF)
            gpu.set(cursorX, cursorY, gpu.get(cursorX, cursorY))

            if result[4] == 203 then -- left arrow
                cursorX = cursorX - 1
            elseif result[4] == 205 then -- right arrow
                cursorX = cursorX + 1
            elseif result[4] == 200 then -- up arrow
                cursorY = cursorY - 1
            elseif result[4] == 208 then -- down arrow
                cursorY = cursorY + 1
            end

            gpu.setBackground(0xFFFFFF)
            gpu.setForeground(0x000000)
            gpu.set(cursorX, cursorY, gpu.get(cursorX, cursorY))
        end
    end
end