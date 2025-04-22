defmodule Gno.Manifest do
  use Gno.Manifest.Type
  use Grax.Schema

  schema Gno.Manifest do
    link service: Gno.manifestService(), type: Gno.Service, required: true

    field :graph, required: true
    field :load_path, required: true
  end

  @environments Application.compile_env(:gno, :environments, ~w[prod dev test]a)

  # Note: We can't use `Mix.env/0` directly because:
  # - At compile time, when Gno is used as a dependency, `Mix.env/0` would always return `:prod`
  # - At runtime, `Mix.env/0` is not available since Mix is not part of releases
  @env Application.compile_env(:gno, :env)

  @doc """
  Returns the currently configured environment.

  The environment is used to determine which manifest files to load. Files can be environment-specific
  by either placing them in an environment subdirectory (e.g. `prod/manifest.ttl`) or by using an
  environment suffix (e.g. `manifest.prod.ttl`). See `Gno.Manifest.LoadPath` for details.

  The environment is configured via the `:env` configuration option:

      config :gno, env: Mix.env()

  The environment can also be set via the `GNO_ENV` or `MIX_ENV` environment variables.

  Only environments in the result of `environments/0` are supported.
  """
  @spec env(keyword()) :: atom()
  def env(opts \\ []) do
    opts
    |> Keyword.get(
      :env,
      System.get_env("GNO_ENV") || System.get_env("MIX_ENV") || @env ||
        raise("""
        No environment configured. Please set the :gno environment via the `:env` configuration option:

            config :gno, env: Mix.env()

        Alternatively, you can set the environment via the `GNO_ENV` or `MIX_ENV` environment variables.
        """)
    )
    |> to_env()
  end

  defp to_env(env) when is_binary(env),
    do: env |> String.downcase() |> String.to_atom() |> to_env()

  defp to_env(env) when env in @environments, do: env

  defp to_env(env),
    do: raise("Invalid environment: #{inspect(env)}; must be one of #{inspect(@environments)}")

  @doc """
  Returns the supported environments for `env/1`.

  The environments are configured via the `:environments` configuration option
  and defaults to `#{inspect(@environments)}`:

      config :gno, :environments, [:prod, :dev, :test, :ci]
  """
  def environments, do: @environments
end
