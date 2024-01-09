local gpu
while not gpu do
    computer.pullSignal(0)
    gpu = component.proxy(component.list("gpu")())
end

local resX, resY = gpu.getResolution()
local cursorY = 1

while not gpu.bind(component.list("screen")(), true) do
    computer.pullSignal(0)
end

local eeprom = component.proxy(component.list("eeprom")())

local bootDrive = eeprom.getData() or ""
local bootByteInsig, bootByteSig = string.byte(component.invoke(bootDrive, "readSector", 1) or "", 511, 512)
if bootByteSig == 0xAA and bootByteInsig == 0x55 then
    goto boot
end

::searchBoot::
for drive in component.list("drive", true) do
    bootByteInsig, bootByteSig = string.byte(component.invoke(drive, "readSector", 1), 511, 512)
    if bootByteSig == 0xAA and bootByteInsig == 0x55 then
        bootDrive = drive
        break
    end
end

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

::boot::
eeprom.setData(bootDrive)
bootDrive = component.proxy(bootDrive)

local result, err = load(bootDrive.readSector(1):sub(1, 200):match("(.+)\x00+"), "=MBR", "t")

if result then
    return result()
else
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