local lfs = require("lfs")
local Model = require(_FRAMEWORK .. "dataBase.model.Model")
local DbModel = require(_FRAMEWORK .. "dataBase.model.DbModel")

local seedersDir = "lua.src.seeders."

MODELS = "lua.src.models."
SEEDERS = seedersDir

local dataBaseControllerObject

local DataBaseController = {
    isDir = function(self, filePath)
        local result, err = lfs.chdir(filePath)

        if result then
            return true
        else
            return false
        end
    end;

    traverseDirectory = function(self, shortPath)
        local files = {}
        local lastVersionDirectoryName
        local path = system.pathForFile(shortPath)

        if lfs.chdir(path) then
            for entry in lfs.dir(path) do
                if entry ~= "." and entry ~= ".." then 
                    local ePath = system.pathForFile(shortPath .. "/" .. entry)

                    if not self:isDir(ePath) then
                        files[#files + 1] = require(shortPath:gsub("/", ".") .. "." .. entry:gsub(".lua", ""))
                    else
                        lastVersionDirectoryName = entry
                        SEEDERS = seedersDir .. entry .. "."

                        for i, v in ipairs(self:traverseDirectory(shortPath .. "/" .. entry)) do
                            if not files[entry] then 
                                files[entry] = {
                                    add = function(self, value)
                                        self[#self + 1] = value
                                    end
                                }
                            end

                            files[entry]:add(v)
                        end
                    end
                end
            end
        end

        return files, lastVersionDirectoryName
    end;

    collectModels = function(self)
        local models, dir
        local shortPath = "lua/src/models"

        if system.getInfo("platform") == "android" then
            dir = "v-" .. self.settings.targetVersion

            models = {
                [dir] = {
                    add = function(self, value)
                        self[#self + 1] = value
                    end
                }
            }

            local modelClasses = self.settings.models
            
            for i, v in ipairs(modelClasses) do
                local status, model = pcall(function() return require(shortPath:gsub("/", ".") .. "." .. dir .. "." .. v) end)
                models[dir]:add(status and model or nil)
            end
        else
            models, dir = self:traverseDirectory(shortPath)
        end

        MODELS = MODELS .. dir .. "."
        
        return models
    end;
    
    collectSeeders = function(self)
        local shortPath = "lua/src/seeders"
        local seeders, dir

        if system.getInfo("platform") == "android" then
            dir = "v-" .. self.settings.targetVersion

            seeders = {
                [dir] = {
                    add = function(self, value)
                        self[#self + 1] = value
                    end
                }
            }

            local seederClasses = self.settings.seeders

            for i, v in ipairs(seederClasses) do
                local status, seeder = pcall(function() return require(shortPath:gsub("/", ".") .. "." .. dir .. "." .. v .. "Seeder") end)
                seeders[dir]:add(status and seeder or nil)
            end
        else
            seeders, dir = self:traverseDirectory(shortPath)
        end

        SEEDERS = seedersDir .. dir .. "."

        return seeders
    end;

    new = function(self, settings)
        if not dataBaseControllerObject then
            dataBaseControllerObject = {}

            self.settings = settings

            DbModel:migrate()

            if DB_VERSION > DbModel:getMaxVersion() then
                local dbModel = DbModel{ version = DB_VERSION }

                local models = self:collectModels()
                local seeders = self:collectSeeders()

                for k, v in pairs(models) do
                    for i = 1, #v do
                        v[i]:migrate()
                    end

                    Model():setUpForeignKeyConstraints()

                    if seeders[k] then
                        for i = 1, #seeders[k] do
                            seeders[k][i]:seed()
                        end
                    end
                end
            else
                local models = self:collectModels()

                for k, s in pairs(models) do
                    for i, v in ipairs(s) do
                        v:restore()
                    end
                end

                Model():setUpForeignKeyConstraints(true)
            end
        
        end
    
        return dataBaseControllerObject
    end
}

return DataBaseController