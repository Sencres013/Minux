local fs = component.proxy(component.invoke(component.list("eeprom")(), "getData"))
local package = {
    loaded = {},
    loading = {},
    path = "/bin/:/sbin/",
    searchpath = function(self, name, path)
        checkArg(1, name, "string")

        path = path or self.path

        for subPath in path:gmatch("([^:]+)") do
            if name:sub(1, 1) == "/" then
                name = name:sub(2)
            end

            if name:match(".+%.") then
                name = name:sub(1, name:match(".+()%.") - 1)
            end

            local fullPath = subPath .. name .. ".lua"

            if fs.exists(fullPath) and not fs.isDirectory(fullPath) then
                return fullPath
            end
        end
    
        return error("cannot find module " .. name)
    end
}

function package.require(file)
    if package.loaded[file] then
        return package.loaded[file]
    end

    if package.loading[file] then
        error(debug.traceback("already loading " .. file))
    end

    package.loading[file] = true
    package.loaded[file] = dofile(package:searchpath(file), fs) or true
    package.loading[file] = nil

    return package.loaded[file]
end

return package