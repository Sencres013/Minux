local gpu = component.proxy(component.list("gpu")())
local resX, resY = gpu.getResolution()
local cursorY = 1

while not gpu.bind(component.list("screen")(), true) do
    computer.pullSignal(0)
end

::searchBoot::
local bootDrive
for drive in component.list("drive", true) do
    local sigByte1, sigByte2 = string.byte(component.invoke(drive, "readSector", 1), 511, 512)
    if sigByte2 == 0xAA and sigByte1 == 0x55 then
        bootDrive = component.proxy(drive)
    end
end

local cursorY = 1
if not bootDrive then
    if cursorY > resY then
        cursorY = resY
        gpu.copy(1, 2, resX, resY - 1, 0, -1)
        gpu.fill(1, resY, resX, 1, " ")
    end

    gpu.set(1, cursorY, "No bootable device found. Insert a bootable device, then press any key")
    cursorY = cursorY + 1
    
    while true do
        local result = computer.pullSignal()

        if result[1] == "key_down" then
            goto searchBoot
        end
    end
end

local MBR, MBRdata = { partitions = {} }, bootDrive.readSector(1)
local partOffset = 447

local function relOffset(partIndex, offset)
    return (partIndex - 1) * 16 + offset + partOffset
end

local function getByte(index)
    return MBRdata:byte(index)
end

local function getBytes(starti, endi)
    local bytes, byteList = 0, table.pack(MBRdata:byte(starti, endi))

    for i = 1, #byteList do
        bytes = bytes + (byteList[#byteList - i + 1] << (i - 1) * 8)
    end

    return bytes
end

for i = 1, 4 do
    MBR.partitions[i] = {
        status = getByte(relOffset(i, 0)) == 0x40 and "active" or getByte(relOffset(i, 0)) == 0x0 and "inactive" or "invalid",
        type = getByte(relOffset(i, 4)) == 0x83 and "minuxfs" or "unknown",
        partStart = getBytes(relOffset(i, 8), relOffset(i, 11))
    }
    MBR.partitions[i].partEnd = (getBytes(relOffset(i, 12), relOffset(i, 15)) - MBR.partitions[i].partStart) / 512
end

local efi = ""

for i = 1, 4 do
    if MBR.partitions[i].status == "active" and MBR.partitions[i].type == "minuxfs" then
        
    end
end

if #efi == 0 then
    if cursorY > resY then
        cursorY = resY
        gpu.copy(1, 2, resX, resY - 1, 0, -1)
        gpu.fill(1, resY, resX, 1, " ")
    end

    gpu.set(1, cursorY, "Operating System not found")
    
    while true do
        computer.pullSignal()
    end
end

local result, err = load(efi, "=BIOSd", "t", _ENV)

if result then
    return result()
else
    error("kernel panic: " .. err)
end