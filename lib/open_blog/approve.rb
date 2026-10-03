module OpenBlog
  class Approve
    def self.call(post, revision_identifier:, name:, facts_checked:, actor:, now: Time.current)
      Operation.run(post: post, actor: actor, now: now) do |current, _created|
        raise Error::NotFound unless current.persisted?
        unless name.is_a?(String) && name.present? && [ true, false ].include?(facts_checked)
          raise Error::ApprovalIncomplete
        end
        revision = current.public_revision
        raise Error::RevisionMismatch unless revision && revision.identifier == revision_identifier

        current.approvals.create!(revision: revision, kind: "sent", reviewer_name: name,
          facts_checked: facts_checked, approved_at: now, recorded_by: actor)
        { revision: "same", publication: nil, approval: "sent" }
      end
    end
  end
end
