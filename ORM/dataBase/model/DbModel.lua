local Model = require(_FRAMEWORK .. "dataBase.model.Model")

local DbModel = Model {
    create = function(self)
        self:id();
        self:int("version")
    end;

    getMaxVersion = function(self)
        return self:rawSelect(([[SELECT MAX(version) AS m FROM %s]]):format(self:getTableName()))[1]["m"] or 0
    end;
}

return DbModel