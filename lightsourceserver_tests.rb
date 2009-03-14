require 'rubygems'
require 'spec'

require 'lightsourceserver_http_handler'
require 'rack'

##################
#  what's left
##################
#
# gem
# template("mytemplate").using_vars("var1" => data1, "var2" => data2)
# filters
#

def request_for(path, host = nil, method = 'GET')
	request_string = "#{method} #{path} HTTP/1.1"
	request_string = "#{request_string}\nHost: #{host}\nCookie: hello=world" if host != nil
	HTTPRequest.new(request_string)
end

def html_response_for(html)
	"HTTP/1.1 200 OK\nContent-Type: text/html\n\n#{html}\n"
end

describe HTTPHandlerBuilder do
	it 'should be able to remove trailing and leading / from /test/' do
		builder = HTTPHandlerBuilder.new
		builder.trim("/test/").should be_eql('test')
	end

	it 'should be able to add a handler for / that serves <html><body>hello world</body></html>' do
		handlers = []
		builder = HTTPHandlerBuilder.new(handlers)

		http_handler = builder.get "/" do |http|
			http.response << "<html><body>hello world</body></html>"
		end

		handlers.length.should be_eql(1)

		http_request = request_for("/")
		http_handler.handles?(http_request).should be_true
		http_handler.request(http_request).class.should be_eql(RackHTTPResponseAdapter)
		http_handler.request(http_request).to_s.should be_eql(html_response_for("<html><body>hello world</body></html>"))
	end

	it 'should be able to yield a new builder by adding a url part' do
		builder = (HTTPHandlerBuilder.new([]) + "test")
		builder.to_s.should be_eql("/test")
	end

	it "should return a handler for /notes/new that serves <html><body>A new note</body></html>" do
		builder = HTTPHandlerBuilder.new([])
		http_handlers = builder.path "/notes" do
			get "/new" do |http|
				http.response << "<html><body>A new note</body></html>"
			end
		end

		http_handlers.length.should be_eql(1)

		http_handler = http_handlers[0]

		http_request = HTTPRequest.new("GET /notes/new HTTP/1.1")
		http_handler.handles?(http_request).should be_true
		http_handler.request(http_request).to_s.should be_eql(html_response_for("<html><body>A new note</body></html>"))
	end

	it 'should return a handler set that responds to /test when requested for a specific domain with <html><body>test</body></html>' do
		builder = HTTPHandlerBuilder.new([])
		http_handlers = builder.hosts "test.com", "www.test.com" do
			get "/test" do |http|
				http.response << "test"
			end
		end

		http_handlers.length.should be_eql(1)

		http_handler = http_handlers[0]

		http_request = HTTPRequest.new("GET /test HTTP/1.1\nHost: test.com\n\n")
		http_handler.handles?(http_request).should be_true
		http_handler.request(http_request).to_s.should be_eql(html_response_for("test"))

		http_request = HTTPRequest.new("GET /test HTTP/1.1\nHost: www.test.com\n\n")
		http_handler.handles?(http_request).should be_true
		http_handler.request(http_request).to_s.should be_eql(html_response_for("test"))
	end

	it 'should return a handler that recognizes that it cannot handle a request for test123.com if it has been configured for notrecognized.com' do
		builder = HTTPHandlerBuilder.new([])
		http_handlers = builder.hosts "test.com" do
			get "/test" do |http|
				http.response << "test"
			end
		end

		http_handlers.length.should be_eql(1)

		http_handler = http_handlers[0]

		http_request = HTTPRequest.new("GET /test HTTP/1.1\nHost: notrecognized.com\n\n")
		http_handler.handles?(http_request).should be_false
	end

	it 'should return a handler that services a request for /test at hosts test1.com and test2.com' do
		builder = HTTPHandlerBuilder.new([])
		http_handlers = builder.hosts ["test1.com", "test2.com"] do
			get "/test" do |http|
				http.response << "test"
			end
		end

		http_handlers.length.should be_eql(1)

		http_handler = http_handlers[0]

		rack_request = Rack::Request.new("REQUEST_METHOD" => "GET", "PATH_INFO" => "/test", "HTTP_HOST" => "test1.com", "HTTP_VERSION" => "HTTP/1.1")
		http_request = RackAdapterHTTPRequest.new(rack_request)
		http_handler.handles?(http_request).should be_true

		rack_request = Rack::Request.new("REQUEST_METHOD" => "GET", "PATH_INFO" => "/test", "HTTP_HOST" => "test2.com", "HTTP_VERSION" => "HTTP/1.1")
		http_request = RackAdapterHTTPRequest.new(rack_request)
		http_handler.handles?(http_request).should be_true

		rack_request = Rack::Request.new("REQUEST_METHOD" => "GET", "PATH_INFO" => "/test", "HTTP_HOST" => "test3.com", "HTTP_VERSION" => "HTTP/1.1")
		http_request = RackAdapterHTTPRequest.new(rack_request)
		http_handler.handles?(http_request).should be_false
	end

	it 'should be able to filter out a url' do
		builder = HTTPHandlerBuilder.new([])
		http_handlers = builder.hosts ["test1.com"] do
			filter "/test" do |http|
				http.response << "Not allowed"
				dont_allow_request
			end
		end

		rack_request = Rack::Request.new("REQUEST_METHOD" => "GET", "PATH_INFO" => "/test", "HTTP_HOST" => "test1.com", "HTTP_VERSION" => "HTTP/1.1")
		http_request = RackAdapterHTTPRequest.new(rack_request)

		http_handlers[0].request(http_request).to_s.should be_eql(html_response_for("Not allowed"))
	end

	it 'should allow a url through a filter by default' do
		builder = HTTPHandlerBuilder.new([])
		http_handlers = builder.hosts ["test1.com"] do
			filter "/filtertest" do |http|
				http.response << "allowed"
			end

			get "/filtertest" do |http|
				http.response << "came to get handler"
			end
		end

		rack_request = Rack::Request.new("REQUEST_METHOD" => "GET", "PATH_INFO" => "/filtertest", "HTTP_HOST" => "test1.com", "HTTP_VERSION" => "HTTP/1.1")
		http_request = RackAdapterHTTPRequest.new(rack_request)
		http_handlers[0].request(http_request).to_s.should be_eql(html_response_for("allowed"))
	end
end

describe HTTPHandler do
	it 'should serve <html><body>hello world</body></html> when requested for / with the verb GET' do
		handler_proc = Proc.new do |http|
			http.response << "<html><body>hello world</body></html>"
		end

		http_handler = HTTPHandler.new({"uri" => "/", "verb" => "GET"}, handler_proc)

		request = HTTPRequest.new("GET / HTTP/1.1")
		http_handler.handles?(request).should be_true
		http_handler.request(request).to_s.should be_eql(html_response_for("<html><body>hello world</body></html>"))
	end

	it 'should serve <html><body>hello world</body></html> when requested for / with host test.com:2000 and with the verb GET, when configured with host test.com' do
		handler_proc = Proc.new do |http|
			http.response << "<html><body>hello world</body></html>"
		end

		http_handler = HTTPHandler.new({"hosts" => ['test.com'], "uri" => "/", "verb" => "GET"}, handler_proc)

		request = HTTPRequest.new("GET / HTTP/1.1\nHost: test.com:2000")
		http_handler.handles?(request).should be_true
		http_handler.request(request).to_s.should be_eql(html_response_for("<html><body>hello world</body></html>"))
	end

	it 'should recognize that it serves /hello/test if configured for /hello with a handler taking parameters http and name' do
		handler_proc = Proc.new do |http, name|
			http.response << "#{name}"
		end

		http_handler = HTTPHandler.new({"uri" => "/hello", "verb" => "GET"}, handler_proc)
		request = HTTPRequest.new("GET /hello/test HTTP/1.1")
		http_handler.handles?(request).should be_true
	end

	it 'should recognize that it serves /hello/test/world if configured for /hello/test with a handler taking parameters http and name, and should not serve for /hello/world' do
		handler_proc = Proc.new do |http, *params|
			http.response << "#{name}"
		end

		http_handler = HTTPHandler.new({"uri" => "/hello/test", "verb" => "GET"}, handler_proc)

		request = HTTPRequest.new("GET /hello/test/world HTTP/1.1")
		http_handler.handles?(request).should be_true

		request = HTTPRequest.new("GET /hello/world HTTP/1.1")
		http_handler.handles?(request).should be_false
	end

	it 'should recognize that it serves /hello/test if configured for /hello/test with a handler taking parameters http and name' do
		handler_proc = Proc.new do |http, name|
			http.response << "#{name}"
		end

		http_handler = HTTPHandler.new({"uri" => "/hello/test", "verb" => "GET"}, handler_proc)
		request = HTTPRequest.new("GET /hello/test HTTP/1.1")
		http_handler.handles?(request).should be_true
	end

	it 'should serve <html><body>test</body></html> when configured for url /hello accessed with url /hello/test' do
		html_creator = Proc.new {|param| "<html><body>#{param}</body></html>" }
		handler_proc = Proc.new do |http, name|
			http.response << html_creator.call(name)
		end

		http_handler = HTTPHandler.new({"uri" => "/hello", "verb" => "GET"}, handler_proc)
		request = HTTPRequest.new("GET /hello/test HTTP/1.1")
		http_handler.handles?(request).should be_true

		http_handler.request(request).to_s.should be_eql(html_response_for(html_creator.call("test")))
	end

	it 'should recognize that it does NOT serve GET /test when configured for GET and POST /test and requested for POST /test' do
		handler_proc = Proc.new do |http, name|
			http.response << "test"
		end

		http_handler = HTTPHandler.new({"uri" => "/test", "verb" => "GET"}, handler_proc)
		request = HTTPRequest.new("POST /hello/test HTTP/1.1")
		http_handler.handles?(request).should be_false
	end

	it 'should use a response object if one is passed to it' do
		handler_proc = Proc.new do |http, name|
			http.response << "test"
		end

		http_handler = HTTPHandler.new({"uri" => "/test", "verb" => "GET"}, handler_proc)
		rack_request = Rack::Request.new("REQUEST_METHOD" => "GET", "PATH_INFO" => "/test", "HTTP_HOST" => "localhost:2000", "HTTP_VERSION" => "HTTP/1.1")
		rack_http_request_adapter = RackAdapterHTTPRequest.new(rack_request)

		rack_http_response_adapter = RackHTTPResponseAdapter.new("1.1", 200)
		rack_http_response_adapter << "some stuff here "

		http_handler.request(rack_http_request_adapter, rack_http_response_adapter).to_s.should be_eql(html_response_for('some stuff here test'))
	end
end

describe "http configuration" do
	def start_http_server(router, ip = "0.0.0.0", port = 80)
		@started_with_ip = ip
		@started_with_port = port
		@started_with_router = router
	end

	it 'should start the http server and serve <html><body>new note</body></html> when queried for /notes/new' do
		http do
			path '/notes' do
				get '/new' do |http|
					http.response << "<html><body>new note</body></html>"
				end
			end
		end

		@started_with_ip.should be_eql("127.0.0.1")
		@started_with_port.should be_eql(80)
		(@started_with_router != nil).should be_true

		router = @started_with_router

		router.request(request_for("/notes/new")).to_s.should be_eql(html_response_for("<html><body>new note</body></html>"))
	end

	it 'should start the http server and serve <html><body>new note</body></html> when queried for /notes/new, and <html><body>new page</body></html> when queried for /pages/new' do
		http do
			path '/notes' do
				get '/new' do |http|
					http.response << "<html><body>new note</body></html>"
				end
			end

			get '/pages/new' do |http|
				http.response << "<html><body>new page</body></html>"
			end
		end

		@started_with_ip.should be_eql("127.0.0.1")
		@started_with_port.should be_eql(80)
		(@started_with_router != nil).should be_true

		router = @started_with_router

		router.request(request_for("/notes/new")).to_s.should be_eql(html_response_for("<html><body>new note</body></html>"))
		router.request(request_for("/pages/new")).to_s.should be_eql(html_response_for("<html><body>new page</body></html>"))
	end

	it 'should start the http server and serve <html><body>new note</body></html> when queried for /notes/new' do
		http "ip" => "127.0.0.1", "port" => 8080  do
			path '/notes' do
				get '/new' do |http|
					http.response << "<html><body>new note</body></html>"
				end
			end
		end

		@started_with_ip.should be_eql("127.0.0.1")
		@started_with_port.should be_eql(8080)
		(@started_with_router != nil).should be_true

		router = @started_with_router

		router.request(request_for("/notes/new")).to_s.should be_eql(html_response_for("<html><body>new note</body></html>"))
	end

	it 'should start an http server and raise a ResourceNotFoundError when queried with with /test for host abc.com, where it is configured with host test.com' do
		http "ip" => "127.0.0.1", "port" => 8080  do
			hosts "test.com" do
				get '/notes/new' do |http|
					http.response << "<html><body>new note</body></html>"
				end
			end
		end

		@started_with_ip.should be_eql("127.0.0.1")
		@started_with_port.should be_eql(8080)
		(@started_with_router != nil).should be_true

		router = @started_with_router

		lambda { router.request(request_for("/notes/new", 'abc.com')) }.should raise_error(ResourceNotFoundError)
	end

	it 'should start an http server and raise a ResourceNotFoundError when queried for / for host 127.0.0.1:8080 given a configured domain localhost' do
		http "ip" => "127.0.0.1", "port" => 8080 do
			hosts 'localhost' do
				get "/" do |http|
					http.response << "<html><body><b>Hello world</b></body></html>"
				end

				get "/test" do |http|
					http.response << "<html><body><b>test</b> without hello world</body></html>"
				end

				path "/test" do
					get "/hello" do |http|
						http.response << "<html><body><h1>Hello</h1> world</body></html>"
					end

					get "/world" do |http|
						http.response << "<html><body>Hello <h1>world</h1></body></html>"
					end
				end
			end
		end

		@started_with_ip.should be_eql("127.0.0.1")
		@started_with_port.should be_eql(8080)
		(@started_with_router != nil).should be_true

		router = @started_with_router

		lambda { router.request(request_for("/test/world", '127.0.0.1:8080')) }.should raise_error(ResourceNotFoundError)
	end
end

describe HTTPRequestRouter do
	it 'should serves <html><body>new note</body></html> for /notes/new and <html><body>new page</body></html> for /pages/new' do
		builder = HTTPHandlerBuilder.new
		handlers = builder.path '/' do
			get '/notes/new' do |http|
				http.response << "<html><body>new note</body></html>"
			end

			get '/pages/new' do |http|
				http.response << "<html><body>new page</body></html>"
			end
		end

		router = HTTPRequestRouter.new(handlers)

		router.request(request_for("/notes/new")).to_s.should be_eql(html_response_for("<html><body>new note</body></html>"))
		router.request(request_for("/pages/new")).to_s.should be_eql(html_response_for("<html><body>new page</body></html>"))
	end

	it 'should raise a 404 if a resource which is not recognized is requested' do
		builder = HTTPHandlerBuilder.new
		handlers = builder.path '/' do
			get '/notes/new' do
				"<html><body>new note</body></html>"
			end
		end

		router = HTTPRequestRouter.new(handlers)
		lambda { router.request(request_for("/")) }.should raise_error(ResourceNotFoundError)
	end

	it 'should support the following verbs GET, POST, PUT, DELETE, HEAD, OPTIONS, TRACE' do
		builder = HTTPHandlerBuilder.new
		handlers = builder.path '/' do
			get '/get' do |http|
				http.response << "get"
			end

			post '/post' do |http|
				http.response << "post"
			end

			put '/put' do |http|
				http.response << "put"
			end

			delete '/delete' do |http|
				http.response << "delete"
			end

			head '/head' do |http|
				http.response << "head"
			end

			options '/options' do |http|
				http.response << "options"
			end

			trace '/trace' do |http|
				http.response << "trace"
			end
		end

		router = HTTPRequestRouter.new(handlers)

		request_test = Proc.new do |verb|
			rack_request = Rack::Request.new("REQUEST_METHOD" => verb, "PATH_INFO" => "/index.html", "HTTP_HOST" => "test.com", "HTTP_VERSION" => "HTTP/1.1")
			http_request = RackAdapterHTTPRequest.new(rack_request)
			router.request(request_for("/#{verb.downcase}", "test.com", verb)).to_s.should be_eql(html_response_for(verb.downcase))
		end

		["GET", "POST", "PUT", "DELETE", "HEAD", "OPTIONS", "TRACE"].each {|verb| request_test.call(verb) }
	end

	it 'should refrain from evaluating the succeeding handlers if a handler returns nil' do
		builder = HTTPHandlerBuilder.new

		handlers = builder.path '/' do
			post 'hello' do |http|
				http.response << "hello"
			end

			get '/test' do |http|
				http.response << "test"
			end
		end

		router = HTTPRequestRouter.new(handlers)

		rack_request = Rack::Request.new("REQUEST_METHOD" => "POST", "PATH_INFO" => "/hello", "HTTP_HOST" => "test.com", "HTTP_VERSION" => "HTTP/1.1", "Content-Type" => "application/x-www-form-urlencoded", 'rack.input' => StringIO.new('hello=world&color=white'))
		http_request = RackAdapterHTTPRequest.new(rack_request)

		router.request(http_request).to_s.should be_eql(html_response_for('hello'))
	end

	it 'should route filtered requests correctly' do
		builder = HTTPHandlerBuilder.new

		handlers = builder.path '/' do
			filter 'filteredhello' do |http|
				http.response << "hello "
			end

			get 'filteredhello' do |http|
				http.response << "test"
			end
		end

		router = HTTPRequestRouter.new(handlers)

		rack_request = Rack::Request.new("REQUEST_METHOD" => "GET", "PATH_INFO" => "/filteredhello", "HTTP_HOST" => "test.com", "HTTP_VERSION" => "HTTP/1.1", "Content-Type" => "application/x-www-form-urlencoded", 'rack.input' => StringIO.new('hello=world&color=white'))
		http_request = RackAdapterHTTPRequest.new(rack_request)
		router.request(http_request).to_s.should be_eql(html_response_for('hello test'))
	end
end

describe HTTPRequest do
	it 'should be able to get the verb GET, http version 1.1, and host test.com from the http packet GET /index.html HTTP/1.1\nHost: test.com\n\nHello world' do
		http_request = HTTPRequest.new("GET /index.html HTTP/1.1\nHost: test.com\n\nHello world")

		http_request.verb.should be_eql("GET")
		http_request.resource.should be_eql("/index.html")
		http_request.http_version.should be_eql("1.1")
		http_request.headers["Host"].should be_eql("test.com")
		http_request.payload.should be_eql("Hello world")
	end

	it 'should have a host header of localhost:2000, given a request having host localhost:2000' do
		http_request = HTTPRequest.new("GET /test.html HTTP/1.1\nHost: localhost:2000\n\ntest")
		http_request.headers["Host"].should be_eql("localhost:2000")
	end
end

describe HTTPResponse do
	it 'should be able to marshal an HTTP response with response code 200, http version 1.1, headers Content-Type: text/html; charset=UTF-8, server LightSourceServer server in ruby, and body <html><body><h1>It works</h1></body></html>n' do
		http_response = HTTPResponse.new("1.1", 200)
		http_response.set_headers  "Content-Type" => "text/html; charset=UTF-8", "Server" => "LightSourceServer server in ruby"
		http_response.body = "<html><body><h1>It works</h1></body></html>"

		response_string = http_response.to_s

		header, body = *(response_string.split("\n\n"))
		header.index("HTTP/1.1 200 OK").should_not be_eql(nil)
		header.index("Content-Type: text/html; charset=UTF-8").should_not be_eql(nil)
		header.index("Server: LightSourceServer server in ruby").should_not be_eql(nil)

		body.should be_eql("<html><body><h1>It works</h1></body></html>\n")
	end

	it "should have 'hello world' in it's body after response << 'hello world'" do
		http_response = HTTPResponse.new("1.1", 200)
		http_response << "hello world"
		http_response.to_s.should be_eql("HTTP/1.1 200 OK\n\nhello world\n")
	end

	it 'should have settable http vesion and response' do
		http_response = HTTPResponse.new("1.1", 200)
		http_response.http_version = "1.0"
		http_response.status_code = 400

		http_response.to_s.should be_eql("HTTP/1.0 400 Bad Request\n\n\n")
	end

	it 'should be redirectable' do
		http_response = HTTPResponse.new("1.1", 200)
		http_response.redirect("http://www.stuff.com")

		http_response.to_s.should be_eql("HTTP/1.1 302 Moved Temporarily\nLocation: http://www.stuff.com\n\n\n")
	end

	it 'should expose the headers of the response' do
		http_response = HTTPResponse.new("1.1", 200)
		http_response.headers.class.should be_eql(Hash)
	end
end

describe HTTPIO do
	it 'should always contain a request and a response object for the current http request' do
		lambda { HTTPIO.new(nil, HTTPResponse.new("1.1", 200)) }.should raise_error(NullParameter)
		lambda { HTTPIO.new(HTTPRequest.new("GET / HTTP/1.1\n\n"), nil) }.should raise_error(NullParameter)
	end
end

describe RackAdapterHTTPRequest do
	it 'should be able to get the verb GET, http version 1.1, host test.com, a payload and GET vars hello=world and color=white from a rack http request' do
		rack_request = Rack::Request.new("REQUEST_METHOD" => "GET", "PATH_INFO" => "/index.html", "HTTP_HOST" => "test.com", "HTTP_VERSION" => "HTTP/1.1", "QUERY_STRING" => "hello=world&color=white", 'rack.input' => StringIO.new('Hello world'))
		http_request = RackAdapterHTTPRequest.new(rack_request)

		http_request.verb.should be_eql("GET")
		http_request.resource.should be_eql("/index.html")
		http_request.http_version.should be_eql("1.1")
		http_request.headers["Host"].should be_eql("test.com")
		http_request.payload.should be_eql("Hello world")
		http_request.GET['hello'].should be_eql('world')
		http_request.GET['color'].should be_eql('white')
	end

	it 'should be able to get the verb POST, http version 1.1, host test.com and FORM vars hello=world and color=white from a rack http request' do
		rack_request = Rack::Request.new("REQUEST_METHOD" => "POST", "PATH_INFO" => "/index.html", "HTTP_HOST" => "test.com", "HTTP_VERSION" => "HTTP/1.1", "Content-Type" => "application/x-www-form-urlencoded", 'rack.input' => StringIO.new('hello=world&color=white'))
		http_request = RackAdapterHTTPRequest.new(rack_request)

		http_request.verb.should be_eql("POST")
		http_request.resource.should be_eql("/index.html")
		http_request.http_version.should be_eql("1.1")
		http_request.headers["Host"].should be_eql("test.com")
		http_request.FORM['hello'].should be_eql('world')
		http_request.FORM['color'].should be_eql('white')
	end

	it 'should have a host header of localhost:2000, given a request having host localhost:2000' do
		rack_request = Rack::Request.new("REQUEST_METHOD" => "GET", "PATH_INFO" => "/index.html", "HTTP_HOST" => "localhost:2000", "HTTP_VERSION" => "HTTP/1.1")
		http_request = RackAdapterHTTPRequest.new(rack_request)
		http_request.headers["Host"].should be_eql("localhost:2000")
	end

	it 'should expose the original rack request property' do
		rack_request = Rack::Request.new("REQUEST_METHOD" => "GET", "PATH_INFO" => "/index.html", "HTTP_HOST" => "localhost:2000", "HTTP_VERSION" => "HTTP/1.1")
		rack_request = Rack::Request.new("REQUEST_METHOD" => "GET", "PATH_INFO" => "/index.html", "HTTP_HOST" => "localhost:2000", "HTTP_VERSION" => "HTTP/1.1")
		http_request = RackAdapterHTTPRequest.new(rack_request)
		http_request.rack_request.class.should be_eql(Rack::Request)
	end

	it 'should support cookies' do
		rack_request = Rack::Request.new("HTTP_COOKIE" => "hello=world", "REQUEST_METHOD" => "GET", "PATH_INFO" => "/index.html", "HTTP_HOST" => "localhost:2000", "HTTP_VERSION" => "HTTP/1.1")
		http_request = RackAdapterHTTPRequest.new(rack_request)
		http_request.cookies['hello'].should be_eql('world')
	end

	it 'should be able to share context between handlers' do
		rack_request = Rack::Request.new("HTTP_COOKIE" => "hello=world", "REQUEST_METHOD" => "GET", "PATH_INFO" => "/index.html", "HTTP_HOST" => "localhost:2000", "HTTP_VERSION" => "HTTP/1.1")
		http_request = RackAdapterHTTPRequest.new(rack_request)
		http_request.context[:hello] = "world"
		http_request.context[:hello].should be_eql("world")
	end
end

describe RackHTTPHeadersAdapter do
	it 'should be able to read the Accept-Encoding header from a hash containing a key HTTP_ACCEPT_ENCODING' do
		rack_headers_adapter = RackHTTPHeadersAdapter.new("HTTP_ACCEPT_ENCODING" => "test encoding")
		rack_headers_adapter["Accept-Encoding"].should be_eql("test encoding")
	end
end

describe RackHTTPResponseAdapter do
	it 'should inherit from HTTPResponse' do
		rack_http_response_adapter = RackHTTPResponseAdapter.new("1.1", 200)
		rack_http_response_adapter.class.ancestors.include?(HTTPResponse).should be_true
	end

	it 'should return a rack response object with the parameters provided' do
		http_response = RackHTTPResponseAdapter.new("1.1", 200)
		http_response.set_headers  "Content-Type" => "text/html; charset=UTF-8", "Server" => "LightSourceServer server in ruby"
		http_response.body = "<html><body><h1>It works</h1></body></html>"

		rack_response = http_response.rack_response
		rack_response["Content-Type"].should be_eql("text/html; charset=UTF-8")
		rack_response["Server"].should be_eql("LightSourceServer server in ruby")
		rack_response.ok?.should be_true

		got_called = false
		rack_response.each {|item| got_called = true; item.should be_eql("<html><body><h1>It works</h1></body></html>") }
		got_called.should be_true
	end

	it 'should return a rack response object which is not an OK response' do
		http_response = RackHTTPResponseAdapter.new("1.1", 302)

		rack_response = http_response.rack_response
		rack_response.ok?.should be_false
	end
end
