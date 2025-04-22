import Config

config :gno, env: Mix.env()

config :sparql_client,
  protocol_version: "1.1",
  update_request_method: :direct

config :tesla, adapter: Tesla.Adapter.Hackney

import_config "#{Mix.env()}.exs"
