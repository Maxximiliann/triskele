import Config

# Use Tzdata for timezone-aware DateTime operations.
# Required by Triskele.Util.Time for America/Denver display conversions.
config :elixir, :time_zone_database, Tzdata.TimeZoneDatabase

import_config "#{config_env()}.exs"
