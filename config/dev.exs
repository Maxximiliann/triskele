import Config

config :logger, :console,
  format: "[$level] $message\n",
  metadata: [:request_id]
