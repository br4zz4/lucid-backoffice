# Classification

`config/data_classification.yml` maps `table.column` to a category. `id`, `*_id`, `*_type`, `created_at` and `updated_at` are public by convention; anything else not listed is `unclassified`. Classification changes go through code review: there is no API or screen to edit it, on purpose. Unknown categories fail at boot.
