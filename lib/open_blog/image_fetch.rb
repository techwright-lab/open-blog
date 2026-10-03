require "net/http"
require "resolv"
require "ipaddr"
require "timeout"
require "stringio"
require "marcel"

module OpenBlog
  class ImageFetch
    TIMEOUT = 10
    REDIRECTS = [ 301, 302, 303, 307, 308 ].freeze
    NONPUBLIC_V4 = %w[0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8 169.254.0.0/16
      172.16.0.0/12 192.0.0.0/24 192.0.2.0/24 192.88.99.0/24 192.168.0.0/16
      198.18.0.0/15 198.51.100.0/24 203.0.113.0/24 224.0.0.0/4 240.0.0.0/4].map { |range| IPAddr.new(range) }.freeze
    GLOBAL_V6 = IPAddr.new("2000::/3")
    NONPUBLIC_V6 = %w[2001::/23 2001:db8::/32 2002::/16 3fff::/20].map { |range| IPAddr.new(range) }.freeze
    class DeadlineExceeded < StandardError; end

    def self.call(url, max_bytes: OpenBlog.config.max_image_bytes, policy: OpenBlog.config.image_fetch_policy)
      new(max_bytes: max_bytes, policy: policy).call(url)
    end

    def initialize(max_bytes:, policy:)
      raise Error::ImageNotPermitted unless max_bytes.is_a?(Integer) && max_bytes.positive? && %i[public_only open].include?(policy)
      @max_bytes, @policy = max_bytes, policy
    end

    def call(url)
      @deadline = monotonic + TIMEOUT
      Timeout.timeout(TIMEOUT, DeadlineExceeded) do
        uri = parse_url(url)
        redirects = 0
        loop do
          addresses = Resolv.getaddresses(uri.hostname)
          raise Error::ImageNotPermitted if addresses.empty?
          addresses.each { |address| permitted_address!(address) } unless @policy == :open
          status, location, bytes = download(uri, addresses.first)
          if REDIRECTS.include?(status)
            raise Error::ImageNotPermitted if redirects >= 3 || location.nil?
            uri = parse_url(URI.join(uri.to_s, location).to_s)
            redirects += 1
          else
            raise Error::ImageNotPermitted unless status.between?(200, 299)
            type = Marcel::MimeType.for(StringIO.new(bytes))
            raise Error::ImageNotPermitted if type == "image/svg+xml" || !OpenBlog.config.image_content_types.include?(type)
            filename = File.basename(URI::DEFAULT_PARSER.unescape(uri.path).tr("\\", "/"))
            filename = "image" if filename.blank? || %w[/ . ..].include?(filename)
            return { io: StringIO.new(bytes), content_type: type, filename: filename }
          end
        end
      end
    rescue URI::InvalidURIError, IPAddr::InvalidAddressError, Resolv::ResolvError, SocketError,
      SystemCallError, IOError, EOFError, Net::HTTPBadResponse, Net::HTTPHeaderSyntaxError,
      Timeout::Error, DeadlineExceeded, OpenSSL::SSL::SSLError, ArgumentError
      raise Error::ImageNotPermitted
    end

    private

    def parse_url(value)
      raise Error::ImageNotPermitted unless value.is_a?(String)
      uri = URI.parse(value)
      unless uri.is_a?(URI::HTTP) && uri.hostname.present? && uri.userinfo.nil? && !uri.hostname.include?("%")
        raise Error::ImageNotPermitted
      end
      uri.fragment = nil
      uri
    end

    def permitted_address!(address)
      ip = IPAddr.new(address).native
      public = if ip.ipv4?
        NONPUBLIC_V4.none? { |range| range.include?(ip) }
      else
        GLOBAL_V6.include?(ip) && NONPUBLIC_V6.none? { |range| range.include?(ip) }
      end
      raise Error::ImageNotPermitted unless public
    end

    def download(uri, address)
      http = Net::HTTP.new(uri.hostname, uri.port, nil)
      http.ipaddr = address
      http.use_ssl = uri.scheme == "https"
      http.verify_mode = OpenSSL::SSL::VERIFY_PEER
      http.verify_hostname = true
      http.max_retries = 0
      http.open_timeout = http.read_timeout = http.write_timeout = remaining
      request = Net::HTTP::Get.new(uri.request_uri, "Accept-Encoding" => "identity")
      bytes = +"".b
      result = nil
      http.start do |connection|
        connection.request(request) do |response|
          response.read_body do |chunk|
            raise Error::ImageNotPermitted if bytes.bytesize + chunk.bytesize > @max_bytes
            bytes << chunk
            http.read_timeout = remaining
          end
          result = [ response.code.to_i, response["location"], bytes ]
        end
      end
      remaining
      result
    end

    def remaining
      seconds = @deadline - monotonic
      raise DeadlineExceeded unless seconds.positive?
      seconds
    end

    def monotonic
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
