Rails.application.configure do
  config.enable_reloading = false
  config.action_dispatch.show_exceptions = :rescuable
  config.active_support.deprecation = :stderr
  config.cache_store = :memory_store
end
