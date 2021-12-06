local Property = {
    new = function(self, name, dataType, isFk, ref, col)
        return {
            name = name;
            type = dataType;
            contraints = "";
            foreignKey = isFk or false;
            onDelete = "CASCADE";
            referenceTable = ref;
            refernceColumn = col;

            pk = function(self)
                self.contraints = self.contraints .. " PRIMARY KEY"

                function self:autoincrement()
                    self.contraints = self.contraints .. " AUTOINCREMENT"
                    return self
                end

                return self
            end;

            fk = function(self)
                self.foreignKey = true

                function self:ref(tableName)
                    self.referenceTable = tableName

                    function self:on(columnName)
                        self.refernceColumn = columnName
                        return ("%s %s%s"):format(self.name, self.type, self.contraints)
                    end

                    return self
                end

                function self:queryForeignKey()
                    return ("ADD COLUMN %s %s REFERENCES %s(%s)"):format(self.name, self.type, self.referenceTable, self.refernceColumn)
                end

                if self.name:find("_id") then
                    self:ref(self.name:gsub("_id", "")):on("id")
                end

                return self
            end;

            getReferenceTableName = function(self)
                return self.referenceTable
            end;

            getReferenceColumnName = function(self)
                return self.refernceColumn
            end;

            isForeignKey = function(self)
                return self.foreignKey
            end;

            notNull = function(self)
                self.contraints = self.contraints .. " NOT NULL"
                return self
            end;

            default = function(self, value)
                value = value == true and "TRUE" or value == false and "FALSE" or value
                self.contraints = self.contraints .. (" DEFAULT %s"):format(value)
                return self
            end;

            query = function(self)
                return ("%s %s%s"):format(self.name, self.type, self.contraints)
            end;

            getName = function(self)
                return self.name
            end;

            getType = function(self)
                return self.type
            end;
        }
    end;
}

setmetatable(Property, { __call = function(t, ...) return Property:new(...) end })

return Property