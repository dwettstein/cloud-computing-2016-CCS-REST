# Ruby dependencies
require 'sinatra'
require 'sinatra/reloader' if development?
require 'json'
require 'net/http'

# sinatra configuration
set :show_exceptions, :after_handler

before do
  # allow CORS
  content_type :json
  status 200
  headers \
    'Allow'                         => 'OPTIONS, GET',
    'Access-Control-Allow-Origin'   => '*',
    'Access-Control-Allow-Methods'  => ['OPTIONS', 'GET']
end

not_found do
  body ({ error: 'Ooops, this route does not seem exist'}.to_json)
end

error do
  body ({ error: 'Sorry there was a nasty error - ' + env['sinatra.error'].message }.to_json)
end


# API endpoints
IP_EP = 'http://ip-api.com/json'
TRANSPORT_EP = 'http://transport.opendata.ch/v1'
WEATHER_EP = 'http://api.openweathermap.org/data/2.5'
WEATHER_APPID = 'appid=87ccf52f80bef59fef990beacbd2a5fb'

# start coding below

## 
# Makes a HTTP GET request to the given URI.
# The response body is returned as JSON.
def forwardRequest(_url)
  uri = URI(_url)
  response = Net::HTTP.get_response(uri)
  result = JSON.parse(response.body)
  return result.to_json
end

##
# Checks if all needed parameters are given.
def hasAllParams(_currParm, _definedParams)
  return (_currParm.keys.map(&:upcase) & _definedParams.map(&:upcase)).length == _definedParams.length
end

##
# Checks if any needed parameter is given.
def hasOneParam(_currParm, _definedParams)
  return (_currParm.keys.map(&:upcase) & _definedParams.map(&:upcase)).any?
end

##
# Creates a response JSON when an error occurred.
def doError(_msg)
  return ({ errors: [{ message: _msg}]}.to_json)
end

##
# Makes a GET request to the IP-API.
def doIPRequest(_params)
  parm = _params['ip'] || "130.125.1.11"
  url = IP_EP + "/" + parm
  return forwardRequest(url)
end

##
# Makes a /locations GET request to the Transport Opendata API.
# Either (query) or (x, y) are mandatory.
def doLocationRequest(_params)
  definedParams = ["query","x","y"]
  parm = _params.length > 0 ? _params : {"query" => "Neuchatel"}
  if hasOneParam(parm, definedParams) 
    url = TRANSPORT_EP + "/locations?" + URI.encode_www_form(parm)
    return forwardRequest(url)
  else
    return doError('Request does not contain one of the correct parameters ('+definedParams.join(",")+')')
  end
end

##
# Makes a /connections GET request to the Transport Opendata API.
# All parameters are mandatory.
def doConnectionsRequest(_params)
  definedParams = ["from","to"]
  parm = _params.length > 0 ? _params : {"from" => "Neuchatel","to" => "Bern"}
  if hasAllParams(parm, definedParams)
    url = TRANSPORT_EP + "/connections?" + URI.encode_www_form(parm)
    return forwardRequest(url)
  else
    return doError('Request does not contain the correct parameters ('+definedParams.join(",")+')')
  end
end

##
# Makes a /stationboard GET request to the Transport Opendata API.
# Either (station) or (id) is mandatory.
def doStationboardRequest(_params)
  definedParams = ["station","id"]
  parm = _params.length > 0 ? _params : {"station" => "Neuchatel"}
  if hasOneParam(parm, definedParams) 
    url = TRANSPORT_EP + "/stationboard?" + URI.encode_www_form(parm)
    return forwardRequest(url)
  else
    return doError('Request does not contain one of the correct parameters ('+definedParams.join(",")+')')
  end
end

##
# Makes a /weather or a /forecast GET request to the OpenWeatherMap API.
# Either (q) or (lat, lon) are mandatory.
# By giving the parameter _future a /forecast request is executed.
def doWeatherRequest(_params, _future)
  cityParam = ["q"]
  coordParam = ["lat","lon"]
  definedParams = (cityParam + coordParam)
  parm = _params.length > 0 ? _params : {"q" => "Neuchatel"}
  if hasAllParams(parm, cityParam) and hasOneParam(parm, coordParam)
    return doError('Request contains too many parameters ('+definedParams.join(",")+')')
  elsif hasAllParams(parm, cityParam) or hasAllParams(parm, coordParam)
    url = WEATHER_EP + "/" + (_future ? "forecast" : "weather") + "?" + WEATHER_APPID + "&" + URI.encode_www_form(parm)
    return forwardRequest(url)
  else
    return doError('Request does not contain one of the correct parameters ('+definedParams.join(",")+')')
  end
end

##
# Combines /ip, /locations and /stationboard GET requests to the Transport Opendata API.
#
# Takes an IP address as parameter and returns the next 5 (train) connections running from 
# the nearest train station to this IP location.
#
# Parameter IP is mandatory.
def doStationsRequest(_params)
  res = doIPRequest(params)
  ip = JSON.parse(res)
  res = doLocationRequest({"type"=>"station","transportations[]"=>"ec_ic","transportations[]"=>"ice_tgv_rj","transportations[]"=>"ir","transportations[]"=>"re_d", "x" => ip["lat"].to_s, "y" => ip["lon"].to_s})
  location = JSON.parse(res)
  station = (location["stations"].sort_by { |hash| hash['distance'].to_i }).first
  if station.nil?
    return doError('No station was found!')
  else
    res = doStationboardRequest({"id"=>station["id"].to_s, "limit"=>"5"})
    stationboard = JSON.parse(res)
    # StationsRequest param limit=5 can respond more than 5 elements (if on same time)
    # therefore the filter first(5) must be applied
    return ({ stationboard: stationboard["stationboard"].first(5) }.to_json)
  end
end

##
# Combines /stations and /weather GET requests.
#
# Takes an IP address as parameter and returns a list of pairs <destination, weather> 
# for the next 5 connections returned by the /stations route.
#
# Parameter IP is mandatory.
def doWeathersRequest(_params, _future)
  res = doStationsRequest(_params)
  station = JSON.parse(res)
  # check for error
  if station.key?("errors")
    return res
  else
    stationboard = station["stationboard"]
    destination = Array.new
    stationboard.each do |board|
      dest = (board["passList"].last)["station"]
      coord = dest["coordinate"]
      res = doWeatherRequest({"lat" => coord["x"].to_s, "lon" => coord["y"].to_s}, _future)
      weather = JSON.parse(res)
      destination.push({"destination" => dest, "weather" => weather})
    end
    
    return destination
  end
end

##
# Defines GET route for /ip.
get "/ip" do
  body doIPRequest(params)
end

##
# Defines GET route for /locations.
get '/locations' do
  body doLocationRequest(params)
end

##
# Defines GET route for /connections.
get '/connections' do
  body doConnectionsRequest(params)
end

##
# Defines GET route for /stationboard.
get '/stationboard' do
  body doStationboardRequest(params)
end

##
# Defines GET route for /weather.
get '/weather' do
  body doWeatherRequest(params, false)
end

##
# Defines GET route for /stations.
get '/stations' do
  body doStationsRequest(params)
end

##
# Defines GET route for /weathers.
# If the (sort) parameter is given, sorts the results either by 
# temperature, humidity, pressure, cloud or wind (default temperature).
get '/weathers' do
  destination = doWeathersRequest(params, false)
  # check for error
  if not destination.kind_of?(Array)
    body destination
  else
    sortby = "weather.main.temp"
    sort = params.has_key?("sort") ? params["sort"].upcase : ""
    if sort == "TEMPERATURE"
      sortby = "weather.main.temp"
    elsif sort == "HUMIDITY"
      sortby = "weather.main.humidity"
    elsif sort == "PRESSURE"
      sortby = "weather.main.pressure"
    elsif sort == "WIND"
      sortby = "weather.wind.speed"
    elsif sort == "CLOUD"
      sortby = "weather.clouds.all"
    end
    
    destination = (destination.sort_by! { |hash| getValue(hash, sortby).to_f }).reverse
    body ({ weathers: destination }.to_json)
  end
end

##
# Defines GET route for /future_weathers.
# If the (sort) parameter is given, sorts the results either by 
# temperature, humidity, pressure, cloud or wind (default temperature).
get '/future_weathers' do
  definedParams = ["x"]
  # check if parameter x exists and if it is a whole number between 1 and 5
  if hasOneParam(params, definedParams) and params["x"].to_f % 1 == 0 and params["x"].to_i.between?(1,5)
    x = params["x"].to_i
    destination = doWeathersRequest(params, true)
    # check for error
    if not destination.kind_of?(Array)
      body destination
    else
      # filter forecast data up to x days
      destination.each do |dest|
        dest["weather"]["list"].delete_if {|hash| !(DateTime.now-1..DateTime.now + x).cover?(DateTime.parse(hash["dt_txt"]).to_date)}
      end
      
      #sorts the destination based on the weather on day x
      sortby = "main.temp"
      sort = params.has_key?("sort") ? params["sort"].upcase : ""
      if sort == "TEMPERATURE"
        sortby = "main.temp"
      elsif sort == "HUMIDITY"
        sortby = "main.humidity"
      elsif sort == "PRESSURE"
        sortby = "main.pressure"
      elsif sort == "WIND"
        sortby = "wind.speed"
      elsif sort == "CLOUD"
        sortby = "clouds.all"
      end
      
      destination = (destination.sort_by! { |hash| getValue(hash["weather"]["list"].last, sortby).to_f }).reverse
      body ({ future_weathers: destination }.to_json)
    end
  else
    body doError('Parameter x must be a number from 1 to 5.')
  end
end

def getValue(_hash, _path)
  _path.to_s.split('.').map(&:to_s).inject(_hash, :[])
end
