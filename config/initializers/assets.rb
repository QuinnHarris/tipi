Rails.application.config.assets.precompile +=
    %w( home categories projects access users/registrations devise/sessions mockups)
    .map { |s| ["#{s}.css", "#{s}.js"] }.flatten
