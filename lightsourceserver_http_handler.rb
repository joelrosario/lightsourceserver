class HTTPHandler
	def initialize(http_request, handler)
		@http_request = http_request
		@handler = handler
	end

	def self.create(http_request, &handler)
		HTTPHandler.new(http_request, handler)
	end

	def hosts_are_not_configured
		!(@http_request.has_key?("hosts")) || @http_request["hosts"].length == 0
	end

	def remove_port_from_host(host)
		host.split(':')[0]
	end

	def handler_host_matches(http_request)
		return true if hosts_are_not_configured
		return false if !(http_request.headers.has_key?("Host"))

		host = remove_port_from_host(http_request.headers["Host"])

		return @http_request["hosts"].include?(host)
	end

	def strip_slashes(str)
		str = str.dup.strip
		str = str[1...str.length] if str[0..0] == '/'
		str = str[0...(str.length - 1)] if str[(str.length - 1)..(str.length - 1)] == '/'
		return str
	end

	def url_params_from(incoming_url)
		if incoming_url.length > @http_request["uri"].length && incoming_url.index(@http_request["uri"]) == 0
			current_url = @http_request["uri"].dup
			incoming_url = incoming_url.sub(current_url, "")
			return strip_slashes(incoming_url).split('/')
		end

		return []
	end

	def handled_resource_matches(http_request)
		return true if http_request.resource == @http_request["uri"]

		url_params = url_params_from(http_request.resource.dup)

		return false if url_params.length == 0
		return (url_params.length == @handler.arity - 1 && @handler.arity.abs >= 2) || @handler.arity < -1
	end

	def handled_verb_matches(http_request)
		http_request.verb == @http_request["verb"] || @http_request["verb"] == "*"
	end

	def handles?(http_request)
		return true if	handled_verb_matches(http_request) &&
				handled_resource_matches(http_request) &&
				handler_host_matches(http_request)

		return false
	end

	def method_missing(m, *args)
		@handler.binding.send(m, args)
	end

	def httpio_for(request, response = nil)
		response = RackHTTPResponseAdapter.new("1.1", 200) if response == nil
		response.set_headers("Content-Type" => "text/html")
		url_params = url_params_from(request.resource)

		return HTTPIO.new(request, response)
	end

	def completed(response)
		response.complete
		return response
	end

	def request(request = nil, response = nil)
		raise "request cannot be nil" if request == nil
		return FALSE if !self.handles?(request)

		httpio = httpio_for(request, response)
		url_params = url_params_from(request.resource)
		params = [httpio]
		params = (params << url_params).flatten if (url_params.length == @handler.arity - 1) || @handler.arity < -1
		@handler.call(*params).tap {|result| return httpio.response if @http_request["verb"] == "*" && result != :response_not_allowed }

		return completed(httpio.response)
	end
end

class HTTPHandlerBuilder
	def initialize(handlers = [], url_part = "")
		@handlers = handlers
		@url_part = add_slash(trim(url_part))
		@hosts = []
	end

	def add_slash(str)
		"/#{str}"
	end

	def trim(str)
		str = str[1...str.length] if str[0..0] == '/'
		last_index = str.length - 1
		str = str[0...last_index] if str[last_index..last_index] == '/'

		return str
	end

	def +(url_part)
		url_part = trim(url_part)
		builder = HTTPHandlerBuilder.new(@handlers, [trim(@url_part), trim(url_part)].join("/"))
		builder.set_hosts(@hosts)
		return builder
	end

	def add_handler(hosts, verb, handler_proc)
		@handlers << HTTPHandler.new({"verb" => verb, "uri" => @url_part, "hosts" => hosts}, handler_proc)
	end

	def method(method_name, url_part, handler_proc)
		(self + url_part).add_handler(@hosts, method_name.upcase, handler_proc)
		return @handlers.last
	end

	def get(url_part, &handler_proc)
		method("GET", url_part, handler_proc)
	end
	def post(url_part, &handler_proc)
		method("POST", url_part, handler_proc)
	end
	def put(url_part, &handler_proc)
		method("PUT", url_part, handler_proc)
	end
	def delete(url_part, &handler_proc)
		method("DELETE", url_part, handler_proc)
	end
	def head(url_part, &handler_proc)
		method("HEAD", url_part, handler_proc)
	end
	def options(url_part, &handler_proc)
		method("OPTIONS", url_part, handler_proc)
	end
	def trace(url_part, &handler_proc)
		method("TRACE", url_part, handler_proc)
	end

	def filter(url_part, &handler_proc)
		method("*", url_part, handler_proc)
	end

	def path(url_part, &handler_proc)
		(self + url_part).instance_eval(&handler_proc)
		return @handlers
	end

	def dont_allow_request
		:response_not_allowed
	end

	def set_hosts(hosts)
		hosts.each {|host| @hosts << host if !@hosts.include?(host) }
	end

	def hosts(*hosts, &handler_proc)
		builder = HTTPHandlerBuilder.new(@handlers, @url_part)
		builder.set_hosts(hosts.flatten)
		builder.instance_eval(&handler_proc)
		return @handlers
	end

	def to_s
		@url_part
	end
end

class ResourceNotFoundError < RuntimeError
	attr_reader :message

	def initialize(message)
		@message = message
	end
end

class NullParameter < RuntimeError
	def initialize(parameter_name)
		@parameter_name = parameter_name
	end

	def to_s
		"#{@parameter_name} cannot be null"
	end
end

class HTTPIO
	attr_reader :request, :response

	def initialize(request, response)
		raise NullParameter.new("request") if request == nil
		raise NullParameter.new("response") if response == nil

		@request, @response = request, response
	end
end

class HTTPRequestRouter
	def initialize(handlers)
		@handlers = handlers
	end

	def request(request)
		response = nil

		@handlers.each do |handler|
			result = handler.request(request, response)
			response = result if result.is_a? RackHTTPResponseAdapter
			return response if result != FALSE && response.complete?
		end

		raise ResourceNotFoundError.new("Handler not found for request:<br>#{request.inspect}")
	end
end

def http(server_options = {}, &block)
	handlers = []
	builder = HTTPHandlerBuilder.new(handlers)
	builder.instance_eval(&block)

	ip = server_options['ip'] || '127.0.0.1'
	port = server_options['port'] || 80

	start_http_server(HTTPRequestRouter.new(handlers), ip, port)

	return handlers
end

class RackHTTPHeadersAdapter
	def initialize(rack_env)
		@rack_env = rack_env
	end

	def [](key)
		env_key = "HTTP_#{key.upcase}".gsub("-", "_")
		return @rack_env[env_key]
	end

	def has_key?(key)
		key = "HTTP_#{key.upcase}".gsub("-", "_")
		@rack_env.has_key?(key)
	end
end

class RackAdapterHTTPRequest
	attr_reader :rack_request, :context

	def initialize(rack_request)
		@rack_request = rack_request
		@rack_http_headers = RackHTTPHeadersAdapter.new(rack_request.env)
		@context = Hash.new
	end

	def verb
		@rack_request.request_method
	end

	def resource
		@rack_request.path_info
	end

	def http_version
		parts = @rack_request.env['HTTP_VERSION'].split("/")
		return parts[1] if parts.length > 1
		return nil
	end

	def  headers
		@rack_http_headers
	end

	def payload
		stream = @rack_request.env['rack.input']
		data = stream.read(stream.length)
		stream.rewind
		return data
	end

	def GET
		@rack_request.GET
	end

	def FORM
		@rack_request.POST
	end

	def cookies
		@rack_request.cookies
	end
end

class HTTPRequest
	attr_reader :verb, :resource, :http_version, :headers, :payload

	def initialize(http_request_string)
		lines = http_request_string.split("\n")

		@verb, @resource, @http_version = HTTPRequest.first_line_info(lines[0])
		@headers, @payload = HTTPRequest.headers_and_payload(lines[1...lines.length])
	end

	def self.first_line_info(first_line)
		first_line_parts = first_line.squeeze(' ').split(" ")
		return first_line_parts[0], first_line_parts[1], first_line_parts[2].split("/")[1]
	end

	def self.headers_and_payload(lines)
		headers = {}
		payload = nil
		handler = nil

		payload_handler = Proc.new {|line|
			payload = "#{payload}\n" if payload != nil
			payload = "#{payload}#{line}"
		}

		header_handler = Proc.new {|line|
			if line.strip == ""
				handler = payload_handler
			else
				header_parts = line.split(':')
				key = header_parts[0]
				value = header_parts[1...header_parts.length].join(':')
				headers[key] = value.strip
			end
		}

		handler = header_handler

		lines.each {|line|
			handler.call(line)
		}

		return headers, payload
	end
end

module HTTPStatus
	@@status_codes = {
		200 => 'OK',
		301 => 'Moved Permanently',
		302 => 'Moved Temporarily',
		304 => 'Not Modified',
		307 => 'Temporary Redirect',
		400 => 'Bad Request',
		401 => 'Unauthorized',
		403 => 'Forbidden',
		404 => 'Not Found',
		405 => 'Method Not Allowed',
		406 => 'Not Acceptable',
		407 => 'Proxy Authentication Required',
		408 => 'Request Timeout',
		500 => 'Internal Server Error',
		501 => 'Not Implemented',
		502 => 'Bad Gateway',
		503 => 'Service Unavailable',
		504 => 'Gateway Timeout'
	}

	def self.message(status_code)
		raise "HTTP status code not supported" if @@status_codes[status_code] == nil
		return @@status_codes[status_code]
	end
end

class HTTPResponse
	attr_accessor :body, :http_version, :status_code, :headers

	def initialize(http_version, status_code)
		@http_version, @status_code = http_version, status_code
		@headers = {}
		@body = ""
	end

	def set_headers(hash)
		hash.keys.each {|key| @headers[key] = hash[key] }
	end

	def << (value)
		@body = @body + value
	end

	def redirect(url)
		@status_code = 302
		@headers['Location'] = url
	end

	def complete
		@complete = true
	end

	def complete?
		@complete == true
	end

	def to_s
		headers = @headers.keys.collect {|key| "#{key}: #{@headers[key]}" }.join("\n")
		status_code = HTTPStatus.message @status_code
		headers = ["HTTP/#{@http_version} #{@status_code} #{status_code}", headers].join("\n").strip
		"#{headers}\n\n#{@body}\n"
	end
end

class RackHTTPResponseAdapter < HTTPResponse
	def initialize(http_version, status_code)
		super(http_version, status_code)
	end

	def rack_response
		Rack::Response.new([@body].flatten, @status_code, @headers)
	end
end
