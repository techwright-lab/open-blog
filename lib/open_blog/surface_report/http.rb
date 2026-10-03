require "net/http"
require "resolv"
require "ipaddr"
require "timeout"
require_relative "../image_fetch"

module OpenBlog
  class SurfaceReport
    class Http
      Response = Struct.new(:status, :headers, :body, :url, keyword_init: true)
      class FetchError < StandardError
        def initialize(_message = nil) = super("Request unavailable")
      end

      def initialize(trusted_origin: nil, max_bytes: 10 * 1024 * 1024, timeout: 10, client: nil)
        raise ArgumentError unless max_bytes.is_a?(Integer) && max_bytes.positive? && timeout.is_a?(Numeric) && timeout.positive?
        @trusted_origin = origin(parse(trusted_origin)) if trusted_origin
        @max_bytes, @timeout, @client = max_bytes, timeout, client
      end

      def get(url)
        uri = parse(url)
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + @timeout
        Timeout.timeout(@timeout, FetchError) do
          headers = { "User-Agent" => "OpenBlogSurfaceBot", "Accept-Encoding" => "identity", "Accept" => "*/*" }
          if @client
            response = @client.get(uri.to_s, headers: headers)
            body = response.body.to_s.b
            raise FetchError if body.bytesize > @max_bytes
            return Response.new(status: response.status.to_i, headers: normalize_headers(response.headers), body: body, url: uri.to_s)
          end
          addresses = Resolv.getaddresses(uri.hostname)
          raise FetchError if addresses.empty?
          addresses.each { |address| public_address!(address) } unless origin(uri) == @trusted_origin
          http = Net::HTTP.new(uri.hostname, uri.port, nil)
          http.ipaddr = addresses.first
          http.use_ssl = uri.scheme == "https"
          http.verify_mode = OpenSSL::SSL::VERIFY_PEER
          http.verify_hostname = true
          http.max_retries = 0
          http.open_timeout = http.read_timeout = http.write_timeout = remaining(deadline)
          result = nil
          http.start do |connection|
            connection.request(Net::HTTP::Get.new(uri.request_uri, headers)) do |response|
              bytes = +"".b
              response.read_body do |chunk|
                raise FetchError if bytes.bytesize + chunk.bytesize > @max_bytes
                bytes << chunk
                http.read_timeout = remaining(deadline)
              end
              result = Response.new(status: response.code.to_i, headers: normalize_headers(response.to_hash), body: bytes, url: uri.to_s)
            end
          end
          remaining(deadline)
          result
        end
      rescue URI::InvalidURIError, IPAddr::InvalidAddressError, Resolv::ResolvError, SocketError, SystemCallError,
        IOError, EOFError, Net::HTTPBadResponse, Net::HTTPHeaderSyntaxError, Timeout::Error, OpenSSL::SSL::SSLError, ArgumentError
        raise FetchError
      end

      private

      def parse(value)
        raise FetchError unless value.is_a?(String)
        uri = URI.parse(value)
        raise FetchError unless uri.is_a?(URI::HTTP) && uri.hostname.present? && uri.userinfo.nil? && !uri.hostname.include?("%")
        uri.fragment = nil
        uri
      end

      def origin(uri) = [ uri.scheme.downcase, uri.hostname.downcase, uri.port ]

      def public_address!(value)
        ip = IPAddr.new(value).native
        valid = ip.ipv4? ? ImageFetch::NONPUBLIC_V4.none? { |range| range.include?(ip) } :
          ImageFetch::GLOBAL_V6.include?(ip) && ImageFetch::NONPUBLIC_V6.none? { |range| range.include?(ip) }
        raise FetchError unless valid
      end

      def normalize_headers(headers)
        headers.to_h.to_h { |key, value| [ key.to_s.downcase, Array(value).join(", ") ] }
      end

      def remaining(deadline)
        seconds = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
        raise FetchError unless seconds.positive?
        seconds
      end
    end
  end
end
