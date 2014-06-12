Rails.application.config.assets.precompile +=
    %w( home categories projects users/registrations )
    .map { |s| ["#{s}.css", "#{s}.js"] }.flatten
