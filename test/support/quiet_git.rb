module QuietGit
  SETTINGS = { "gc.auto" => "0", "gc.autoDetach" => "false", "maintenance.auto" => "false", "receive.autoGC" => "false" }.freeze

  # Detached maintenance outlives the git command and races the removal of the temporary directory.
  def disable_background_maintenance(*repository)
    SETTINGS.each { |key, value| git(*repository, "config", key, value) }
  end
end
