function Print( t, params )
	local p = params and params or {}
	local excludeList = type(p.exclude) == "string" and { p.exclude } or type (p.exclude) == "table" and p.exclude or {}

	local function isException(e)
		for k, v in pairs(excludeList) do
			if e == v then
				return true
			end
		end

		return false
	end

	local printTable_cache = {}
	
	local function sub_printTable( t, indent )
		if ( printTable_cache[tostring(t)] ) then
			print( indent .. "*" .. tostring(t) )
		else
			printTable_cache[tostring(t)] = true
			if ( type( t ) == "table" ) then
				for pos, val in pairs( t ) do
					if not isException(pos) then
						if ( type(val) == "table" ) then
							print( indent .. "[" .. pos .. "] => " .. tostring( t ).. " {" )
							sub_printTable( val, indent .. string.rep( " ", 6 ) )
							print( indent .. " " .. "}" )
						elseif ( type(val) == "string" ) then
							print( indent .. "[" .. pos .. '] => "' .. val .. '"' )
						else
							print( indent .. "[" .. pos .. "] => " .. tostring(val) )
							end
						end
					end
				else
				print( indent..tostring(t) )
			end
		end
	end

	if ( type(t) == "table" ) then
		print( tostring(t) .. " {" )
		sub_printTable( t, "    " )
		print( "}" )
	else
		sub_printTable( t, "    " )
	end
end


--[[ require "ORM.Table"










print("ORM begins")




local table = Table{
	Table:id(),
	Table:varchar("first_name", 255):notNull(),
	Table:varchar("last_name", 255):notNull(),
	Table:varchar("login", 255):notNull():unique(),
	Table:varchar("password_hash", 255):notNull(),
	Table:date("birth_date"):notNull(),
}
 ]]