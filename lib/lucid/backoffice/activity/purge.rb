module Lucid
  module Backoffice
    module Activity
      # Deletes, in batches, the events older than the retention period.
      module Purge
        module_function

        # @return [Integer] how many events were removed
        def call(now: Time.current)
          config = Lucid::Backoffice.configuration
          cutoff = now - config.activity_retention
          total = 0
          loop do
            ids = Event.where("occurred_at < ?", cutoff).limit(config.activity_purge_batch).pluck(:id)
            break if ids.empty?

            total += Event.unscoped.where(id: ids).delete_all
          end
          total
        end
      end
    end
  end
end
