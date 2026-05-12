import Config

# ---------------------------------------------------------------------------
# Runtime configuration — all secrets come from environment variables.
# The application refuses to boot if any required variable is missing.
# Add new required variables to this list; document them in .env.example.
# ---------------------------------------------------------------------------

if config_env() == :prod do
  required_vars = [
    "KRAKEN_API_KEY",
    "KRAKEN_API_SECRET",
    "TELEGRAM_BOT_TOKEN",
    "TELEGRAM_CHAT_ID",
    "DATABASE_URL",
    "SECRET_KEY_BASE",
    "LIVE_VIEW_SIGNING_SALT",
    "OPERATOR_USERNAME",
    "OPERATOR_PASSWORD_HASH",
    "OPERATOR_TOTP_SECRET"
  ]

  missing =
    Enum.filter(required_vars, fn var -> System.get_env(var) in [nil, ""] end)

  if missing != [] do
    raise """
    Missing required environment variables: #{Enum.join(missing, ", ")}
    See .env.example for the full list and descriptions.
    """
  end
end
