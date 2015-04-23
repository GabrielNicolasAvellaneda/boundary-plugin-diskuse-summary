---------------
---- ## A Boundary Plugin Framework for Luvit.
----
---- For easy development of custom Boundary.com plugins.
----
---- [Github Page](https://github.com/GabrielNicolasAvellaneda/boundary-plugin-framework-lua)
----
---- @author Gabriel Nicolas Avellaneda <avellaneda.gabriel@gmail.com>
---- @copyright Boundary.com 2015
---- @license MIT
---------------
local fs = require('fs')
local json = require('json')
local Emitter = require('core').Emitter
local Error = require('core').Error
local Object = require('core').Object
local Process = require('uv').Process
local timer = require('timer')
local math = require('math')
local string = require('string')
local os = require('os')
local io = require('io')
local http = require('http')
local https = require('https')
local net = require('net')
local bit = require('bit')
local table = require('table')
local boundary = require('boundary')

local __pkg = "Boundary Plugin Frtamework"
local __ver = "Version 1.0"
local __tags = "lua,plugin,framework"

local framework = {}
local params = boundary.param

framework.boundary = boundary

framework.params = params


framework.string = {}
framework.functional = {}
framework.table = {}
framework.util = {}
framework.http = {}


--local ffi = require('ffi')

-- Added some missing function in the luvit > 2.0 release

--ffi.cdef [[
  --int gethostname(char *name, unsigned int namelen);
  --]]

--[[
  Return the hostname
  @param maxlen{integer,optional} defaults to 255
--]]
--function os.hostname (maxlen)
  --maxlen = maxlen or 255
  --local buf = ffi.new("uint8_t[?]", maxlen)
  --local res = ffi.C.gethostname(buf, maxlen)
  --assert(res == 0)
  --return ffi.string(buf)
--end

local encode_alphabet = {
	'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z',
	'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z',
	'0', '1', '2', '3', '4', '5', '6', '7', '8', '9', '+', '/'
}

local decode_alphabet = {}
for i, v in ipairs(encode_alphabet) do
  decode_alphabet[v] = i-1
end

local function translate(sixbit)
  return encode_alphabet[sixbit + 1] 
end

local function unTranslate(char)
  return decode_alphabet[char]
end

local function toBytes(str)
  return { str:byte(1, #str) }
end

local function mask6bits(byte)
  return bit.band(0x3f, byte)
end

local function pad(bytes)
  local to_pad = 3 - #bytes % 3 
  while to_pad > 0 and to_pad ~= 3 do
    table.insert(bytes, 0x0)
    to_pad = to_pad - 1
  end

  return bytes
end

local function encode(str, no_padding)
  local bytes = toBytes(str)
  local bytesTotal = #bytes
  if bytesTotal == 0 then
  	  return ''
  end
  bytes = pad(bytes)
  local output = {}
 
  local i = 1
  while i < #bytes do
    -- read three bytes into a 24 bit buffer to produce 4 coded bytes.
    local buffer = bit.rol(bytes[i], 16)	
    buffer = bit.bor(buffer, bit.rol(bytes[i+1], 8))
    buffer = bit.bor(buffer, bytes[i+2])

    -- get six bits at a time and translate to base64
    for j = 18, 0, -6 do
		table.insert(output, translate(mask6bits(bit.ror(buffer, j))))
	end
	i = i + 3
  end
	-- If was padded then replace with = characters 
  local padding_char = no_padding and '' or '='

   if bytesTotal % 3 == 1  then
   	   output[#output-1] = padding_char 
   	   output[#output] = padding_char 
  elseif bytesTotal % 3 == 2 then
	output[#output] = padding_char 
   end
  
  return table.concat(output)
end

local function decode(str)
  -- take four encoded octets and produce 3 decoded bytes.
  local output = {}
  local i = 1
  while i < #str do
    local buffer = 0
    -- get the octet represented by the coded base64 char
    -- shift left by 6 bits and or 
    -- mask the 3 bytes, and convert to ascii

    for j = 18, 0, -6 do
      local octet = unTranslate(str:sub(i, i))
      buffer = bit.bor(bit.rol(octet, j), buffer)
      i = i + 1
    end

    for j = 16, 0, -8 do
      local byte = bit.band(0xff, bit.ror(buffer, j))
      table.insert(output, byte)
    end
  end

  return string.char(unpack(output))
end

framework.util.base64Encode = encode
framework.util.base64Decode = decode

function framework.util.error(errstring)
  print("_bevent:"..__pkg..":"..__ver..":"..errstring.."|t:error|tags:"..__tags)
end

function framework.util.info(errstring)
  print("_bevent:"..__pkg..":"..__ver..":"..errstring.."|t:error|tags:"..__tags)
end

--- Wraps a function to calculate the time passed between the wrap and the function execution.
function framework.util.timed(func, startTime)
  local startTime = startTime or os.time()

  return function(...) 
    return os.time() - startTime, func(...)
  end
end


function framework.util.currentTimestamp()
  return os.time()
end
local currentTimestamp = framework.util.currentTimestamp

function framework.util.megaBytesToBytes(mb)
  return mb * 1024 * 1024
end

function framework.functional.partial(func, x) 
  return function (...)
    return func(x, ...) 
  end
end

function framework.functional.compose(f, g)
  return function(...) 
    return g(f(...))
  end
end

function framework.table.get(key, map)
  if type(map) ~= 'table' then
    return nil 
  end

  return map[key]
end

function framework.table.keys(t)
  local result = {}
  for k,_ in pairs(t) do
    table.insert(result, k)
  end

  return result
end

function framework.table.clone(t)
  if type(t) ~= 'table' then return t end

  local meta = getmetatable(t)
  local target = {}
  for k,v in pairs(t) do
    if type(v) == 'table' then
      target[k] = clone(v)
    else
      target[k] = v
    end
  end
  setmetatable(target, meta)
  return target
end

function framework.string.contains(pattern, str)
  local s,e = string.find(str, pattern)

  return s ~= nil
end

function framework.string.escape(str)
  local s, c = string.gsub(str, '%.', '%%.')
  s, c = string.gsub(s, '%-', '%%-')
  return s
end

function framework.string.urldecode(str)
  local char, gsub, tonumber = string.char, string.gsub, tonumber
  local function _(hex) return char(tonumber(hex, 16)) end

  str = gsub(str, '%%(%x%x)', _)

  return str
end

function framework.string.urlencode(str)
  if str then
    str = string.gsub(str, '\n', '\r\n')
    str = string.gsub(str, '([^%w])', function(c)
      return string.format('%%%02X', string.byte(c))
    end)
  end

  return str
end

function framework.string.jsonsplit(self)
  local outResults = {}
  local theStart,theSplitEnd = string.find(self, "{")
  local numOpens = theStart and 1 or 0
  theSplitEnd = theSplitEnd and theSplitEnd + 1
  while theSplitEnd < string.len(self) do
    if self[theSplitEnd] == '{' then
      numOpens = numOpens + 1
    elseif self[theSplitEnd] == '}' then
      numOpens = numOpens - 1
    end
    if numOpens == 0 then
      table.insert( outResults, string.sub ( self, theStart, theSplitEnd ) )
      theStart,theSplitEnd = string.find(self, "{", theSplitEnd)
      numOpens = theStart and 0 or 1
      theSplitEnd = theSplitEnd or string.len(self)
    end
    theSplitEnd = theSplitEnd + 1
  end
  return outResults
end

function framework.string.split(self, pattern)
  local outResults = {}
  local theStart = 1
  local theSplitStart, theSplitEnd = string.find(self, pattern, theStart)
  while theSplitStart do
    table.insert( outResults, string.sub( self, theStart, theSplitStart-1 ) )
    theStart = theSplitEnd + 1
    theSplitStart, theSplitEnd = string.find( self, pattern, theStart )
  end
  table.insert( outResults, string.sub( self, theStart ) )
  return outResults
end

--- Trim blanks from the string
function framework.string.trim(self)
   return string.match(self,"^()%s*$") and "" or string.match(self,"^%s*(.*%S)" )
end 

--- Check if the string is empty. Before checking it will be trimmed to remove blank spaces.
function framework.string.isEmpty(str)
  return (str == nil or framework.string.trim(str) == '')
end

function framework.string.notEmpty(str)
  return not framework.string.isEmpty(str)
end

-- You can call framework.string() to export all functions to the string table to the global table for easy access.
function exportable(t)
  setmetatable(t, {
    __call = function (t, warn)
      for k,v in pairs(t) do 
        if (warn) then
          if _G[k] ~= nil then
            process.stderr:write('Warning: Overriding function ' .. k ..' on global space.')
          end
        end
        _G[k] = v
      end
    end
  })
end

-- Allow to export functions to global table
exportable(framework.string)
exportable(framework.util)
exportable(framework.functional)
exportable(framework.table)
exportable(framework.http)

--- DataSource class.
-- @type DataSource
local DataSource = Emitter:extend()
--- DataSource is the base class for any DataSource you want to implement.
framework.DataSource = DataSource
--- DataSource constructor.
-- @name DataSource:new
function DataSource:initialize(params)
  self.params = params
end

--- Fetch data from the datasource. This is an abstract method.
function DataSource:fetch(caller, callback)
  error('fetch: you must implement on class or object instance.')
end

--- NetDataSource class.
-- @type NetDataSource
local NetDataSource = DataSource:extend()
function NetDataSource:initialize(host, port)

  self.host = host
  self.port = port
end

function NetDataSource:onFetch(socket)
  framework.util.info('you must override the NetDataSource:onFetch')
end

--- Fetch data from the configured host and port
-- @param context How calls this functions
-- @func callback A callback that gets called when there is some data on the socket.
function NetDataSource:fetch(context, callback)

  local socket
  socket = net.createConnection(self.port, self.host, function ()

    self:onFetch(socket)

    if callback then
      socket:once('data', function (data)
        callback(data)
        socket:shutdown()
      end)
    else
      socket:shutdown()
    end

  end)
  socket:on('error', function (err) self:emit('error', 'Socket error: ' .. err.message) end)
end

framework.NetDataSource = NetDataSource

--- DataSourcePoller class
-- @type DataSourcePoller
local DataSourcePoller = Emitter:extend() 

--- DataSourcePoller constructor.
-- DataSourcePoller Polls a DataSource at the specified interval and calls a callback when there is some data available. 
-- @int pollInterval number of milliseconds to poll for data 
-- @param dataSource A DataSource to be polled
-- @name DataSourcePoller:new 
function DataSourcePoller:initialize(pollInterval, dataSource)
  self.pollInterval = pollInterval
  self.dataSource = dataSource
  --dataSource:propagate('error', self)
end

function DataSourcePoller:_poll(callback)
  self.dataSource:fetch(self, callback)

  timer.setTimeout(self.pollInterval, function () self:_poll(callback) end)
end

--- Start polling for data.
-- @func callback A callback function to call when the DataSource returns some data. 
function DataSourcePoller:run(callback)
  if self.running then 
    return
  end

  self.running = true
  self:_poll(callback)
end

--- Plugin Class.
-- @type Plugin
local Plugin = Emitter:extend()
framework.Plugin = Plugin

--- Plugin constructor.
-- A base plugin implementation that accept a dataSource and polls periodically for new data and format the output so the boundary meter can collect the metrics.
-- @param params is a table of options that can be:
--  pollInterval (optional) the poll interval between data fetchs. This is required if you pass a plain DataSource and not a DataSourcePoller.
--  source (optional)
--  version (options) the version of the plugin.    
-- @param dataSource A DataSource that will be polled for data. 
-- If is a DataSource a DataSourcePoller will be created internally to pool for data
-- It can also be a DataSourcePoller or PollerCollection.
-- @name Plugin:new
function Plugin:initialize(params, dataSource)

  assert(dataSource, 'Plugin:new dataSource is required.')

  local pollInterval = params.pollInterval or 1000
  if not Plugin:_isPoller(dataSource) then
    self.dataSource = DataSourcePoller:new(pollInterval, dataSource)
  else 
    self.dataSource = dataSource
  end

  self.source = params.source or os.hostname()
  self.version = params.version or __ver
  self.name = params.name or __pkg
  self.tags = params.tags or __tags
  __pkg = self.name
  __ver = self.version
  __tags = self.tags

  --dataSource:propagate('error', self)

  self:on('error', function (err) self:error(err) end)

  framework.util.info("Up")
end

function Plugin:_isPoller(poller)
  return poller.run 
end

--- Called when the Plugin detect and error in one of his components.
-- @param err the error emitted by one of the component that failed.
function Plugin:error(err)
  local msg = ''
  if type(err) == 'table' then
    msg = err.message
  else
    msg = tostring(err)
  end
  print(msg)
end

--- Run the plugin and start polling from the configured DataSource
function Plugin:run()

  self.dataSource:run(function (...) self:parseValues(...) end)
end

function Plugin:parseValues(...)
  local metrics = self:onParseValues(...)

  self:report(metrics)
end

function Plugin:onParseValues(...)
  error('You must implement onParseValues')
end

function Plugin:report(metrics)
  self:emit('report')
  self:onReport(metrics)
end

function Plugin:onReport(metrics)
  table.foreach(metrics, function(_index)
    print(self:format(metrics[_index].metric, metrics[_index].value, metrics[_index].source or self.source, metrics[_index].timestamp or currentTimestamp()))
  end)
end

function Plugin:format(metric, value, source, timestamp)
  self:emit('format')
  return self:onFormat(metric, value, source, timestamp) 
end

--- Called by the framework before formating the metric output. 
-- @string metric the metric name
-- @param value the value to format
-- @string source the source to report for the metric
-- @param timestamp the time the metric was retrieved
-- You can override this on your plugin instance.
function Plugin:onFormat(metric, value, source, timestamp)
  return string.format('%s %f %s %s', metric, value, source, timestamp)
end

local CommandPlugin = Plugin:extend()
framework.CommandPlugin = CommandPlugin

function CommandPlugin:initialize(params)
  Plugin.initialize(self, params)

  if not params.command then
    error('params.command undefined. You need to define the command to excetue.')
  end

  self.command = params.command
end

function CommandPlugin:execCommand(callback)
  local proc = io.popen(self.command, 'r')	
  local output = proc:read("*a")
  proc:close()
  if callback then
    callback(output)
  end
end

function CommandPlugin:onPoll()
  self:execCommand(function (output) self.parseCommandOutput(self, output) end)
end

function CommandPlugin:parseCommandOutput(output)
  local metrics = self:onParseCommandOutput(output)
  self:report(metrics)
end

function CommandPlugin:onParseCommandOutput(output)
  print(output)
  return {}
end

local NetPlugin = Plugin:extend()
framework.NetPlugin = NetPlugin

local HttpPlugin = Plugin:extend()
framework.HttpPlugin = HttpPlugin

function HttpPlugin:initialize(params)
  Plugin.initialize(self, params)
	
  self.reqOptions = {
    host = params.host,
    port = params.port,
    path = params.path
  }
end

local PollingPlugin = Plugin:extend()

framework.PollingPlugin = PollingPlugin

function HttpPlugin:makeRequest(reqOptions, successCallback)
  local req = http.request(reqOptions, function (res)


    local data = ''

    res:on('data', function (chunk)
      data = data .. chunk	
      successCallback(data)
      -- TODO: Verify when data its complete or when we need to use de end
    end)

    res:on('error', function (err)
      local msg = 'Error while receiving a response: ' .. err.message
      self:error(msg)
    end)

  end)
	
  req:on('error', function (err)
    local msg = 'Error while sending a request: ' .. err.message
    self:error(msg)
  end)

  req:done()
end

function HttpPlugin:onPoll()
  self:makeRequest(self.reqOptions, function (data)
    self:parseResponse(data)
  end)
end

function HttpPlugin:parseResponse(data)
  local metrics = self:onParseResponse(data) 
  self:report(metrics)
end

function HttpPlugin:onParseResponse(data)
  -- To be overriden on class instance
  print(data)
  return {}
end

--- Acumulator Class
-- @type Accumulator
local Accumulator = Emitter:extend()

--- Accumulator constructor.
-- Keep track of values so we can return the delta for accumulated metrics.
-- @name Accumulator:new
function Accumulator:initialize()
  self.map = {}
end

--- Accumulates a value an return the delta between the actual an latest value.
-- @string key the key for the item
-- @param value the item value
-- @return diff the delta between the latests and actual value.
function Accumulator:accumulate(key, value)
  local oldValue = self.map[key]
  if oldValue == nil then
    oldValue = value	
  end

  self.map[key] = value
  local diff = value - oldValue

  return diff
end

--- Reset the specified value
-- @string key A key to untrack
function Accumulator:reset(key)
  self.map[key] = nil
end

--- Clean up all the tracked key/values.
function Accumulator:resetAll()
  self.map = {}
end

framework.Accumulator = Accumulator

local PollerCollection = Emitter:extend()
function PollerCollection:initialize(pollers) 
  self.pollers = pollers or {}

end

function PollerCollection:add(poller)
  table.insert(self.pollers, poller)
end

function PollerCollection:run(callback) 
  if self.running then
    return
  end

  self.running = true
  for _,p in pairs(self.pollers) do
    p:run(callback)
  end

end

--- WebRequestDataSource Class
-- @type WebRequestDataSource
local WebRequestDataSource = DataSource:extend()
function WebRequestDataSource:initialize(params)
  local options = params
  if type(params) == 'string' then
    options = url.parse(params)
  end

  self.wait_for_end = options.wait_for_end or false

  self.options = options
  self.info = options.meta
end

local base64Encode = framework.util.base64Encode

function WebRequestDataSource:fetch(context, callback)
  assert(callback, 'WebRequestDataSource:fetch: callback is required')

  local start_time = os.time()
  local options = self.options

  local headers = {} 
  local buffer = ''

  local success = function (res) 

    if self.wait_for_end then
      res:on('end', function ()
        local exec_time = os.time() - start_time  
        callback(buffer, {info = self.info, response_time = exec_time, status_code = res.statusCode})

        res:destroy()
      end)
    else 
      res:once('data', function (data)
        local exec_time = os.time() - start_time
        buffer = buffer .. data
        res:on('data', function (data) 
          buffer = buffer .. data
        end)

        if not self.wait_for_end then
          callback(buffer, {info = self.info, response_time = exec_time, status_code = res.statusCode})
        end
      end)
    end 

    res:propagate('error', self)
  end

  options.headers = {}
  options.headers['User-Agent'] = 'Boundary Meter <support@boundary.com>'

  if options.auth then
    options.headers['Authorization'] = 'Basic ' .. base64Encode(options.auth, true)
  end
  
  local data = options.data
  local body
  if data ~= nil and table.getn(data) > 0 then
    body = table.concat(data, '&') 
    options.headers['Content-Type'] = 'application/x-www-form-urlencoded'
    options.headers['Content-Length'] = #body 
  end

  local req
  if options.protocol == 'https' then
    req = https.request(options, success)
  else
    req = http.request(options, success)
  end

  if body and #body > 0 then
    req:write(body)
  end

  req:propagate('error', self)
  req:done()
end


--- RandomDataSource class
-- @type RandomDataSource
local RandomDataSource = DataSource:extend()

--- RandomDataSource constructor
-- @int minValue the lower bounds for the random number generation.
-- @int maxValue the upper bound for the random number generation.
--@usage local ds = RandomDataSource:new(1, 100)
function RandomDataSource:initialize(minValue, maxValue)
  self.minValue = minValue
  self.maxValue = maxValue
end

--- Returns a random number
-- @param context the object that called the fetch
-- @func callback A callback to call with the random generated number
-- @usage local ds = RandomDataSource:new(1, 100) -- Generate numbers from 1 to 100
--ds.fetch(nil, print)
function RandomDataSource:fetch(context, callback)
  
  local value = math.random(self.minValue, self.maxValue)
  if not callback then error('fetch: you must set a callback when calling fetch') end

  callback(value)
end

framework.RandomDataSource = RandomDataSource
framework.DataSourcePoller = DataSourcePoller
framework.WebRequestDataSource = WebRequestDataSource
framework.PollerCollection = PollerCollection

return framework



