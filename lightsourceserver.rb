puts "rubygems"
require 'rubygems'

require 'rack'
require 'thin'
#require 'webrick'
#require 'rack/handler/webrick'

require 'lightsourceserver_http_handler'

class LightSourceServerRackAdapter
	def initialize(router)
		@router = router
	end

	def call(env)
		router = @router
		response = nil

		begin
			http_request = RackAdapterHTTPRequest.new(Rack::Request.new(env))
			response = router.request(http_request)
		rescue ResourceNotFoundError => e
			response = RackHTTPResponseAdapter.new("1.1", 404)
			response.body = "<html><head><title>404 Error</title></head><body>#{e.message}</body></html>"
			response.set_headers("Content-Type" => "text/html")
		rescue Object => e
			error_backtrace = e.backtrace[1...e.backtrace.length].collect {|line| "\t#{line}" }.join("\n")
			puts "\nUNEXPECTED ERROR for request: #{env.inspect}"
			puts "#{e.backtrace[0]}: #{e.message}\n#{error_backtrace}"
			response = RackHTTPResponseAdapter.new("1.1", 503)
			response.body = "<html><head><title>503 Error</title></head><body>An internal error occurred. We'll fix the problem shortly.</body></html>"
			response.set_headers("Content-Type" => "text/html")
		end

		response.rack_response.finish
	end
end

def start_thin_http_server(router, ip = "0.0.0.0", port = 8080)
	Thin::Server::start(ip, port) do
		use Rack::CommonLogger
		use Rack::ShowExceptions

		run LightSourceServerRackAdapter.new(router)
	end
end

def start_webrick_server(router, ip = "0.0.0.0", port = 8080)
	Rack::Handler::CGI.run LightSourceServerRackAdapter.new(router), :Port => port
end

def start_http_server(router, ip = "0.0.0.0", port = 8080)
	start_thin_http_server(router, ip, port)
end
