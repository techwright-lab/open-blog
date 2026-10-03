require "digest"
require "commonmarker"

module OpenBlog
  class FaqExtraction
    HEADING = /\A[ \t]*(\#{2,6})[ \t]+(.+?)(?:[ \t]+\#+)?[ \t]*\z/
    FAQ_TITLE = /\bFAQ\b|\A(?:Frequently asked questions|Common questions|Q&A)/i
    PLAIN_NODES = %i[document paragraph text softbreak].freeze

    def self.call(body:, standalone_questions: [])
      new(body, standalone_questions).call
    end

    def self.faq_heading?(text)
      text.is_a?(String) && text.match?(FAQ_TITLE)
    end

    def self.contains_faq_heading?(body)
      body.to_s.each_line.any? do |line|
        match = HEADING.match(line.chomp)
        match && [ 2, 3 ].include?(match[1].length) && faq_heading?(match[2])
      end
    end

    def initialize(body, standalone_questions)
      unless body.is_a?(String) && body.valid_encoding? && standalone_questions.is_a?(Array) && standalone_questions.all? { |question| question.is_a?(String) }
        raise Error::ValidationFailed.new(details: [ "body", "standalone_questions" ])
      end
      @body, @standalone_questions = body, standalone_questions
      @pairs, @leftover, @reasons, @cut = [], [], [], []
      @lines = scan_lines
    end

    def call
      headings = @lines.select { |line| [ 2, 3 ].include?(line[:level]) && self.class.faq_heading?(line[:heading]) }
      @reasons << "faq_heading_in_code" if headings.any? { |line| line[:code] }
      headings = headings.reject { |line| line[:code] }
      @reasons << "multiple_faq_headings" if headings.length > 1
      sections = []
      sections << section(headings.first, standalone: false) if headings.first
      @lines.each do |line|
        next unless !line[:code] && line[:level] == 2 && @standalone_questions.include?(line[:heading])
        next if sections.any? { |existing| line[:start] >= existing[:start] && line[:start] < existing[:end] }
        sections << section(line, standalone: true)
      end
      sections.sort_by { |entry| entry[:start] }.each { |entry| extract_section(entry) }
      questions = @pairs.map { |pair| pair[:question] }
      @reasons << "duplicate_question" if questions.uniq.length != questions.length
      @reasons << "leftover_text" if @leftover.any?
      @reasons.uniq!
      @cut = @cut.each_with_object([]) do |range, merged|
        if merged.last && range[:start] <= merged.last[:end]
          merged.last[:end] = [ merged.last[:end], range[:end] ].max
        else
          merged << range.dup
        end
      end
      { pairs: @pairs, cut: @cut, body_after: cut_body, leftover: @leftover,
        class: @reasons.any? ? "review" : (@cut.any? ? "clean" : "none"),
        reasons: @reasons, source_body_sha256: Digest::SHA256.hexdigest(@body) }
    end

    private

    def scan_lines
      offset = 0
      fence = nil
      @body.each_line.map do |raw|
        text = raw.chomp
        was_fenced = !fence.nil?
        if fence
          fence = nil if text.match?(/\A {0,3}#{Regexp.escape(fence[0])}{#{fence.length},}[ \t]*\z/)
        elsif (opening = text.match(/\A {0,3}(`{3,}|~{3,})/))
          fence = opening[1]
        end
        match = HEADING.match(text)
        line = { text: text, start: offset, end: offset + raw.bytesize,
          level: match && match[1].length, heading: match && match[2],
          code: was_fenced || !fence.nil? || text.match?(/\A(?: {4}|\t)/) }
        offset += raw.bytesize
        line
      end
    end

    def section(heading, standalone:)
      following = @lines.find { |line| line[:start] > heading[:start] && line[:level] == 2 && !line[:code] }
      { start: heading[:start], end: following ? following[:start] : @body.bytesize,
        heading: heading, standalone: standalone }
    end

    def extract_section(section)
      @cut << section.slice(:start, :end)
      heading = section[:heading]
      if section[:standalone]
        @reasons << "standalone_question"
        add_pair(heading[:heading], bytes(heading[:end], section[:end]), bold: false)
        return
      end
      lines = @lines.select { |line| line[:start] >= heading[:end] && line[:start] < section[:end] }
      candidates = lines.reject { |line| line[:code] }
      level = candidates.any? { |line| line[:level] == 4 } ? 4 : 3
      questions = candidates.select { |line| line[:level] == level }
      bold = questions.empty?
      questions = candidates.select { |line| bold_question(line[:text]) } if bold
      if questions.empty?
        add_leftover(bytes(heading[:end], section[:end]))
        @reasons << "questions_absent" if @leftover.empty?
        return
      end
      add_leftover(bytes(heading[:end], questions.first[:start]))
      questions.each_with_index do |line, index|
        finish = questions[index + 1]&.fetch(:start) || section[:end]
        answer = bytes(line[:end], finish)
        if bold
          match = bold_question(line[:text])
          question = match[1]
          answer = "#{match[2]}\n#{answer}" if match[2].present?
        else
          question = line[:heading]
        end
        add_pair(question, answer, bold: bold)
      end
    end

    def bold_question(text)
      text.match(/\A {0,3}\*\*(.+?)\*\*[ \t]*(.*)\z/)
    end

    def add_pair(question, answer, bold:)
      question = question.strip
      plain_question = PlainText.from_markdown(question)
      if plain_question != question
        @reasons << "markdown_in_question"
        question = plain_question
      end
      answer = answer.gsub(/\r\n?/, "\n").strip
      @reasons << "question_without_question_mark" unless question.end_with?("?")
      @reasons << "answer_absent" if answer.empty?
      @reasons << "multiline_bold_answer" if bold && answer.lines.length > 1
      nodes = Commonmarker.parse(answer, options: { extension: { autolink: false } })
      types = node_types(nodes)
      @reasons << "heading_in_answer" if types.include?(:heading)
      if (types - PLAIN_NODES).any? || plain_text(nodes).strip != answer
        @reasons << "markdown_in_answer"
        answer = PlainText.from_markdown(answer)
      end
      @pairs << { question: question, answer: answer }
    end

    def plain_text(node)
      return node.literal if node.type == :text
      return "\n" if node.type == :softbreak
      node.each.map { |child| plain_text(child) }.join(node.type == :document ? "\n\n" : "")
    end

    def node_types(node)
      [ node.type ] + node.each.flat_map { |child| node_types(child) }
    end

    def add_leftover(text)
      @leftover << text.strip if text.present?
    end

    def bytes(start, finish)
      @body.byteslice(start...finish)
    end

    def cut_body
      result = @body.dup
      @cut.reverse_each do |range|
        before = result.byteslice(0...range[:start]).rstrip
        after = result.byteslice(range[:end]..-1).to_s
        result = if before.empty?
          after
        elsif after.empty?
          "#{before}\n"
        else
          "#{before}\n\n#{after}"
        end
      end
      result
    end
  end
end
