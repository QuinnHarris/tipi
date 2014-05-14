namespace :test do
  task :prepare => 'db:test:prepare' do
    previous_env, Rails.env = Rails.env, 'test'
    puts "Seeding database"
    Rake::Task["db:seed"].execute
    Rails.env = previous_env
  end
end
