require_relative "test_helper"
require "minitest/mock"
require "socket"
require_relative "../lib/open_blog/surface_report/http"

class SurfaceReportHttpTest < ActiveSupport::TestCase
  class Transport
    attr_accessor :ipaddr, :use_ssl, :verify_mode, :verify_hostname, :max_retries, :open_timeout, :read_timeout, :write_timeout
    attr_reader :requests
    def initialize(chunks)
      @chunks, @requests = chunks, []
    end
    def start = yield self
    def request(request)
      @requests << request
      response = Struct.new(:code, :chunks) do
        def to_hash = { "content-type" => [ "text/html" ] }
        def read_body = chunks.each { |chunk| yield chunk }
      end.new("200", @chunks)
      yield response
    end
  end

  test "network connections pin checked DNS preserve TLS identity and enforce streaming bounds" do
    transport = Transport.new([ "abc", "def" ])
    constructions = []
    Resolv.stub(:getaddresses, [ "93.184.216.34" ]) do
      Net::HTTP.stub(:new, ->(*args) { constructions << args; transport }) do
        result = OpenBlog::SurfaceReport::Http.new.get("https://public.example/page")
        assert_equal "abcdef", result.body
        assert_raises(OpenBlog::SurfaceReport::Http::FetchError) { OpenBlog::SurfaceReport::Http.new(max_bytes: 5).get("https://public.example/page") }
      end
    end
    assert_equal [ "public.example", 443, nil ], constructions.first
    assert_equal "93.184.216.34", transport.ipaddr
    assert transport.use_ssl
    assert transport.verify_hostname
    assert_equal OpenSSL::SSL::VERIFY_PEER, transport.verify_mode
    assert_equal 0, transport.max_retries
    assert_operator transport.open_timeout, :<=, 10
    assert_equal "identity", transport.requests.first["Accept-Encoding"]
  end

  test "a trusted origin never grants its trust to another port host or scheme" do
    http = OpenBlog::SurfaceReport::Http.new(trusted_origin: "http://localhost:3000")
    Resolv.stub(:getaddresses, [ "127.0.0.1" ]) do
      Net::HTTP.stub(:new, ->(*) { flunk "Origin trust escaped" }) do
        %w[http://localhost:3001/ http://other.test:3000/ https://localhost:3000/].each do |url|
          assert_raises(OpenBlog::SurfaceReport::Http::FetchError) { http.get(url) }
        end
      end
    end
  end

  test "injected slow transport has a total deadline and never exposes transport messages" do
    client = Object.new
    client.define_singleton_method(:get) { |*_, **_| sleep 0.1 }
    error = assert_raises(OpenBlog::SurfaceReport::Http::FetchError) do
      OpenBlog::SurfaceReport::Http.new(client: client, timeout: 0.01).get("https://example.test/")
    end
    assert_equal "Request unavailable", error.message
  end

  test "untrusted private destinations and malformed URLs never connect" do
    http = OpenBlog::SurfaceReport::Http.new
    Net::HTTP.stub(:new, ->(*) { flunk "Unsafe transport" }) do
      [ "127.0.0.1", "169.254.169.254", "::1", "::ffff:10.0.0.1", "2001:db8::1" ].each do |address|
        Resolv.stub(:getaddresses, [ address ]) { assert_raises(OpenBlog::SurfaceReport::Http::FetchError) { http.get("https://other.test/page") } }
      end
      %w[file:///etc/passwd https://user:secret@other.test/].each do |url|
        assert_raises(OpenBlog::SurfaceReport::Http::FetchError) { http.get(url) }
      end
    end
  end

  test "explicit trusted origin fetches loopback with a bot user agent and preserves raw bytes without following redirects" do
    server = TCPServer.new("127.0.0.1", 0)
    origin = "http://127.0.0.1:#{server.addr[1]}"
    worker = Thread.new do
      client = server.accept
      request = +""
      request << client.gets until request.end_with?("\r\n\r\n")
      client.write("HTTP/1.1 302 Found\r\nLocation: http://169.254.169.254/secret\r\nContent-Length: 2\r\nConnection: close\r\n\r\n\xFF\x00".b)
      client.close
      request
    end
    result = OpenBlog::SurfaceReport::Http.new(trusted_origin: origin).get("#{origin}/page")
    assert_equal 302, result.status
    assert_equal "http://169.254.169.254/secret", result.headers["location"]
    assert_equal "\xFF\x00".b, result.body
    assert_equal "#{origin}/page", result.url
    assert_match(/User-Agent: OpenBlogSurfaceBot/i, worker.value)
  ensure
    server&.close
    worker&.join(1)
  end

  test "injected client receives headers and enforces body size" do
    calls = []
    client = Object.new
    client.define_singleton_method(:get) do |url, headers:|
      calls << [ url, headers ]
      Struct.new(:status, :headers, :body).new(200, { "Content-Type" => "text/html" }, "abcd")
    end
    http = OpenBlog::SurfaceReport::Http.new(client: client, max_bytes: 3)
    assert_raises(OpenBlog::SurfaceReport::Http::FetchError) { http.get("https://example.test/") }
    assert_match(/Bot/, calls.sole.last.fetch("User-Agent"))
  end
end
