local colors = setmetatable({
    words = {
        white = 0,
        orange = 1,
        magenta = 2,
        lightblue = 3,
        yellow = 4,
        lime = 5,
        pink = 6,
        gray = 7,
        silver = 8,
        cyan = 9,
        purple = 10,
        blue = 11,
        brown = 12,
        green = 13,
        red = 14,
        black = 15
    },
    numbers = {
        "white",
        "orange",
        "magenta",
        "lightblue",
        "yellow",
        "lime",
        "pink",
        "gray",
        "silver",
        "cyan",
        "purple",
        "blue",
        "brown",
        "green",
        "red",
        "black"
    }
}, {
    __index = function(t, k)
        if type(k) == "number" then
            return t.numbers[k + 1]
        else
            return t.words[k]
        end
    end
})

return colors