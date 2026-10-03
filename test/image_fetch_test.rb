require_relative "test_helper"
require "minitest/mock"
require "net/http"
require "resolv"
require "socket"
require "base64"

class ImageFetchTest < ActiveSupport::TestCase
  PNG = Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/l9sAAAAASUVORK5CYII=").freeze
  PUBLIC_IP = "93.184.216.34"

  class Transport
    attr_accessor :ipaddr, :use_ssl, :verify_mode, :verify_hostname, :max_retries, :open_timeout, :read_timeout, :write_timeout
    attr_reader :requests
    def initialize(response)
      @response, @requests = response, []
    end
    def start
      yield self
    end
    def request(request)
      @requests << request
      yield @response
    end
  end

  test "fetch pins a resolved address while preserving hostname TLS and disabling proxies" do
    transport = Transport.new(response(200, [ PNG ]))
    constructions = []
    Resolv.stub(:getaddresses, [ PUBLIC_IP ]) do
      Net::HTTP.stub(:new, ->(*args) { constructions << args; transport }) do
        fetched = OpenBlog::ImageFetch.call("https://images.example.test/photo.png?size=2")
        assert_equal PNG, fetched[:io].read
        assert_equal "image/png", fetched[:content_type]
        assert_equal "photo.png", fetched[:filename]
        fetched[:io].close
      end
    end
    assert_equal [ [ "images.example.test", 443, nil ] ], constructions
    assert_equal PUBLIC_IP, transport.ipaddr
    assert_equal true, transport.use_ssl
    assert_equal OpenSSL::SSL::VERIFY_PEER, transport.verify_mode
    assert_equal true, transport.verify_hostname
    assert_equal 0, transport.max_retries
    assert_equal "/photo.png?size=2", transport.requests.sole.path
  end

  test "nonpublic literal and DNS addresses are refused without any request" do
    addresses = %w[127.0.0.1 10.0.0.1 172.16.0.1 192.168.1.1 169.254.170.2 0.0.0.0 100.64.0.1 224.0.0.1 198.18.0.1 ::1 :: fc00::1 fe80::1 ::ffff:10.0.0.1 ::ffff:169.254.170.2 2001:db8::1]
    Net::HTTP.stub(:new, ->(*) { flunk "Refused address reached transport" }) do
      addresses.each do |address|
        Resolv.stub(:getaddresses, [ address ]) { assert_refused("https://images.example.test/private") }
      end
      Resolv.stub(:getaddresses, [ PUBLIC_IP, "127.0.0.1" ]) { assert_refused("https://images.example.test/mixed") }
      %w[file:///etc/passwd ftp://example.test/image https://user:pass@example.test/image].each { |url| assert_refused(url) }
    end
  end

  test "three redirect hops succeed and the fourth is refused" do
    [ 3, 4 ].each do |count|
      responses = Array.new(count) { response(302, [ "redirect" ], "location" => "/next.png") } + [ response(200, [ PNG ]) ]
      with_responses(responses) do
        if count == 3
          fetched = OpenBlog::ImageFetch.call("https://images.example.test/start")
          assert_equal PNG, fetched[:io].read
          fetched[:io].close
        else
          assert_refused("https://images.example.test/start")
        end
      end
    end
  end

  test "redirect destinations are checked before connecting" do
    addresses = 0
    resolutions = ->(_) { addresses += 1; addresses == 1 ? [ PUBLIC_IP ] : [ "169.254.170.2" ] }
    calls = 0
    Resolv.stub(:getaddresses, resolutions) do
      Net::HTTP.stub(:new, ->(*) { calls += 1; Transport.new(response(302, [], "location" => "http://internal.example.test/image")) }) do
        assert_refused("https://images.example.test/start")
      end
    end
    assert_equal 1, calls
  end

  test "streaming limits apply to image and redirect bodies and bytes determine type" do
    with_responses([ response(200, [ PNG ], "content-type" => "text/html") ]) do
      fetched = OpenBlog::ImageFetch.call("https://images.example.test/photo", max_bytes: PNG.bytesize)
      assert_equal "image/png", fetched[:content_type]
      fetched[:io].close
    end
    [ response(200, [ PNG, "x" ]), response(302, [ "x" * 100 ], "location" => "/image"),
      response(200, [ "<html>no image</html>" ], "content-type" => "image/png"),
      response(200, [ '<svg xmlns="http://www.w3.org/2000/svg"></svg>' ]) ].each do |entry|
      with_responses([ entry ]) { assert_refused("https://images.example.test/photo", max_bytes: PNG.bytesize) }
    end
  end

  test "open policy fetches from a real local server with a pinned hostname" do
    server = TCPServer.new("127.0.0.1", 0)
    port = server.addr[1]
    reader = Thread.new do
      socket = server.accept
      headers = +""
      headers << socket.gets until headers.end_with?("\r\n\r\n")
      socket.write("HTTP/1.1 200 OK\r\nContent-Length: #{PNG.bytesize}\r\nConnection: close\r\n\r\n")
      socket.write(PNG)
      socket.close
      headers
    end
    Resolv.stub(:getaddresses, [ "127.0.0.1" ]) do
      fetched = OpenBlog::ImageFetch.call("http://unresolvable.example.test:#{port}/image.png", policy: :open)
      assert_equal PNG, fetched[:io].read
      fetched[:io].close
    end
    assert_includes reader.value, "Host: unresolvable.example.test:#{port}"
  ensure
    reader&.kill if reader&.alive?
    server&.close
  end

  test "literal loopback and mapped metadata addresses fail without connecting" do
    Net::HTTP.stub(:new, ->(*) { flunk "Literal address reached transport" }) do
      %w[http://127.0.0.1/a http://[::1]/a http://[::ffff:169.254.170.2]/a].each { |url| assert_refused(url) }
    end
  end

  test "DNS resolution is inside the overall timeout" do
    original_timeout = Timeout.method(:timeout)
    budgets = []
    shortened = lambda do |seconds, exception, &block|
      budgets << seconds
      original_timeout.call(0.03, exception, &block)
    end
    Timeout.stub(:timeout, shortened) do
      Resolv.stub(:getaddresses, ->(_) { sleep 1; [ PUBLIC_IP ] }) do
        assert_refused("https://images.example.test/slow-dns")
      end
    end
    assert_equal [ 10 ], budgets
  end

  test "the same elapsed budget follows redirects and streaming chunks" do
    elapsed = 0
    first = response(302, [], "location" => "/next")
    second = response(200, [])
    first.define_singleton_method(:read_body) { |&block| elapsed += 6; block.call("redirect") }
    second.define_singleton_method(:read_body) { |&block| elapsed += 5; block.call(PNG) }
    fetcher = OpenBlog::ImageFetch.new(max_bytes: 1000, policy: :public_only)
    with_responses([ first, second ]) do
      fetcher.stub(:monotonic, -> { elapsed }) do
        error = assert_raises(OpenBlog::Error::ImageNotPermitted) { fetcher.call("https://images.example.test/start") }
        assert_equal [], error.details
      end
    end
  end

  test "network errors and missing or unsafe redirect locations have generic refusals" do
    Resolv.stub(:getaddresses, ->(_) { raise SocketError, "internal.secret.example: lookup failed" }) do
      assert_refused("https://images.example.test/image")
    end
    [ response(404, []), response(302, []), response(302, [], "location" => "file:///secret") ].each do |entry|
      with_responses([ entry ]) { assert_refused("https://images.example.test/image") }
    end
  end

  private

  def response(status, chunks, headers = {})
    klass = Net::HTTPResponse::CODE_TO_OBJ.fetch(status.to_s)
    result = klass.new("1.1", status.to_s, "Response")
    headers.each { |key, value| result[key] = value }
    result.define_singleton_method(:read_body) { |&block| chunks.each(&block) }
    result
  end

  def with_responses(responses, &block)
    Resolv.stub(:getaddresses, [ PUBLIC_IP ]) do
      Net::HTTP.stub(:new, ->(*) { Transport.new(responses.shift || raise("Unexpected request")) }, &block)
    end
  end

  def assert_refused(url, **options)
    error = assert_raises(OpenBlog::Error::ImageNotPermitted) { OpenBlog::ImageFetch.call(url, **options) }
    assert_equal :image_not_permitted, error.code
    assert_equal [], error.details
    assert_equal "The image input is not supported.", error.message
  end
end
