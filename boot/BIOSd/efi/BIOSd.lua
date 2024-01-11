-- bootloader will serve to uncompress kernel in the future
local function strToBytes(str)
    local bytes = 0

    for i = 1, #str do
        bytes = bytes + (str:sub(i, i):byte() << (i - 1) * 8)
    end

    return bytes
end

local drive = component.proxy(component.invoke(component.list("eeprom")(), "getData"))

local currentPath, currentInode, entryOffset = "", 2, strToBytes(drive.readSector(11):sub(169, 172))
local path = "boot/kernel.lua"

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

                    while true do
                        dataBlock = strToBytes((drive.readSector((indirectBlock + 1) * 2 - 1) .. drive.readSector((indirectBlock + 1) * 2)):sub(1 + offset, 4 + offset))

                        if dataBlock == 0 then
                            break
                        end

                        data = data .. drive.readSector((dataBlock + 1) * 2 - 1) .. drive.readSector((dataBlock + 1) * 2)
                        offset = offset + 4

                        if offset == 1024 then
                            break
                        end
                    end
                end

                load(data:match("[%g%s%p]+"), "=kernel")()
            end

            entryOffset = strToBytes(drive.readSector(10 + math.ceil(nextInode / 4)):sub((nextInode - 1) % 4 * 128 + 41, (nextInode - 1) % 4 * 128 + 44))
            break
        end

        offset = offset + strToBytes(currentEntry:sub(5 + offset, 6 + offset))
    end

    currentInode = nextInode
end