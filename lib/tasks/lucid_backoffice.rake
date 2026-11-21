namespace :lucid do
  namespace :backoffice do
    desc "Delete activity events older than config.activity_retention"
    task purge: :environment do
      puts "removed #{Lucid::Backoffice::Activity::Purge.call} activity events"
    end
  end
end
