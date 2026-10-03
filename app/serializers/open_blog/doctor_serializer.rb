module OpenBlog
  class DoctorSerializer
    def self.call(checks)
      { checks: checks.map { |check| { name: check[:name], status: check[:status], message: check[:message] } } }
    end
  end
end
