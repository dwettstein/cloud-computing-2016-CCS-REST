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
def forwardRequest(_url)
  uri = URI(_url)
  response = Net::HTTP.get_response(uri)
  result = JSON.parse(response.body)
  return result.to_json
end

def hasAllParams(_currParm, _definedParams)
  return (_currParm.keys.map(&:upcase) & _definedParams.map(&:upcase)).length == _definedParams.length
end

def hasOneParam(_currParm, _definedParams)
  return (_currParm.keys.map(&:upcase) & _definedParams.map(&:upcase)).any?
end

def doError(_msg)
  return ({ errors: [{ message: _msg}]}.to_json)
end

def doIPRequest(_params)
  parm = _params['ip'] || "130.125.1.11"
  url = IP_EP + "/" + parm
  return forwardRequest(url)
end

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

get "/ip" do
  body doIPRequest(params)
end


get '/locations' do
  body doLocationRequest(params)
end


get '/connections' do
  definedParams = ["from","to"]
  parm = params.length > 0 ? params : {"from" => "Neuchatel","to" => "Bern"}
  if hasAllParams(parm, definedParams)
    url = TRANSPORT_EP + "/connections?" + URI.encode_www_form(parm)
    body forwardRequest(url)
  else
    body doError('Request does not contain the correct parameters ('+definedParams.join(",")+')')
  end
end


get '/stationboard' do
  body doStationboardRequest(params)
end


get '/weather' do
  body doWeatherRequest(params, false)
end


get '/stations' do
  body doStationsRequest(params)
end


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


get '/future_weathers' do
  definedParams = ["x"]
  # check if parameter x exists and if it is a whole number between 1 and 5
  if hasOneParam(params, definedParams) and params["x"].to_f % 1 == 0 and params["x"].to_i.between?(1,5)
    destination = doWeathersRequest(params, true)
    # check for error
    if not destination.kind_of?(Array)
      body destination
    else
      # TODO filter forecast data up to x days
      
      
      # TODO sort by some !numbers!
      sortby = "weather.main.temp"
      sort = params.has_key?("sort") ? params["sort"].upcase : ""
      if sort == "TEMPERATURE"
        sortby = "weather.main.temp"
      elsif sort == "HUMIDITY"
        sortby = "weather.main.humidity"
      elsif sort == "PRESSURE"
        sortby = "weather.main.pressure"
      end
      
      #destination = (destination.sort_by! { |hash| getValue(hash, sortby).to_f }).reverse
      body ({ future_weathers: destination }.to_json)
    end
  else
    body doError('Parameter x must be a number from 1 to 5.')
  end
end

def getValue(_hash, _path)
  _path.to_s.split('.').map(&:to_s).inject(_hash, :[])
end
