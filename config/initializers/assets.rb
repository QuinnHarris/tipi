Rails.application.config.assets.precompile +=
    %w( home categories projects access users/registrations devise/sessions )
    .map { |s| ["#{s}.css", "#{s}.js"] }.flatten
