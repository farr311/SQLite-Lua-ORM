local sqlite3 = require("sqlite3")
local List = require(_FRAMEWORK .. "util.collections.List")
local Property = require(_FRAMEWORK .. "dataBase.model.Property")

local function camelCaseToSnakeCase(str)
	return type(str) == "string" and tostring(str):gsub("/%u", function(s) return s:gsub("/", ""):lower() end ):gsub("%u", function(s)
		return "_" .. s:lower() end) or str
end

local function snakeCaseToCamelCase(str)
	return str:gsub("_%w", function(a) return a:gsub("_", ""):upper() end)
end

local function getFilename()
    local debugInfo = debug.getinfo(4)
    local fileSeparator = (TEST_BUILD or system.getInfo("environment") == "simulator") and package.config:sub(1,1) or "\\"
	local str = debugInfo.source:gsub(fileSeparator, "!"):gsub("-", "'"):gsub("%.lua", "")
	local tail = str:gsub(".*lua!src!.*", "")

    return camelCaseToSnakeCase("/" .. str:gsub(tail, ""):gsub("'", "-"):gsub(".*!", ""))
end

local dbPath = system.pathForFile("tasks_data.db", system.DocumentsDirectory)
local db = sqlite3.open(dbPath)
--local db = sqlite3.open_memory()

local function executeQuery(query)
    --print(query)
    local exitCode = db:exec(query)

    if exitCode == 0 then
        return 
    else
        if exitCode == 1 then
            print("Exited with error: *SQL SYNTAX ERROR*;\n*QUERY:*\n" .. query)
        end
    end

    return false
end

local propertyTypes = {
    INT = "INTEGER", LONG = "LONG", BOOLEAN = "BOOLEAN", TEXT = "TEXT", VARCHAR = "VARCHAR(%d)", DOUBLE = "DOUBLE"
}

local instances = List()

local Model = {
    new = function(self, migration)
        return {
            migration = migration;
            create = migration and migration.create;

            tableName = getFilename();
            includeTimestamps = true;
            softDeletable = true;
            properties = List();
            foreignKeyConstraints = List();
            associatedGetters = {};

            id = function(self)
                return self.properties:add(Property("id", propertyTypes.INT):pk():autoincrement():notNull())
            end;

            int = function(self, name)
                return self.properties:add(Property(name, propertyTypes.INT))
            end;

            long = function(self, name)
                return self.properties:add(Property(name, propertyTypes.LONG))
            end;

            boolean = function(self, name)
                return self.properties:add(Property(name, propertyTypes.BOOLEAN))
            end;

            varchar = function(self, size, name)
                return self.properties:add(Property(name, propertyTypes.VARCHAR:format(size)))
            end;

            text = function(self, name)
                return self.properties:add(Property(name, propertyTypes.TEXT))
            end;

            double = function(self, name)
                return self.properties:add(Property(name, propertyTypes.DOUBLE))
            end;

            createTable = function(self)
                executeQuery(([[CREATE TABLE IF NOT EXISTS %s (%s)]]):format(self:getTableName(), self:normalizeProperties()))
            end;

            disableTimestamps = function(self)
                self.includeTimestamps = false
            end;

            disableSoftDeleting = function(self)
                self.softDeletable = false
            end;

            normalizeProperties = function(self)
                local propertiesList = {} 

                for i = 1, self.properties:size() do
                    local property = self.properties:get(i)

                    if not property:isForeignKey() then
                        table.insert(propertiesList, property:query())
                    else
                        self.foreignKeyConstraints:add{
                            property = property,
                            fk = self:getTableName() .. " " .. property:queryForeignKey()
                        }
                    end
                end

                return "\n\t" .. table.concat(propertiesList, ",\n\t") .. "\n"
            end;

            migrate = function(self)
                self:create()

                if self.includeTimestamps then
                    self:long("created_at")
                    self:long("updated_at")
                end

                if self.softDeletable then
                    self:boolean("is_deleted"):default(0)
                end

                self:createTable()
                self:restore(false)
            end;

            restore = function(self, created)
                created = created == nil and true

                if created then
                    for i, v in ipairs(self:rawSelect(([[PRAGMA table_info('%s');]]):format(self:getTableName()))) do
                        local isFk = v.name:match("%w+_id") and true or false
                        local tbl = isFk and v.name:gsub("_id", "") or nil
                        local col = isFk and "id" or nil
                        local property = Property(v.name, v.type, isFk, tbl, col)

                        self.properties:add(property)

                        if property:isForeignKey() then
                            self.foreignKeyConstraints:add{ property = property }
                        end
                    end
                end

                for k, v in pairs(migration) do
                    if not self[k] then
                        self[k] = v
                    end
                end

                instances:add(self)
                setmetatable(self, { __call = function(t, a) return self:new(a) end })
            end;
        
            setUpForeignKeyConstraints = function(self, restoreMode)
                for i = 1, instances:size() do
                    local instance = instances:get(i)

                    for j = 1, instance.foreignKeyConstraints:size() do
                        local propertyWrap = instance.foreignKeyConstraints:get(j)
                        local property = propertyWrap.property

                        local referenceTable = property:getReferenceTableName()
                        local referenceColumn = property:getReferenceColumnName()

                        local getterFunctionName = "get" .. snakeCaseToCamelCase(referenceTable):gsub("^%l", string.upper)

                        instance.associatedGetters[getterFunctionName] = function(t)
                            local val = t[property:getName()]

                            if val then
                                -- IF one to one
                                return instance:rawSelect(([[SELECT * FROM %s WHERE id = %s]]):format(referenceTable, val))[1]
                            end
                        end

                        if not restoreMode then
                            executeQuery(("ALTER TABLE %s%s"):format(propertyWrap.fk, " ON DELETE CASCADE"))
                        end
                    end
                end
            end;
        
            rawSelect = function(self, query)
                local returnTable = {}
        
                local q = query and query or [[SELECT * FROM ]] .. self.tableName
        
                for row in db:nrows(q) do
                    returnTable[#returnTable + 1] = row
                end
        
                return returnTable
            end;

            rawQuery = function(self, query)            
                return executeQuery(query)
            end;
        
            getTableName = function(self)
                return self.tableName
            end;

            getPropertyType = function(self, name)
                for i = 1, self.properties:size() do
                    if self.properties:get(i):getName() == name then
                        return self.properties:get(i):getType()
                    end
                end
            end;

            factory = function(self, data)
                local model = self
                local modelObject = {
                    data = data;
                    commit = function(self)
                        local values = {}

                        for k, v in pairs(self.data) do
                            if k ~= "id" then
                                values[k] = v
                            end
                        end

                        values.updatedAt = os.time()

                        local normalizedColumns = model:normalizeColumns(values)
                        local normalizedValues = model:normalizeValues(values):toArray()
                        local columnValuePairs = {}

                        for i = 1, #normalizedColumns do
                            columnValuePairs[i] = normalizedColumns[i] .. " = " .. tostring(normalizedValues[i])
                        end

                        local setCondition = "\n\t" .. table.concat(columnValuePairs, ", \n\t") .. "\n"

                        executeQuery(([[UPDATE %s SET %s WHERE id = %s]]):format(model:getTableName(), setCondition, self.data.id))
                    end;
                }

                function modelObject:refresh()
                    modelObject.data = model:get(data.id).data
                    return self
                end

                if model.softDeletable then
                    function modelObject:softDelete()
                        self:setIsDeleted(true)
                        self:commit()
                    end
                end

                setmetatable(modelObject, { __index = function(self, key)
                    if key == "getAll" then
                        return function(self)
                            local d = {}

                            for k, v in pairs(self.data) do
                                if v ~= "NULL" then
                                    d[snakeCaseToCamelCase(k)] = v
                                end
                            end

                            return d
                        end
                    elseif key:match("get.*") then
                        if model.associatedGetters[key] then
                            return function() return model.associatedGetters[key](self.data) end
                        else
                            local k = model[key] or model[camelCaseToSnakeCase(key)]

                            if k then
                                return function(self, ...) return model[k](model, ...) end
                            end

                            return function(self)
                                key = key:gsub("get", "", 1):gsub("^%L", string.lower)

                                local value = self.data[key] 
                                
                                if not value then
                                    key = camelCaseToSnakeCase(key)
                                    value = self.data[key]
                                end
                                
                                if value == "NULL" then
                                    return nil
                                end

                                if model:getPropertyType(key) == propertyTypes.BOOLEAN then
                                    return (value == "TRUE" or value == 1 or value == "true" or value == true) and true or false
                                end

                                return value
                            end
                        end
                    elseif model[key] or key:match("set.*") then
                        return function(self, value)
                            key = key:gsub("set", "", 1):gsub("^%L", string.lower)

                            local k = self.data[key] and key or camelCaseToSnakeCase(key)

                            self.data[k] = value
                        end
                    end
                end })

                return modelObject
            end;

            normalizeColumns = function(self, columnData, filtered)
                local filtered = filtered == nil and true or filtered
                local sortedData = {}
                local normalizedColumns = {}

                if filtered then
                    for i = 1, self.properties:size() do
                        local pName = self.properties:get(i):getName()
                        
                        for k, v in pairs(columnData) do
                            if type(k) == "number" and v == pName or camelCaseToSnakeCase(v) == pName 
                                or k == pName or camelCaseToSnakeCase(k) == pName then
                                sortedData[#sortedData + 1] = pName
                            end
                        end
                    end
                else
                    for k, v in pairs(columnData) do
                        if type(k) == "number" then
                            sortedData[#sortedData + 1] = v
                        end
                    end
                end

                for i = 1, #sortedData do
                    normalizedColumns[i] = sortedData[i]
                end

                return normalizedColumns
            end;

            normalizeValue = function(self, propertyType, value)
                local v

                if propertyType then
                    if propertyType == propertyTypes.BOOLEAN then
                        v = (value == true or value == "true" or value == 1 or value == "TRUE") and 1 or 
                            (value == false or value == "false" or value == 0 or value == "FALSE") and 0
                    elseif 
                        propertyType:match(propertyTypes.VARCHAR:gsub("%(%%d%)", "%%(%%d*%%)")) or
                        propertyType == propertyTypes.TEXT
                    then
                        v = "'" .. tostring(value):gsub("'", "''") .. "'"

                        --[[ if v and v:lower() == "' null'" then
                            v = v:gsub(" ", "")
                        end ]]
                    else
                        v = value
                    end
                else
                    if type(value) == "boolean" then
                        value = value == true and 1 or 0
                    end

                    return value
                end

                return v
            end;

            normalizeValues = function(self, data, filtered)
                local filtered = filtered == nil and true or filtered
                local sortedData = {}
                local values = {}

                if filtered then
                    for i = 1, self.properties:size() do
                        local property = self.properties:get(i)
                        local propertyName = property:getName()
                        local propertyType = property:getType()
                        
                        for k, v in pairs(data) do
                            if type(k) == "number" then
                                sortedData[#sortedData + 1] = { value = v }
                            else
                                if camelCaseToSnakeCase(k) == propertyName or k == propertyName then
                                    sortedData[#sortedData + 1] = { name = propertyName, value = v, type = propertyType }
                                end
                            end
                        end
                    end
                else
                    for i = 1, #data do
                        sortedData[i] = { value = data[i], type = data.type }
                    end
                end

                for i = 1, #sortedData do
                    local d = sortedData[i]

                    values[i] = { name = d.name, value = self:normalizeValue(d.type, d.value) }
                end

                function values:toArray()
                    local array = {}

                    for i = 1, #self do
                        array[i] = self[i].value
                    end

                    return array
                end;

                function values:toMap()
                    local map = {}

                    for i = 1, #self do
                        map[self[i].name] = self[i].value
                    end

                    return map
                end;

                return values
            end;

            isAggregate = function(self, column)
                if column[1] == "COUNT(*)" then 
                    return true
                end
            end;

            normalizeColumn = function(self, column)
                for i = 1, self.properties:size() do
                    local propertyName = self.properties:get(i):getName()
                    
                    if camelCaseToSnakeCase(column) == propertyName or column == propertyName then
                        return propertyName
                    end
                end

                return column
            end;

            new = function(self, data)
                data.createdAt = os.time()
                data.updatedAt = os.time()

                local query = ([[INSERT INTO %s (%s) VALUES (%s);]]):format(
                                                                        self:getTableName(), 
                                                                        table.concat(self:normalizeColumns(data), ", "), 
                                                                        table.concat(self:normalizeValues(data):toArray(), ", "))
                executeQuery(query)

                local idQuery = ([[SELECT last_insert_rowid() AS id FROM %s LIMIT 1]]):format(self:getTableName())

                return self:get(self:rawSelect(idQuery)[1].id)
            end;

            get = function(self, id)
                return self:factory(self:rawSelect(([[SELECT * FROM %s WHERE id = %s;]]):format(self:getTableName(), id))[1])
            end;

            select = function(self, data, includeSoftDeleted)
                local columns = "*"
                local condition = ""
                local orderCondition = ""
                local groupCondition = ""
                local limitCondition = ""
                local offsetCondition = ""
                local isAggregate = false
                local isGrouped = false

                if data then
                    isAggregate = #data == 1 and self:isAggregate(data)
                    
                    columns = table.concat(self:normalizeColumns(data, false), ", ")
                end

                function self:where(data)
                    local conditionString = nil
                    if type(data) == "table" then
                        for k, v in pairs(data) do
                            conditionString = not conditionString and " WHERE " or conditionString .. " AND "

                            if type(v) == "table" then
                                if #v == 2 and type(v[1]) == "string" and v[1] == "<" or v[1] == ">" then
                                    conditionString = conditionString .. self:normalizeColumn(k) .. " " .. v[1] .. " " ..
                                                        self:normalizeValues({v[2], type = propertyTypes.INT}, false):toArray()[1]
                                else
                                    v.type = type(v[1]) == "string" and propertyTypes.TEXT or propertyTypes.INT
                                    conditionString = conditionString .. self:normalizeColumn(k) .. " IN (" .. 
                                                    table.concat(self:normalizeValues(v, false):toArray(), ", ") .. ")"
                                end
                            else
                                if type(k) ~= "number" then
                                    local operator = type(v) == "string" and v:upper() == "NULL" and " IS " or " = "

                                    local pattern = "[<=|>=|>|<|!]"

                                    for match in k:gmatch(pattern) do
                                        operator = match == "!" and " != " or " " ..  match .. " "
                                        break
                                    end

                                    k = k:gsub(pattern, "")

                                    conditionString = conditionString .. self:normalizeColumn(k) .. operator .. 
                                                        tostring(self:normalizeValues{ [self:normalizeColumn(k)] = v }:toArray()[1])
                                else
                                    conditionString = conditionString .. tostring(self:normalizeValues{ [k] = v }:toArray()[1])
                                end
                            end
                        end
                    elseif type(data) == "string" then
                        conditionString = " WHERE " .. data
                    else
                        conditionString = ""
                    end

                    condition = conditionString

                    return self
                end

                function self:order(order)
                    local orderString

                    if type(order) == "table" then
                        orderString = ""
                        for k, v in pairs(order) do
                            orderString = (orderString == "" and " ORDER BY " or orderString .. ", ") .. self:normalizeColumn(k) .. 
                                            " " .. (v == 1 and "ASC" or "DESC")
                        end
                    elseif type(order) == "string" then
                        orderString = " ORDER BY " .. order
                    else
                        orderString = ""
                    end

                    orderCondition = orderString

                    return self
                end

                function self:group(group)
                    local groupString

                    if type(group) == "table" then
                        groupString = ""
                        for _, g in ipairs(group) do
                            groupString = (groupString == "" and " GROUP BY " or groupString .. ", ") .. self:normalizeColumn(g)
                        end
                    elseif type(group) == "string" then
                        groupString = " GROUP BY " .. group
                    else
                        groupString = ""
                    end

                    if groupString ~= "" then
                        isGrouped = true
                    end

                    groupCondition = groupString

                    return self
                end

                function self:limit(lim)
                    limitCondition = type(lim) == "number" and " LIMIT " .. lim or ""
                    return self
                end

                function self:offset(offset)
                    offsetCondition = type(offset) == "number" and " OFFSET " .. offset or ""
                    return self
                end

                function self:fetch()
                    if not includeSoftDeleted then
                        condition = condition == "" and " WHERE is_deleted = 0" or condition .. " AND is_deleted = 0"
                    end

                    local query = ([[SELECT %s FROM %s%s%s%s%s%s;]]):format(columns, self:getTableName(), condition, orderCondition,
                                                                                groupCondition, limitCondition, offsetCondition)
                    local selected = self:rawSelect(query)

                    local selectedObjectsList = List(#selected)

                    if isAggregate then
                        -- TODO: return a special container holding aggregated info
                        -- TODO: this container must include special methods for data analysis
                        if isGrouped then
                            return selected
                        end

                        return selected[1]["COUNT(*)"]
                    else
                        for i = 1, #selected do
                            selectedObjectsList:add(self:factory(selected[i]))
                        end
                    end

                    return selectedObjectsList
                end

                return self
            end;

            count = function(self, rows)
                return self:select(rows and rows or { "COUNT(*)" })
            end;
        }
    end;
}

setmetatable(Model, { __call = function(t, a) return Model:new(a) end })

return Model