module OpenBlog
  class SurfaceReport
    module Robots
      module_function

      def allowed?(body, path, agent)
        return true if path == "/robots.txt"
        groups = []
        group = nil
        body.to_s.dup.force_encoding("UTF-8").scrub.delete_prefix("\uFEFF").split(/\r\n|\n|\r/).each do |line|
          key, value = line.sub(/#.*/, "").strip.split(":", 2).map(&:strip)
          next unless value
          if key.downcase == "user-agent"
            next unless value.match?(/\A(?:[a-z_-]+|\*)\z/i)
            if !group || group[:started]
              group = { agents: [], rules: [], started: false }
              groups << group
            end
            group[:agents] << value.downcase
          elsif %w[allow disallow].include?(key.downcase) && group
            group[:started] = true
            group[:rules] << [ key.downcase, normalize(value) ] if value.start_with?("/")
          end
        end
        selected = groups.select { |entry| entry[:agents].include?(agent.downcase) }
        selected = groups.select { |entry| entry[:agents].include?("*") } if selected.empty?
        target = normalize(path)
        matches = selected.flat_map { |entry| entry[:rules] }.select do |_kind, pattern|
          ending = pattern.end_with?("$")
          value = ending ? pattern[0...-1] : pattern
          expression = value.split("*", -1).map { |part| Regexp.escape(part) }.join(".*")
          target.match?(Regexp.new("\\A#{expression}#{'\\z' if ending}"))
        end
        winner = matches.max_by { |kind, pattern| [ pattern.delete("*").delete_suffix("$").bytesize, kind == "allow" ? 1 : 0 ] }
        winner.nil? || winner.first == "allow"
      end

      def normalize(value)
        escaped = value.to_s.b.bytes.map { |byte| byte > 127 ? "%%%02X" % byte : byte.chr }.join
        escaped.gsub(/%([0-9a-f]{2})/i) do
          byte = Regexp.last_match(1).to_i(16)
          character = byte.chr
          character.match?(/[a-z0-9._~-]/i) ? character : "%%%02X" % byte
        end
      end
      private_class_method :normalize
    end
  end
end
