module OpenBlog
  class Renderer
    module RichText
      def self.render(text, post: nil)
        ActionText::Content.new(text.to_s).render_attachments(with_full_attributes: false) do |attachment|
          blob = attachment.attachable
          image = ImageResolution.image_for_attachment(blob, post: post) if blob.is_a?(ActiveStorage::Blob)
          if image
            caption = PlainText.from_html(attachment.caption.to_s)
            alt = attachment.node["alt"].presence || caption
            ActionText::Content.render(partial: "open_blog/attachments/blob", locals: { image: image, alt: alt, caption: caption })
          else
            ERB::Util.html_escape(PlainText.from_html(attachment.caption.to_s))
          end
        end.to_html
      end
    end
  end
end
