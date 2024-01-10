local function format(drive)
    local zeroSector = ""

    for i = 1, 32 do
        zeroSector = zeroSector .. "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    end

    for i = 1, drive.getCapacity() / 512 do
        drive.writeSector(i, zeroSector)
    end
end

local function formatBytes(bytes)
    local levels, index = { "B", "KiB", "MiB" }, 1

    while bytes / 1024 >= 1 do
        index = index + 1
        bytes = bytes / 1024
    end

    return tostring(bytes):sub(1, math.min(#tostring(bytes), 3)) .. " " .. levels[index]
end

local function fsToStr(fs)
    return fs.label .. " - " .. formatBytes(fs.spaceTotal)
end

local function outputOption(fs, inverted, cursorY)
    if inverted then
        gpu.setBackground(0xFFFFFF)
        gpu.setForeground(0x0)
    else
        gpu.setBackground(0x0)
        gpu.setForeground(0xFFFFFF)
    end

    local fsStr = fsToStr(fs)
    gpu.set(math.ceil(math.max(resX - #fsStr, 1) / 2), cursorY, fsStr)
end

status("Searching for suitable drives")
local addrList, drive = {}
firstFailure = true
repeat
    computer.pullSignal(0)
    for driveAddr in component.list("drive", true) do
        if component.invoke(driveAddr, "getSectorSize") == 512 then
            table.insert(addrList, driveAddr)
        end
    end

    if firstFailure and #addrList == 0 then
        firstFailure = false
        status("No suitable drive found", 1)
        status("Waiting for insertion of suitable drive...")
    end
until #addrList > 0

local buffer = gpu.allocateBuffer()
gpu.bitblt(buffer, 1, 1, resX, resY, 0, 1, 1)

local index, driveList, cursorY, baseY = 1, {}

-- add listener for component_added and component_removed and update the list accordingly
for i = 1, #addrList do
    local label = component.invoke(addrList[i], "getLabel") or "NO_LABEL"
    label = #label > 17 and label:sub(1, 17) .. "..." or label

    driveList[i] = {
        addr = addrList[i],
        label = label,
        spaceTotal = component.invoke(addrList[i], "getCapacity")
    }
end

table.sort(driveList, function(elem1, elem2)
    if elem1.label ~= elem2.label then
        return elem1.label < elem2.label
    elseif elem1.spaceTotal ~= elem2.spaceTotal then
        return elem1.spaceTotal < elem2.spaceTotal
    else
        return elem1.addr < elem2.addr
    end
end)

gpu.fill(1, 1, resX, resY, " ")
cursorY = math.floor(resY / 2) - math.ceil(#driveList / 2)
gpu.set(math.ceil(math.max(resX - 45, 1) / 2), cursorY, "Select drive to format and install Minux onto")
cursorY = cursorY + 2
baseY = cursorY

outputOption(driveList[1], true, cursorY)
cursorY = cursorY + 1

for i = 2, #driveList do
    outputOption(driveList[i], false, cursorY)
    cursorY = cursorY + 1
end

local drive
while true do
    ::pullSignal::
    local result = table.pack(computer.pullSignal())

    if result[1] == "key_down" then
        local lastIndex

        if result[4] == 28 then
            gpu.bitblt(0, 1, 1, resX, resY, buffer, 1, 1)
            gpu.setBackground(0x0)
            gpu.setForeground(0xFFFFFF)

            drive = driveList[index].addr
            status("Selected drive " .. driveList[index].label .. " at address " .. drive, 0)

            status("Formatting drive...")
            format(component.proxy(drive))
            status("Formatted drive", 0)

            break
        elseif result[4] == 200 then
            lastIndex = index
            index = math.max(index - 1, 1)
        elseif result[4] == 208 then
            lastIndex = index
            index = math.min(index + 1, #driveList)
        else
            goto pullSignal
        end
        
        outputOption(driveList[lastIndex], false, baseY + lastIndex - 1)
        outputOption(driveList[index], true, baseY + index - 1)
    end
end

local driveUUID = drive
drive = component.proxy(drive);

local label = drive.getLabel() or "NO_LABEL"
label = #label > 17 and label:sub(1, 17) .. "..." or label
local eeprom = component.proxy(component.list("eeprom")())

eeprom.setData(driveUUID);
status("Set boot address to " .. driveUUID, 0)

status("Initializing MBR")
local MBR = "local a=component;local b=a.proxy(a.list(\"drive\",true)())local c=b.readSector;load((c(2)..c(3)):match(\"[%g ]+\"),\"=MBRext\")"
local MBRext = "local a,b,c,d=function(z)local y=0;for x=1,#z do y=y+z:sub(x,x):byte()<<(x-1)*8 end end,function(z)return 446+(z-1)*16;end,component,math.ceil;local e=c.proxy(c.list(\"eeprom\")(),\"getData\")local f=e.readSector;local g,h,i,j=f(1),\"\",2;for z=1,4 do if g:byte(b(z)+1)==64 and g:byte(b(z)+5)==131 then j=a(g:sub(b(z)+9,b(z)+12))break;end end local k=a(f(11+j):sub(169,172))local l,m,n,o,p,q,r=\"boot/BIOSd/efi/BIOSd.lua\",\"\"for s in l:gmatch(\"([^/]+)/?\")do n,o=f((k+1)*2-1),0;while 1 do q=n:sub(9+o,9+n:sub(7+o,7+o):byte()+o-1)p=a(n:sub(1+o,4+o))if h:sub(1,-2)==l then for z=1,12 do r=a(f(10+j+d(i/4)):sub((i-1)%4*128+41+(z-1)*4,(i-1)%4*128+40+z*4))if r==0 then break;end m=m..f((r+1)*2-1+j)..f((r+1)*2+j)end load(m:match(\"([%g ]+)\"),\"=BIOSd\")()end if q==s then h=h..q..\"/\"k=a(f(10+d(p/4)):sub((p-1)%4*128+41,(p-1)%4*128+44))end o=o+a(n:sub(5+o,6+o))end i=p;end"

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

for i = 1, 446 - #MBR do
    MBR = MBR .. "\x00"
end

local startSector = 2
local capacity = drive.getCapacity() - startSector * 512

MBR = MBR .. bytesToStr(0x80, 1) -- active
MBR = MBR .. bytesToStr(0x0, 3) -- CHS is irrelevant
MBR = MBR .. bytesToStr(0x83, 1) -- partition type linux fs
MBR = MBR .. bytesToStr(0x0, 3) -- CHS is irrelevant
MBR = MBR .. bytesToStr(startSector, 4) -- first absolute sector
MBR = MBR .. bytesToStr(capacity / 512, 4) -- number of sectors

-- empty partitions
for i = 1, 6 do
    MBR = MBR .. "\x00\x00\x00\x00\x00\x00\x00\x00"
end

MBR = MBR .. "\x55\xAA" -- bootable flag
status("Initialized MBR", 0)

status("Initializing superblock")
local superblock = ""

local function appendSuperblock(value, length)
    if type(value) == "string" then
        superblock = superblock .. value

        for i = 1, length - #value do
            superblock = superblock .. "\x00"
        end
    else
        superblock = superblock .. bytesToStr(value, length)
    end
end

local blockSize, fragmentSize, bytesPerInode = 1024, 1024, 2048 -- block fragmentation not implemented
local totalInodes, reservedBlocks = math.floor(capacity / bytesPerInode), math.floor(capacity / blockSize * 0.05)
if totalInodes % 4 ~= 0 then
    totalInodes = totalInodes + 4 - totalInodes % 4
end

-- main fields
appendSuperblock(totalInodes, 4) -- total number of inodes in the system
appendSuperblock(capacity / blockSize, 4) -- amount of blocks
appendSuperblock(reservedBlocks, 4) -- 5% of blocks reserved for superuser
appendSuperblock(capacity / blockSize - 5 - totalInodes * 128 / blockSize - 1, 4) -- total number of unallocated blocks (total blocks - metadata - inode blocks - lost+found)
appendSuperblock(totalInodes - 11, 4) -- total number of unallocated inodes (10 reserved and lost+found)
appendSuperblock(0x1, 4) -- block containing the superblock
appendSuperblock(math.log(blockSize, 2) - 10, 4) -- number to shift 1024 by to get block size
appendSuperblock(math.log(fragmentSize, 2) - 10, 4) -- number to shift 1024 by to get fragment size
appendSuperblock(0x2000, 4) -- number of blocks in each group
appendSuperblock(0x2000, 4) -- number of fragments in each group
appendSuperblock(totalInodes, 4) -- number of inodes in each group
appendSuperblock(0x0, 4) -- last mount time
appendSuperblock(math.floor(os.time()), 4) -- last written time
appendSuperblock(0x0, 2) -- number of times mounted since consistency check
appendSuperblock(0xFFFF, 2) -- number of mounts allowed before consistency check
appendSuperblock(0xEF53, 2) -- ext signature
appendSuperblock(0x1, 2) -- file system state (1 = clean)
appendSuperblock(0x1, 2) -- what to do when error is detected (1 = ignore)
appendSuperblock(0x0, 2) -- minor portion of version
appendSuperblock(0x0, 4) -- time of last consistency check
appendSuperblock(0x0, 4) -- interval between forced consistency checks
appendSuperblock(0x0, 4) -- operating system id (0 = linux)
appendSuperblock(0x1, 4) -- major portion of version
appendSuperblock(0x0, 2) -- user id that can use reserved blocks
appendSuperblock(0x0, 2) -- group id that can use reserved blocks

local function UUIDStrToByteStr(uuid)
    local justBytes = ""
    for i = 1, #uuid do
        justBytes = justBytes .. (uuid:sub(i, i) ~= "-" and uuid:sub(i, i) or "")
    end
    
    local bytes = {}
    for i = 1, #justBytes / 2 do
        bytes[i] = string.char((tonumber(justBytes:sub(i * 2 - 1, i * 2 - 1), 16) << 4) + tonumber(justBytes:sub(i * 2, i * 2), 16))
    end

    return table.concat(bytes)
end

-- extended fields
appendSuperblock(0xB, 4) -- first non reserved inode
appendSuperblock(0x80, 2) -- size of inode structure
appendSuperblock(0x0, 2) -- block group the superblock is part of (if backup copy)
appendSuperblock(0x0, 4) -- optional features, subject to change
appendSuperblock(0x2, 4) -- required features, subject to change
appendSuperblock(0x1, 4) -- features that if not supported, volume must be mounted in read only mode, subject to change
appendSuperblock(UUIDStrToByteStr(driveUUID), 16) -- file system id
appendSuperblock("label", 16) -- volume name
appendSuperblock(0x0, 64) -- path volume was last mounted to
appendSuperblock(0x0, 4) -- compression algorithms used, if any
appendSuperblock(0x0, 1) -- number of blocks to preallocate for files
appendSuperblock(0x0, 1) -- number of blocks to preallocate for directories
appendSuperblock(0x0, 2) -- unused
appendSuperblock(0x0, 16) -- journal id, same style as file system id
appendSuperblock(0x0, 4) -- journal inode
appendSuperblock(0x0, 4) -- journal device
appendSuperblock(0x0, 4) -- head of orphan inode list, lost+found inode index
status("Initialized superblock", 0)

status("Initializing group descriptor table")
local GDT = ""

local function appendGDT(value, length)
    GDT = GDT .. bytesToStr(value, length)
end

appendGDT(0x3, 4) -- block address of block usage map
appendGDT(0x4, 4) -- block address of inode usage map
appendGDT(0x5, 4) -- starting block address of inode table
appendGDT(capacity / blockSize - 5 - totalInodes * 128 / blockSize - 1, 2) -- number of unallocated blocks in group (total - metadata - inode blocks - lost+found)
appendGDT(totalInodes - 10, 2) -- number of unallocated inodes in group
appendGDT(0x2, 2) -- number of directories in group (root and lost+found)
status("Initialized group descriptor table", 0)

status("Initializing block bitmap")
local blockBitmap = ""

local blockBits = ""
for i = 1, capacity / blockSize - (capacity / blockSize - 5 - totalInodes * 128 / blockSize - 1) do
    blockBits = blockBits .. "1"
end

local blockBitsSize = #blockBits

while #blockBits > 0 do
    if #blockBits < 8 then
        blockBits = string.sub("00000000", 1, 8 - #blockBits) .. blockBits
    end

    blockBitmap = blockBitmap .. string.char(tonumber(blockBits:sub(1, 8), 2))
    blockBits = blockBits:sub(1, math.max(#blockBits - 8, 0))
end

for i = 1, math.ceil(capacity / blockSize / 8) - math.ceil(blockBitsSize / 8) - 1 do
    blockBitmap = blockBitmap .. "\x00"
end

if capacity / blockSize % 8 ~= 0 then
    local finalUseByte = 0
    for i = 0, 8 - capacity / blockSize % 8 do
        finalUseByte = finalUseByte + (1 << 7 - i)
    end
    blockBitmap = blockBitmap .. bytesToStr(finalUseByte, 1)
else
    blockBitmap = blockBitmap .. "\x80"
end

for i = 1, 1024 - #blockBitmap do
    blockBitmap = blockBitmap .. "\xFF"
end
status("Initialized block bitmap", 0)

status("Initializing inode bitmap")
local inodeBitmap = "\xFF\x03" -- first 10 reserved inodes

for i = 1, math.floor(totalInodes / 8) do
    inodeBitmap = inodeBitmap .. "\x00"
end

if totalInodes % 8 ~= 0 then
    inodeBitmap = inodeBitmap .. "\xF0"
end

for i = 1, 1024 - math.ceil(totalInodes / 8) do
    inodeBitmap = inodeBitmap .. "\xFF"
end
status("Initialized inode bitmap", 0)

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

local function createInode(data, type, perms, userId, groupId, index)
    local inode = ""

    local function appendInode(value, length)
        inode = inode .. bytesToStr(value, length)
    end

    appendInode(type + perms, 2)
    appendInode(userId & 0xFFFF, 2)

    if type == 0x4000 then
        appendInode(0x18, 4)
    else
        appendInode(#data == 0 and 0x400 or #data, 4)
    end

    appendInode(math.floor(os.time()), 4)
    appendInode(math.floor(os.time()), 4)
    appendInode(math.floor(os.time()), 4)
    appendInode(0x0, 4)
    appendInode(groupId & 0xFFFF, 2)

    if type == 0x4000 then
        appendInode(0x2, 2)
    else
        appendInode(0x1, 2)
    end

    local numBlocks = math.floor(#data / 1024) + 1

    if #data == 0 then
        appendInode(0x2, 4)
    elseif numBlocks <= 12 then
        appendInode(math.ceil(#data / 1024) * 2, 4)
    else
        appendInode(math.ceil(#data / 1024) * 2 + 2, 4)
    end
    
    appendInode(0x0, 4)
    appendInode(0x0, 4)

    for i = 1, math.min(numBlocks, 12) do
        local blockAddr, newBlockBitmap = nextAvailableBit(blockBitmap)
        blockBitmap = newBlockBitmap

        appendInode(blockAddr, 4)

        drive.writeSector((blockAddr + 1) * 2 - 1, data:sub((i - 1) * 1024 + 1, (i - 1) * 1024 + 512))
        drive.writeSector((blockAddr + 1) * 2, data:sub((i - 1) * 1024 + 513, i * 1024))
    end

    for i = 1, 12 - math.max(numBlocks, 0) do
        appendInode(0x0, 4)
    end

    if numBlocks > 12 then
        local directBlockAddr, newBlockBitmap = nextAvailableBit(blockBitmap)
        local directBlock = ""

        blockBitmap = newBlockBitmap

        appendInode(directBlockAddr, 4)

        for i = 1, numBlocks - 12 do
            local blockAddr, newBlockBitmap = nextAvailableBit(blockBitmap)

            blockBitmap = newBlockBitmap
            directBlock = directBlock .. bytesToStr(blockAddr, 4)

            drive.writeSector((blockAddr + 1) * 2 - 1, data:sub((i + 11) * 1024 + 1, (i + 11) * 1024 + 512))
            drive.writeSector((blockAddr + 1) * 2, data:sub((i + 11) * 1024 + 513, (i + 12) * 1024))
        end

        drive.writeSector((directBlockAddr + 1) * 2 - 1, directBlock:sub(1, 512))
        drive.writeSector((directBlockAddr + 1) * 2, directBlock:sub(513, 1024))
    else
        appendInode(0x0, 4)
    end

    -- TODO doubly indirect blocks
    -- if numBlocks > 12 + 256 then

    -- end
    appendInode(0x0, 4) -- double indirect
    appendInode(0x0, 4) -- triply indirect

    appendInode(0x0, 4)
    appendInode(0x0, 4)
    appendInode(0x0, 4)
    appendInode(0x0, 4)
    appendInode(0x0, 1)
    appendInode(0x0, 1)
    appendInode(0x0, 2)
    appendInode((userId >> 16) & 0xFFFF, 2)
    appendInode((groupId >> 16) & 0xFFFF, 2)
    appendInode(0x0, 4)

    if not index then
        local nextInodeAddr, newInodeBitmap = nextAvailableBit(inodeBitmap)

        index = nextInodeAddr
        inodeBitmap = newInodeBitmap
    end

    local data = drive.readSector(10 + startSector + math.ceil(index / 4))

    if index - 1 % 4 == 0 then
        data = inode .. data:sub(129)
    elseif index % 4 == 0 then
        data = data:sub(1, 384) .. inode
    else
        data = data:sub(1, (index - 1) % 4 * 128) .. inode .. data:sub(index % 4 * 128 + 1)
    end

    drive.writeSector(10 + startSector + math.ceil(index / 4), data)

    return index
end

local function strToBytes(str)
    local bytes = 0

    for i = 1, #str do
        bytes = bytes + (str:sub(i, i):byte() << (i - 1) * 8)
    end

    return bytes
end

local function appendInodeEntry(inode, entry)
    local dataBlock = strToBytes(drive.readSector(10 + startSector + math.ceil(inode / 4)):sub((inode - 1) % 4 * 128 + 41, (inode - 1) % 4 * 128 + 44))
    local data = drive.readSector((dataBlock + 1) * 2 - 1) .. drive.readSector((dataBlock + 1) * 2)
    local offset = 0

    while true do
        offset = offset + strToBytes(data:sub(5 + offset, 6 + offset))

        if strToBytes(data:sub(5 + offset, 6 + offset)) == 0 then
            data = data:sub(1, offset) .. entry
            break
        end

        if offset + strToBytes(data:sub(5 + offset, 6 + offset)) == 1024 then
            local entryLength = 8 + strToBytes(data:sub(7 + offset, 7 + offset))
            if entryLength % 4 ~= 0 then
                entryLength = entryLength + 4 - entryLength % 4
            end

            data = data:sub(1, 4 + offset) .. bytesToStr(entryLength, 2) .. data:sub(7 + offset)
            offset = offset + entryLength
            data = data:sub(1, offset) .. entry

            break
        end
    end

    drive.writeSector((dataBlock + 1) * 2 - 1, data:sub(1, 512))
    drive.writeSector((dataBlock + 1) * 2, data:sub(513, 1024))
end

local function changeInodeField(index, startPos, endPos, data)
    local inode = drive.readSector(10 + startSector + math.ceil(index / 4))

    if type(data) == "string" then
        inode = inode:sub(1, startPos - 1) .. data .. inode:sub(endPos + 1)
    else
        inode = inode:sub(1, startPos - 1) .. bytesToStr(data, endPos - startPos + 1) .. inode:sub(endPos + 1)
    end

    drive.writeSector(10 + startSector + math.ceil(index / 4), inode)
end

local function findParentAddr(path)
    local currentPath, currentInode, entryOffset = "", 2, strToBytes(drive.readSector(11 + startSector):sub(169, 172))

    for entry in path:gmatch("/?([^/\x00]+)/?") do
        local currentEntry, offset = drive.readSector((entryOffset + 1) * 2 - 1), 0
        local nextInode

        while true do
            local nameLength = currentEntry:sub(7 + offset, 7 + offset):byte()
            local filename = currentEntry:sub(9 + offset, 9 + nameLength + offset - 1)
            nextInode = strToBytes(currentEntry:sub(1 + offset, 4 + offset))

            if currentPath .. entry == path then
                return currentInode
            end

            if filename == entry then
                currentPath = currentPath .. filename .. "/"
                entryOffset = strToBytes(drive.readSector(10 + startSector + math.ceil(nextInode / 4)):sub((nextInode - 1) % 4 * 128 + 41, (nextInode - 1) % 4 * 128 + 44))

                break
            end

            offset = offset + strToBytes(currentEntry:sub(5 + offset, 6 + offset))
        end

        currentInode = nextInode
    end
end

local function getAllEntriesSize(inode)
    local dataBlock = strToBytes(drive.readSector(10 + startSector + math.ceil(inode / 4)):sub((inode - 1) % 4 * 128 + 41, (inode - 1) % 4 * 128 + 44))
    local data = drive.readSector((dataBlock + 1) * 2 - 1) .. drive.readSector((dataBlock + 1) * 2)
    local offset = 0

    while true do
        if offset + strToBytes(data:sub(5 + offset, 6 + offset)) == 1024 then
            offset = offset + 8 + strToBytes(data:sub(7 + offset, 7 + offset))
            return offset + 4 - offset % 4
        end

        offset = offset + strToBytes(data:sub(5 + offset, 6 + offset))
    end
end

local function createDirEntry(name, data, ...)
    local dirEntry = ""

    local function appendDirEntry(value, length)
        if type(value) == "string" then
            dirEntry = dirEntry .. value
        else
            dirEntry = dirEntry .. bytesToStr(value, length)
        end
    end

    local typeEnum = {}
    typeEnum[0x1] = 0x5
    typeEnum[0x2] = 0x3
    typeEnum[0x4] = 0x2
    typeEnum[0x6] = 0x4
    typeEnum[0x8] = 0x1
    typeEnum[0xA] = 0x7
    typeEnum[0xC] = 0x6

    local filename = name:match(".+/(.+)") or name
    local newInode = createInode(data or "", ...)
    local parent = findParentAddr(name)
    
    appendDirEntry(newInode, 4)
    appendDirEntry(1024 - getAllEntriesSize(parent), 2)
    appendDirEntry(#filename & 0xFF, 1)
    appendDirEntry(typeEnum[table.pack(...)[1] >> 12] or 0, 1)
    appendDirEntry(filename, #filename)

    appendInodeEntry(parent, dirEntry)
    changeInodeField(parent, (parent - 1) % 4 * 128 + 27, (parent - 1) % 4 * 128 + 28, strToBytes(drive.readSector(10 + startSector + math.ceil(parent / 4)):sub((parent - 1) % 4 * 128 + 27, (parent - 1) % 4 * 128 + 28)) + 1)
    appendInodeEntry(newInode, bytesToStr(newInode, 4) .. "\x0C\x00\x01\x02.\x00\x00\x00")
    appendInodeEntry(newInode, bytesToStr(parent, 4) .. "\xF4\x03\x02\x02..\x00\x00")
end

createInode("", 0x4000, 0x1ED, 0, 0, 2) -- root inode
appendInodeEntry(2, "\x02\x00\x00\x00\x0C\x00\x01\x02.\x00\x00\x00")
appendInodeEntry(2, "\x02\x00\x00\x00\xF4\x03\x02\x02..\x00\x00")

createDirEntry("lost+found", nil, 0x4000, 0x1C0, 0, 0)
local numInodes = 1

status("Fetching file list")
local handle = internet.request("https://api.github.com/repos/Sencres013/Minux/git/trees/master?recursive=1")
local fileData, chunk = ""

repeat
    computer.pullSignal(0)
    connected = handle.finishConnect()
until connected

status("Reading file list")
repeat
    chunk = handle.read(math.huge)
    fileData = fileData .. (chunk or "")
until not chunk

if fileData == "" then
    status("Could not read file list. Rebooting...", 1)
    sleep(5)
    computer.shutdown(true)
end

handle.close()
status("Loaded file list", 0)

local repo, numDirs = "https://raw.githubusercontent.com/Sencres013/Minux/master/", 2

for dir in fileData:gmatch('"path":"([^%.][%w/%. _%-]-)"[^b]-"type":"tree"') do
    status("Creating directory " .. dir)
    createDirEntry(dir, nil, 0x4000, 0x1ED, 0, 0)
    status("Created directory", 0)

    numDirs = numDirs + 1
    numInodes = numInodes + 1
end

for file in fileData:gmatch('"path":"([^%.][%w/%. _%-]-)"[^t]-"type":"blob"') do
    status("Fetching file " .. file)
    local handle = internet.request(repo .. file)
    local data, chunk = ""

    repeat
        computer.pullSignal(0)
        connected = handle.finishConnect()
    until connected

    status("Reading file data")
    repeat
        chunk = handle.read(math.huge)
        data = data .. (chunk or "")
    until not chunk

    handle.close()

    if file == "boot/bios.lua" then
        status("Flashing BIOS")
        eeprom.set(data)
        status("Flashed BIOS", 0)
    end

    status("Creating file")
    createDirEntry(file, data, 0x8000, 0x1ED, 0, 0)
    status("Created file", 0)

    numInodes = numInodes + 1
end

local freeBlocks = capacity / blockSize - 1
for i = 1, math.ceil(capacity / blockSize / 8) do
    for j = 0, 7 do
        if blockBitmap:sub(i, i):byte() & (1 << j) == 1 << j then
            freeBlocks = freeBlocks - 1
        end
    end
end

if capacity / blockSize % 8 ~= 0 then
    freeBlocks = freeBlocks + (8 - capacity / blockSize % 8)
end
freeBlocks = freeBlocks + 1

superblock = superblock:sub(1, 12) .. bytesToStr(freeBlocks, 4) .. bytesToStr(totalInodes - numInodes - 10, 4) .. superblock:sub(21)
GDT = GDT:sub(1, 12) .. bytesToStr(freeBlocks, 2) .. bytesToStr(totalInodes - numInodes - 10, 2) .. bytesToStr(numDirs, 2)

superblock = superblock:sub(1, 48) .. bytesToStr(math.floor(os.time()), 4) .. superblock:sub(53)

status("Writing metadata")
drive.writeSector(1, MBR)
drive.writeSector(2, MBRext:sub(1, 512))
drive.writeSector(3, MBRext:sub(513, 1024))
drive.writeSector(3 + startSector, superblock)
drive.writeSector(5 + startSector, GDT)
drive.writeSector(7 + startSector, blockBitmap:sub(1, 512))
drive.writeSector(8 + startSector, blockBitmap:sub(513, 1024))
drive.writeSector(9 + startSector, inodeBitmap:sub(1, 512))
drive.writeSector(10 + startSector, inodeBitmap:sub(513, 1024))
status("Wrote metadata", 0)

status("Rebooting...")
sleep(3)
computer.shutdown(true)