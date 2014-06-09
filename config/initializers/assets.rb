Rails.application.config.assets.precompile +=
    %w( home categories projects )
    .map { |s| ["#{s}.css", "#{s}.js"] }.flatten
