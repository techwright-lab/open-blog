module OpenBlog
  class Doctor
    module Javascript
      private

      def javascript
        layout = layout_source
        tag = layout.match(/javascript_(importmap_tags|include_tag)\s*(?:\(?\s*)(?:["']([^"']+)["'])?/)
        return [ "error", "The blog layout has no recognizable JavaScript entry point." ] unless tag
        if tag[2].nil? && layout[tag.end(0)..].match?(/\A[^%\s)]/)
          return [ "warning", "Dynamic JavaScript entry point cannot be verified statically." ]
        end
        entry = tag[2] || "application"
        maps = javascript_map_source(layout)
        pins = maps.scan(/\bpin\s+["']([^"']+)["']\s*,\s*to:\s*["']([^"']+)["']/).to_h
        source = javascript_tree(entry, pins: pins)
        return [ "error", "JavaScript entry point #{entry} was not found." ] if source.empty?
        importmap = tag[1] == "importmap_tags"
        loaders = source.scan(/(?:eager|lazy)LoadControllersFrom\s*\(\s*["']([^"']+)["']/).flatten
        missing = Dir[Engine.root.join("app/assets/javascripts/open_blog/controllers/*_controller.js")].filter_map do |path|
          file = File.basename(path)
          name = "open-blog--#{file.delete_suffix('_controller.js').tr('_', '-')}"
          local = @root.join("app/javascript/controllers/open_blog/#{file}")
          next name unless local.file?
          explicit = source.match?(/\.register\s*\(\s*["']#{Regexp.escape(name)}["']/) && source.include?("open_blog/#{file.delete_suffix('.js')}")
          automatic = importmap && loaders.any? do |prefix|
            prefix == "controllers" && maps.match?(/pin_all_from[^\n]*controllers[^\n]*under:\s*["']controllers["']/)
          end
          name unless explicit || automatic
        end
        missing.any? ? [ "error", "Register controllers reachable from #{entry}: #{missing.join(', ')}." ] : [ "ok", "All blog controllers are reachable from #{entry}." ]
      end

      def javascript_map_source(layout)
        custom = layout[/importmap:\s*([\w.]+)/, 1]
        return read("config/importmap.rb") if custom.nil? || custom == "Rails.application.importmap"
        name = custom.split(".").last.sub(/\Aimportmap_/, "")
        read("config/importmap_#{name}.rb")
      end

      def javascript_tree(specifier, from: nil, seen: [], pins: {})
        specifier = pins.fetch(specifier, specifier)
        base = if specifier.start_with?(".") && from
          from.dirname.join(specifier)
        else
          @root.join("app/javascript", specifier)
        end
        file = [ base, Pathname("#{base}.js"), base.join("index.js") ].find(&:file?)
        return "" unless file && !seen.include?(file.cleanpath.to_s)
        seen << file.cleanpath.to_s
        source = file.read
        imports = source.scan(/\bimport\s+(?:[^;\n]*?\s+from\s+)?["']([^"']+)["']/).flatten
        source + imports.map { |name| javascript_tree(name, from: file, seen: seen, pins: pins) }.join("\n")
      end
    end
  end
end
