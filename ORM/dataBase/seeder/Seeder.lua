local List = require(_FRAMEWORK .. "util.collections.List")
local Map = require(_FRAMEWORK .. "util.collections.Map")

local seeders = Map()
local seeded = List()
local dependencies = Map()

local function getFilename()
    local debugInfo = debug.getinfo(4)
    local fileSeparator = TEST_BUILD and package.config:sub(1,1) or "\\"
	local str = debugInfo.source:gsub(fileSeparator, "!"):gsub("-", "'"):gsub("%.lua", "")
	local tail = str:gsub(".*lua!src!.*", "")

    return str:gsub(tail, ""):gsub("'", "-"):gsub(".*!", "")
end

local Seeder = {
    new = function(self, implementation)
        return {
            implementation = implementation;
            seederName = getFilename();
            class = self;

            seed = function(self)
                implementation.seederName = self.seederName
                implementation.class = self.class
                implementation.dependantSeeders = List()

                function implementation:runDependant()
                    local entrySet = dependencies:getEntrySet()

                    for i = 1, entrySet:size() do
                        local entry = entrySet:get(i)
                        local seederName = entry:getKey()
                        local dependenciesList = entry:getValue()

                        if dependenciesList:size() == 0 or 
                            (dependenciesList:size() == 1 and dependenciesList:get(1) == self.seederName) then

                            local seeder = seeders:get(seederName)
                            if seeder then
                                self.class:seed(seeder)
                            end
                        end
                    end
                end

                seeders:add(self.seederName, implementation)

                local allowSeeding = not (type(implementation.dependencies) == "table" and implementation.dependencies[1])
                                        and true or self:checkDependecies(implementation.dependencies)

                if allowSeeding then
                    self.class:seed(implementation)
                else
                    if not dependencies:get(implementation.seederName) then
                        dependencies:add(implementation.seederName, List())
                        end

                    for i = 1, #implementation.dependencies do
                        if not seeded:contains(implementation.dependencies[i]) then
                            dependencies:get(implementation.seederName):add(implementation.dependencies[i])
                        end
                    end
                end
            end;

            checkDependecies = function(self, dependencies)
                for i = 1, #dependencies do
                    if not seeded:contains(dependencies[i]) then
                        return false
                    end
                end
        
                return true
            end;
        }
    end;

    seed = function(self, seeder)
        seeder:seed()
        seeded:add(seeder.seederName)
        seeders:remove(seeder.seederName)

        local entrySet = dependencies:getEntrySet()

        for i = 1, entrySet:size() do
            local entry = entrySet:get(i)
            local key = entry:getKey()
            local value = entry:getValue()

            if value:contains(seeder.seederName) then
                value:remove(seeder.seederName)
            end
        end

        if type(seeder.runDependant) == "function" then
            seeder:runDependant()
        end
    end;

    randomString = function(self, l1, l2)
        l1 = l1 or 1
        l2 = l2 or 99
        local chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
        local length = math.random(l1, l2)
        local str = ""

        charTable = {}
        for c in chars:gmatch"." do
            table.insert(charTable, c)
        end

        for i = 1, length do
            str = str .. charTable[math.random(1, #charTable)]
        end

        return str
    end;
}

setmetatable(Seeder, { __call = function(t, a) return Seeder:new(a) end })

return Seeder