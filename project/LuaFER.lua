-- -----------------------------
-- Database functions
-- -----------------------------
-- Gets column data as text. From a query, at the current cursor position. Data convertet to string
function DBCursorGetColumnText(cursor, column)
  local buffer = mosync.SysAlloc(2048)
  local size = mosync.maDBCursorGetColumnText(cursor, column, buffer, 2047)
  local text = string.sub(mosync.SysBufferToString(buffer),1,size)
  mosync.SysFree(buffer)
  return text
end

-- -----------------------------
-- String escape
-- -----------------------------
local escapecodes = {
  ["\""] = "\\\"", ["\\"] = "\\\\", ["\b"] = "\\b", ["\f"] = "\\f",
  ["\n"] = "\\n",  ["\r"] = "\\r",  ["\t"] = "\\t"
}

local function escapeutf8 (uchar)
  local value = escapecodes[uchar]
  if value then
    return value
  end
  local a, b, c, d = string.byte (uchar, 1, 4)
  a, b, c, d = a or 0, b or 0, c or 0, d or 0
  if a <= 0x7f then
    value = a
  elseif 0xc0 <= a and a <= 0xdf and b >= 0x80 then
    value = (a - 0xc0) * 0x40 + b - 0x80
  elseif 0xe0 <= a and a <= 0xef and b >= 0x80 and c >= 0x80 then
    value = ((a - 0xe0) * 0x40 + b - 0x80) * 0x40 + c - 0x80
  elseif 0xf0 <= a and a <= 0xf7 and b >= 0x80 and c >= 0x80 and d >= 0x80 then
    value = (((a - 0xf0) * 0x40 + b - 0x80) * 0x40 + c - 0x80) * 0x40 + d - 0x80
  else
    return ""
  end
  if value <= 0xffff then
    return string.format ("\\u%.4x", value)
  elseif value <= 0x10ffff then
    -- encode as UTF-16 surrogate pair
    value = value - 0x10000
    local highsur, lowsur = 0xD800 + floor (value/0x400), 0xDC00 + (value % 0x400)
    return strformat ("\\u%.4x\\u%.4x", highsur, lowsur)
  else
    return ""
  end
end

local function fsub (str, pattern, repl) -- gsub always builds a new string in a buffer
  if string.find (str, pattern) then
    return string.gsub (str, pattern, repl)
  else
    return str
  end
end

local function quotestring (value)
  value = fsub (value, "[%z\1-\31\"\\\127]", escapeutf8)
  if string.find (value, "[\194\216\220\225\226\239]") then
    value = fsub (value, "\194[\128-\159\173]", escapeutf8)
    value = fsub (value, "\216[\128-\132]", escapeutf8)
    value = fsub (value, "\220\143", escapeutf8)
    value = fsub (value, "\225\158[\180\181]", escapeutf8)
    value = fsub (value, "\226\128[\140-\143\168\175]", escapeutf8)
    value = fsub (value, "\226\129[\160-\175]", escapeutf8)
    value = fsub (value, "\239\187\191", escapeutf8)
    value = fsub (value, "\239\191[\176\191]", escapeutf8)
  end
  return "\"" .. value .. "\""
end

-- -----------------------------
-- FERLua function
-- -----------------------------
FERLua = {}

FERLua.sql_true = "\'t\'"
FERLua.sql_false = "\'f\'"

FERLua.user_true = "DA"
FERLua.user_false = "NE"

FERLua.engLevel = {0,1,2,3}
FERLua.semesters = {1,2,3,4,5,6}

FERLua.languages = {"hr", "en"}

FERLua.user_undergrad = "P"
FERLua.user_graduate  = "D"
FERLua.sql_undergrad = "\'P\'"
FERLua.sql_graduate  = "\'D\'"

FERLua.isInteger = function (self, num)
  if tonumber(num) ~= nil then
    return math.floor(num) - num == 0
  end
  return false
end

FERLua.isOperator = function (self, oper)
  if oper == "<" or oper == ">" or oper == "=" then
    return true
  end
  return false
end

FERLua.isBool = function (self, bool)
  if bool == self.user_true or bool == self.user_false then
    return true
  end
  return false
end

FERLua.isSemester = function(self, sem) 
  if FERLua:isInteger(sem) == false then
 	return false
  end
  for _, v in pairs(FERLua.semesters) do
    if v == tonumber(sem) then
  	  return true
  	end
  end
  return false
end

FERLua.isEngLevel = function(self, level)
  if FERLua:isInteger(level) == false then
    return false
  end
  for _, v in pairs(FERLua.engLevel) do
    if v == tonumber(level) then
      return true
    end
  end
  return false
end 

FERLua.isLanguage = function (self, lan) 
  for _, v in pairs (FERLua.languages) do
    if v == lan then
      return true
    end
  end
  return false 
end 

FERLua.isStudyLevel = function(self, lev)
  if lev == self.user_undergrad or lev == self.user_graduate then
  	return true
  end
  return false
end

-- sifpred INTEGER
-- ectsbod  "[ >  <  =] INTEGER"
-- nemaocjenu FERLua.user_true/FERLua.user_false
-- engleski 0,1,2,3
-- satipred "[ >  <  =] INTEGER"
-- satilab "[ >  <  =] INTEGER"
-- nazivpred (LIKE) string (jezik dependent)
-- opispred (LIKE) string (jezik dependent)
-- jezik [hr en] -> @param string can depend on jezik if table has `jezik`
-- ime (LIKE) string
-- prezime (LIKE) string
-- semestar 1,2,3,4,5,6
-- nazivsmjer (=) string
-- razina [FERLua.undergrad FERLua.graduate]
-- nazivvrsta (=) string
-- sveuciliste (=) string
FERLua.createSearchQuery = function(self, sifpred, ectsbod, nemaocjenu, engleski, satipred, satilab, nazivpred, opispred, jezik, ime, prezime, semestar, nazivsmjer, razina, nazivvrsta, sveuciliste)
  local join = ""
  local where = ""
  local first_where = false
  
  if jezik ~= nil then -- jezik is conected to more tables, if wrong return nil
    if FERLua:isLanguage(jezik) == false then
      return nil
    end 
    if first_where == false then
  	  where = where .. "predmet_opis.jezik = \'" .. jezik .. "\'"
  	  first_where = true
  	else
  	  where = where .. " AND predmet_opis.jezik = \'" .. jezik .. "\'"
  	end 
  end 
  
  if sifpred ~= nil then
    if self:isInteger(sifpred) == false then
      return nil
    end
    if first_where == false then
      where = where .. "predmet.sifpred = " .. sifpred
      first_where = true
    else
      where = where .. " AND predmet.sifpred = " .. sifpred
    end 
  end
   
  if ectsbod ~= nil then
  	if self:isOperator(string.sub(ectsbod, 1, 1)) == false then -- operator
  	  return nil
  	end	  
  	if self:isInteger(string.sub(ectsbod, 2)) == false then -- number
  	  return nil
  	end
  	if first_where == false then
  	  where = where .. "predmet.ectsbod " .. ectsbod
  	  first_where = true
  	else
  	  where = where .. " AND predmet.ectsbod " .. ectsbod
  	end  
  end
  
  if nemaocjenu ~= nil then
    if self:isBool(nemaocjenu) == false then
      return nil
    end
    if nemaocjenu == self.user_true then
      nemaocjenu = self.sql_true
    end
    if nemaocjenu == self.user_false then
      nemaocjenu = self.sql_false
    end
    if first_where == false then
      where = where .. "predmet.nemaocjenu = " .. nemaocjenu
  	  first_where = true
    else
  	  where = where .. " AND predmet.nemaocjenu = " .. nemaocjenu
  	end 
  end
  
  if engleski ~= nil then
    if FERLua:isEngLevel(engleski) == false then
      return nil
    end
    if first_where == false then
  	  where = where .. "predmet.engleski = " .. engleski
  	  first_where = true
    else
  	  where = where .. " AND predmet.engleski = " .. engleski
    end 
  end
  
  if satipred ~= nil then
  	if self:isOperator(string.sub(satipred, 1, 1)) == false then
  	  return nil
  	end
  	if self:isInteger(string.sub(satipred, 2)) == false then
  	  return nil
  	end
    if first_where == false then
  	  where = where .. "predmet.satipred " .. satipred
  	  first_where = true
  	else
     where = where .. " AND predmet.satipred " .. satipred
    end 
  end
  
  if satilab ~= nil then
  	if self:isOperator(string.sub(satilab, 1, 1)) == false then
  	  return nil
  	end
  	if self:isInteger(string.sub(satilab, 2)) == false then
  	  return nil
  	end
    if first_where == false then
      where = where .. "predmet.satilab " .. satilab
  	  first_where = true
  	else
      where = where .. " AND predmet.satilab " .. satilab
    end 
  end
  
  if nazivpred ~= nil then
    if first_where == false then
     where = where .. "predmet_opis.nazivpred LIKE \'%" .. nazivpred .. "%\'"
     first_where = true
    else
      where = where .. " AND predmet_opis.nazivpred LIKE \'%" .. nazivpred .. "%\'"
  	end
  end
  
  if opispred ~= nil then
    if first_where == false then
  	  where = where .. "predmet_opis.opispred LIKE \'%" .. opispred .. "%\'"
  	  first_where = true
  	else
  	  where = where .. " AND predmet_opis.opispred LIKE \'%" .. opispred .. "%\'"
  	end
  end
  -- untill now included everything that was interesting from predmet and predmet_opis
  -- now we include other tables
  local predmet_nastavnik = false
  local nastavnik = false
  local predmet_vrsta = false
  local smjer_naziv = false
  local predmet_slicni = false
  
  if ime ~= nil then
    if predmet_nastavnik == false then
      join = join .. " JOIN predmet_nastavnik ON predmet_nastavnik.sifpred = predmet.sifpred" 
      predmet_nastavnik = true
    end 
    if nastavnik == false then
      join = join .. " JOIN nastavnik ON nastavnik.sifdjel = predmet_nastavnik.sifdjel" 
      nastavnik = true
    end   
    if first_where == false then
  	  where = where .. "nastavnik.ime LIKE \'%" .. ime .. "%\'"
  	  first_where = true
  	else
  	  where = where .. " AND nastavnik.ime LIKE \'%" .. ime .. "%\'"
  	end 
  end 
  
  if prezime ~= nil then
    if predmet_nastavnik == false then
      join = join .. " JOIN predmet_nastavnik ON predmet_nastavnik.sifpred = predmet.sifpred" 
      predmet_nastavnik = true
    end 
    if nastavnik == false then
      join = join .. " JOIN nastavnik ON nastavnik.sifdjel = predmet_nastavnik.sifdjel"
      nastavnik = true 
    end 
    if first_where == false then
  	  where = where .. "nastavnik.prezime LIKE \'%" .. prezime .. "%\'"
  	  first_where = true
  	else
  	  where = where .. " AND nastavnik.prezime LIKE \'%" .. prezime .. "%\'"
  	end  
  end 
  
  if semestar ~= nil then
    if FERLua:isSemester(semestar) == false then
      return nil
    end 
    if predmet_vrsta == false then
      join = join .. " JOIN predmet_vrsta ON predmet_vrsta.sifpred = predmet.sifpred"
      predmet_vrsta = true
    end
    if first_where == false then
      where = where .. "predmet_vrsta.semestar = " .. semestar
      first_where = true
    else
  	  where = where .. " AND predmet_vrsta.semestar = " .. semestar
  	end 
  end 
  
  if nazivsmjer ~= nil then
    if predmet_vrsta == false then
      join = join .. " JOIN predmet_vrsta ON predmet_vrsta.sifpred = predmet.sifpred"
      predmet_vrsta = true
    end
    if smjer_naziv == false then 
      join = join .. " JOIN smjer_naziv ON smjer_naziv.sifsmjer = predmet_vrsta.sifsmjer AND smjer_naziv.jezik = predmet_vrsta.jezik"
      smjer_naziv = true
    end 
    if first_where == false then
      where = where .. "smjer_naziv.nazivsmjer = \'" .. nazivsmjer .. "\'"
  	  first_where = true
  	else
  	  where = where .. " AND smjer_naziv.nazivsmjer = \'" .. nazivsmjer .. "\'"
  	end
  end
  
  if razina ~= nil then
    if self:isStudyLevel(razina) == false then
      return nil
    end
    if razina == self.user_undergrad then
      razina = self.sql_undergrad
    end
    if razina == self.user_graduate then
      razina = self.sql_graduate
    end
    if predmet_vrsta == false then
      join = join .. " JOIN predmet_vrsta ON predmet_vrsta.sifpred = predmet.sifpred"
      predmet_vrsta = true
    end
    if first_where == false then
  	  where = where .. "predmet_vrsta.razina = " .. razina
      first_where = true
    else
  	  where = where .. " AND predmet_vrsta.razina = " .. razina
  	end 
  end
  
  if nazivvrsta ~= nil then
    if predmet_vrsta == false then
      join = join .. " JOIN predmet_vrsta ON predmet_vrsta.sifpred = predmet.sifpred"
      predmet_vrsta = true
    end
    if first_where == false then
  	  where = where .. "predmet_vrsta.nazivvrsta = \'" .. nazivvrsta .. "\'"
  	  first_where = true
  	else
  	  where = where .. " AND predmet_vrsta.nazivvrsta = \'" .. nazivvrsta .. "\'"
  	end 
  end
  
  if sveuciliste ~= nil then
    if predmet_slicni == false then
      join = join .. " JOIN predmet_slicni ON predmet_slicni.sifpred = predmet.sifpred"
      predmet_slicni = true
    end
    if first_where == false then
  	  where = where .. "predmet_slicni.sveuciliste = \'" .. sveuciliste .. "\'"
  	  first_where = true
  	else
  	  where = where .. " AND predmet_slicni.sveuciliste = \'" .. sveuciliste .. "\'"
  	end 
  end
  
  if where == "" then -- return all
    return "SELECT DISTINCT predmet_opis.nazivpred, predmet_opis.jezik, predmet_opis.sifpred FROM predmet JOIN predmet_opis ON predmet.sifpred = predmet_opis.sifpred ORDER BY predmet_opis.nazivpred ASC"
  else
  	return "SELECT DISTINCT predmet_opis.nazivpred, predmet_opis.jezik, predmet_opis.sifpred FROM predmet JOIN predmet_opis ON predmet.sifpred = predmet_opis.sifpred" .. join .. " WHERE " .. where .. " ORDER BY predmet_opis.nazivpred ASC"
  end
end

FERLua.resultsCompute = function(self, sifpred, ectsbod, nemaocjenu, engleski, satipred, satilab, nazivpred, opispred, jezik, ime, prezime, semestar, nazivsmjer, razina, nazivvrsta, sveuciliste)
  local cursor = mosync.maDBExecSQL(mosync.maDBOpen(mosync.FileSys:GetLocalPath() .. "infopackage.sqlite"), self:createSearchQuery(sifpred, ectsbod, nemaocjenu, engleski, satipred, satilab, nazivpred, opispred, jezik, ime, prezime, semestar, nazivsmjer, razina, nazivvrsta, sveuciliste))
  if cursor == 0 then
    self.WebView:EvalJS('drawResultsHTML("")')
  else
    local data = ""
    while mosync.MA_DB_OK == mosync.maDBCursorNext(cursor) do
      data = data .. '$' .. DBCursorGetColumnText(cursor, 0) .. '#'  .. DBCursorGetColumnText(cursor, 1) .. '#' .. DBCursorGetColumnText(cursor, 2) 
    end  
    mosync.maDBCursorDestroy(cursor)
    self.WebView:EvalJS("drawResultsHTML(" .. quotestring(string.sub(data,2)) .. ")" )
  end
end

-- collects data that includes only one attribute
FERLua.getCollectedData = function (self, member, db, query)
  local cursor = mosync.maDBExecSQL(db, query)
  if cursor == 0 then
    self.WebView:EvalJS("createData('" .. member .. "', '')")
  else 
    local data = ""
    while mosync.MA_DB_OK == mosync.maDBCursorNext(cursor) do
      data = data .. '$' .. DBCursorGetColumnText(cursor, 0)
    end
    mosync.maDBCursorDestroy(cursor)
    self.WebView:EvalJS("createData('" .. member .. "', " .. quotestring(string.sub(data,2)) .. ")")
  end
end

FERLua.initializeMainHtml = function(self)
  local db = mosync.maDBOpen(mosync.FileSys:GetLocalPath() .. "infopackage.sqlite")
  self:getCollectedData('smjer_hr_p', db, "SELECT DISTINCT sn.nazivsmjer FROM smjer s JOIN smjer_naziv sn ON s.sifsmjer = sn.sifsmjer  WHERE s.razina = 3 AND sn.jezik='hr' ORDER BY 1")
  self:getCollectedData('smjer_hr_d', db, "SELECT DISTINCT sn.nazivsmjer FROM smjer s JOIN smjer_naziv sn ON s.sifsmjer = sn.sifsmjer  WHERE s.razina = 4 AND sn.jezik='hr' ORDER BY 1")
  self:getCollectedData('smjer_en_p', db, "SELECT DISTINCT sn.nazivsmjer FROM smjer s JOIN smjer_naziv sn ON s.sifsmjer = sn.sifsmjer  WHERE s.razina = 3 AND sn.jezik='en' ORDER BY 1")
  self:getCollectedData('smjer_en_d', db, "SELECT DISTINCT sn.nazivsmjer FROM smjer s JOIN smjer_naziv sn ON s.sifsmjer = sn.sifsmjer  WHERE s.razina = 4 AND sn.jezik='en' ORDER BY 1")
  self:getCollectedData('tip_hr_p', db, "SELECT DISTINCT nazivvrsta FROM predmet_vrsta WHERE razina = 'P' AND jezik='hr' ORDER BY 1")
  self:getCollectedData('tip_hr_d', db, "SELECT DISTINCT nazivvrsta FROM predmet_vrsta WHERE razina = 'D' AND jezik='hr' ORDER BY 1")
  self:getCollectedData('tip_en_p', db, "SELECT DISTINCT nazivvrsta FROM predmet_vrsta WHERE razina = 'P' AND jezik='en' ORDER BY 1")
  self:getCollectedData('tip_en_d', db, "SELECT DISTINCT nazivvrsta FROM predmet_vrsta WHERE razina = 'D' AND jezik='en' ORDER BY 1")
  self:getCollectedData('sveucilista', db, "SELECT DISTINCT sveuciliste FROM predmet_slicni ORDER BY 1")
  self.WebView:EvalJS("initialize()")
end

FERLua.checkExistSubject = function(self, sifpred, nazivpred, jezik)
  local db = mosync.maDBOpen(mosync.FileSys:GetLocalPath() .. "infopackage.sqlite")
  local cursor = mosync.maDBExecSQL(db, "SELECT DISTINCT sifpred FROM predmet_opis WHERE sifpred = " .. sifpred .. " AND nazivpred = '" .. nazivpred .. "' AND jezik = '" .. jezik .. "'")
  if cursor == 0 then
    self.WebView:EvalJS("doesNotExist()")
  else
    mosync.maDBCursorDestroy(cursor)
    self:showSubject(db, sifpred, nazivpred, jezik)
  end
end

-- takes one row and assigns the values to JavaScript layer
FERLua.loadSubjectData = function(self, db, query, ...)
  local cursor = mosync.maDBExecSQL(db, query)
  if cursor ~= 0 then 
    mosync.maDBCursorNext(cursor)
    for i,v in ipairs(arg) do
      local data = DBCursorGetColumnText(cursor, i-1)
      if data ~= "" then
        self.WebView:EvalJS("createData('" .. v .. "', " .. quotestring(data) .. ")")
      end
    end
    mosync.maDBCursorDestroy(cursor)
  end
end

FERLua.getCollectedDataAsRows = function(self, ordering, member, db, query)
  local cursor = mosync.maDBExecSQL(db, query)
  if cursor ~= 0 then
    local data = ""
    local counter = 0
    while mosync.MA_DB_OK == mosync.maDBCursorNext(cursor) do
      counter = counter + 1
      if ordering == true then
        data = data .. '<tr><td>' .. counter .. '. </td><td>' .. DBCursorGetColumnText(cursor, 0) .. '</td></tr>'
      else
        data = data .. '<tr><td>' .. DBCursorGetColumnText(cursor, 0) .. '</td></tr>'
      end
    end
    mosync.maDBCursorDestroy(cursor)
    self.WebView:EvalJS("createData('" .. member .. "', " .. quotestring(data) .. ")")
  end
end

FERLua.showSubject = function(self, db, sifpred, nazivpred, jezik)
  --table predmet
  self:loadSubjectData(db, "SELECT ectsbod, url, polazese, predajese, engleski, ocjena2, ocjena3, ocjena4, ocjena5, satipred, satiaud, satilab, nemaocjenu, nemaokont, nemaizvod, nemaispit, nemaoblik, nemaliter, nemakompet FROM predmet WHERE sifpred = " .. sifpred, 'ectsbod', 'url', 'polazese', 'predajese', 'engleski', 'ocjena2', 'ocjena3', 'ocjena4', 'ocjena5', 'satipred', 'satiaud', 'satilab', 'nemaocjenu', 'nemaokont', 'nemaizvod', 'nemaispit', 'nemaoblik', 'nemaliter', 'nemakompet')
  -- table nastavnik, predmet_nastavnik
  self:getCollectedDataAsRows(false, 'nastavnik_N', db, "SELECT (CASE WHEN titulanakon = '' THEN '' ELSE titulanakon || ' ' END) || ime || ' ' || prezime FROM nastavnik n JOIN predmet_nastavnik pn ON n.sifdjel = pn.sifdjel WHERE sifpred = " .. sifpred .. " AND uloga = 'N'")
  self:getCollectedDataAsRows(false, 'nastavnik_P', db, "SELECT (CASE WHEN titulanakon = '' THEN '' ELSE titulanakon || ' ' END) || ime || ' ' || prezime FROM nastavnik n JOIN predmet_nastavnik pn ON n.sifdjel = pn.sifdjel WHERE sifpred = " .. sifpred .. " AND uloga = 'P'")
  self:getCollectedDataAsRows(false, 'nastavnik_L', db, "SELECT (CASE WHEN titulanakon = '' THEN '' ELSE titulanakon || ' ' END) || ime || ' ' || prezime FROM nastavnik n JOIN predmet_nastavnik pn ON n.sifdjel = pn.sifdjel WHERE sifpred = " .. sifpred .. " AND uloga = 'L'")
  self:getCollectedDataAsRows(false, 'nastavnik_A', db, "SELECT (CASE WHEN titulanakon = '' THEN '' ELSE titulanakon || ' ' END) || ime || ' ' || prezime FROM nastavnik n JOIN predmet_nastavnik pn ON n.sifdjel = pn.sifdjel WHERE sifpred = " .. sifpred .. " AND uloga = 'A'")
  -- table predmet_ishodi
  self:getCollectedDataAsRows(true, 'ishodi', db, "SELECT nazivishod FROM predmet_ishodi WHERE sifpred = " .. sifpred .. " AND jezik = '" .. jezik .. "' ORDER BY ordishod")
  -- table predmet_literatura
  self:getCollectedDataAsRows(true, 'literatura', db, "SELECT (CASE WHEN autori = '' THEN '' ELSE autori || ' ' END) || (CASE WHEN godina = '' THEN  '' ELSE '(' || godina || ') ' END) || (CASE WHEN naziv = '' THEN '' ELSE naziv || ' ' END) || izdavac FROM predmet_literatura WHERE sifpred = 34539 ORDER BY ordliteratura")
  -- table predmet_tjedniplan
  self:getCollectedDataAsRows(true, 'tjedniplan', db, "SELECT opisrada FROM predmet_tjedniplan WHERE sifpred = " .. sifpred .. " AND jezik = '" .. jezik .. "' ORDER BY tjedan")
  -- predmet_slicni
  self:getCollectedDataAsRows(false, 'slicni', db, "SELECT sveuciliste || ', <a href=\"' || url || '\">' || naziv || '</a>'  FROM predmet_slicni WHERE sifpred = " .. sifpred .." ORDER BY ordslicni")
  -- table predmet_preduvjet
  self:getCollectedDataAsRows(false, 'preduvjet', db, "SELECT nazivpred || '(" .. sifpred .. ")' FROM predmet_opis po JOIN predmet_preduvjet pp ON po.sifpred = pp.sifpreduvjet WHERE pp.sifpred = " .. sifpred .. " AND jezik = '" .. jezik .. "'")
  -- table predemt_opis
  self:loadSubjectData(db, "SELECT opispred, kompetencije, ocjenanapomena, bodovinapomena FROM predmet_opis WHERE sifpred = " .. sifpred .. " AND jezik = '" .. jezik .. "'",'opispred', 'kompetencije', 'ocjenanapomena', 'bodovinapomena')
  -- table predmet_vrsta smjer_naziv
  self:getCollectedDataAsRows(false, 'dostupan', db, "SELECT (CASE WHEN razina = 'P' THEN  (CASE WHEN '" .. jezik .. "' = 'hr' THEN 'Preddiplomski' WHEN '" .. jezik .. "' = 'en' THEN 'Undergraduate' END) WHEN razina = 'D' THEN  (CASE WHEN '" .. jezik .. "' = 'hr' THEN 'Diplomski' WHEN '" .. jezik .. "' = 'en' THEN 'Graduate' END)  END) || (CASE WHEN '" .. jezik .. "' = 'hr' THEN ' studij, ' WHEN '" .. jezik .. "' = 'en' THEN ' study, ' END) || nazivsmjer || ', ' || nazivvrsta || ', ' || semestar || '. semestar' FROM predmet_vrsta pv JOIN smjer_naziv sn ON pv.sifsmjer = sn.sifsmjer AND pv.jezik = sn.jezik WHERE pv.sifpred = " .. sifpred .. " AND pv.jezik = '" .. jezik .. "' ORDER BY nazivsmjer")
  -- table predmet_oblicinastave, obliknastave_naziv
  self:getCollectedDataAsRows(false, 'oblicinastave', db, "SELECT CASE WHEN opisoblik = '' THEN nazivoblik ELSE nazivoblik || ' - ' || opisoblik END FROM predmet_oblicinastave po JOIN obliknastave_naziv obn ON obn.sifoblik = po.sifoblik AND obn.jezik = po.jezik WHERE sifpred = " .. sifpred .. " AND po.jezik = '" .. jezik .. "' ORDER BY po.ordoblik")
  -- table predmet_vrsta, predmet_provjera
  self:getCollectedDataAsRows(false, 'ocjenjivanje', db, "SELECT naziv_provjera || '</td><td>' || pragk || '</td><td>' || udiok  || '%</td><td>' || pragi  || '</td><td>' || udioi || '%' FROM predmet_provjera pp JOIN provjera_vrsta pv ON pp.sifoblik = pv.sifoblik  WHERE (udioi != 0 OR udiok !=0) AND sifpred = " .. sifpred .. " AND jezik = '" .. jezik .. "' ORDER BY ord")
  
  self.WebView:EvalJS("initialize()")
end

FERLua.Main = function(self)
  -- We want to app to exit on devices that have a back button.
  mosync.EventMonitor:OnKeyDown(function(key)
    if mosync.MAK_BACK == key then
	  mosync.maExit(0)
    end
  end)
  self.Screen = mosync.NativeUI:CreateScreen{}
  self.WebView = mosync.NativeUI:CreateWebView{
    parent = self.Screen,
    enableZoom = "false",
    bounces = "false"
  }	  
  self.WebView:SetProp(mosync.MAW_WEB_VIEW_URL, "index.html")
  mosync.NativeUI:ShowScreen(self.Screen)
  mosync.EventMonitor:RunEventLoop()
end

-- Start the program
FERLua:Main()